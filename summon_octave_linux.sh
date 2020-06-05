#!/bin/bash

octver=4.4.1

set -o errexit
set -o pipefail

scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
scriptpath=$scriptdir/$( basename "${BASH_SOURCE[0]}" )

container_tag=octave_linux_build
container_user=developer
container_group=developer
container_name=$container_tag

container_rootdir=/home/$container_user/octave-linux
if [ "$1" == __container_build__ ]; then
    rootdir=$container_rootdir
else
    rootdir=$(pwd)/$(basename $container_rootdir)
fi
    
octprefix=$rootdir/plx-octave-$octver
srcroot=$rootdir/src
buildroot=$rootdir/build
instroot=$rootdir/install
qtroot=$instroot/qt5

depsdir=lib


ncores="${NCORES:-4}"


create_container_image()
{
    uid=`id -u`
    gid=`id -g`
    docker build -t $container_tag - <<EOF

FROM centos:7

#RUN yum -y update

RUN yum -y install \
    sudo \
    gcc gcc-c++ \
    binutils \
    autogen \
    strip \
    perl \
    make cmake \
    patch \
    pkg-config \
    git \ 
    bzip2 unzip gzip tar \
    which \
    texinfo \
    chrpath \
    file \
    wget

RUN yum -y install \
    mesa-libGL-devel \
    mesa-libGLU-devel \
    libxkbcommon-devel \
    libxkbcommon-x11-devel

RUN yum -y install \
    autoconf       \
    automake && \
    yum -y remove automake && \
    pushd /root && \
    curl -L -O http://ftp.gnu.org/gnu/automake/automake-1.14.tar.gz && \
    tar --no-same-owner -zxf automake-1.14.tar.gz && \
    cd automake-1.14 && \
    ./configure --prefix=/usr && \
    make && make install && \
    cd .. && rm -rf automake-1.14 && rm automake-1.14.tar.gz && popd \
    && \
    pushd /root && \
    curl -L -O http://ftp.gnu.org/gnu/libtool/libtool-2.4.6.tar.gz && \
    tar --no-same-owner -zxf libtool-2.4.6.tar.gz && \
    cd libtool-2.4.6 && \
    ./configure --prefix=/usr && \
    make && make install && \
    cd .. && rm -rf libtool-2.4.6 && rm libtool-2.4.6.tar.gz && popd

RUN yum -y install \
    freetype-devel \
    fontconfig-devel

RUN yum -y install epel-release && \
    yum -y install patchelf

RUN bash -c ' \
        groupadd -g ${gid} ${container_group} && \
        useradd -u ${uid} -g ${gid} -G wheel -m -s /bin/bash --no-log-init ${container_user} \
        '
RUN echo "$container_user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-usernopasswd

USER $container_user:$container_group
ENV HOME /home/$container_user

CMD bash

EOF
}


delete_container_image()
{
    docker image rm $container_tag
} 


elf_strip()
{
    find $octprefix -executable -type f -exec bash -c "file {} | grep -i elf -q && strip -g {}" \;
}


do_make()
{
    local target=${1:-'build'}
    make -j$ncores $1 2>&1 | tee ${target}log.txt
}


fetch_src()
{ 
    ( cd $srcroot && \
      curl -L -O $1 && \
      tar xvf `basename $1` )
}


enter_builddir()
{
    rm -rf $buildroot/$1
    mkdir -p $buildroot/$1
    cd $buildroot/$1
}


build_gcc()
{
    local ver=4.8.5

    fetch_src http://ftp.gnu.org/gnu/gcc/gcc-$ver/gcc-$ver.tar.gz

    ( cd $srcroot/gcc-$ver && \
	./contrib/download_prerequisites )

    enter_builddir gcc
    $srcroot/gcc-$ver/configure \
    	--prefix=$instroot \
    	--enable-languages=c,c++,fortran \
    	--disable-multilib \
    2>&1 | tee conflog.txt

    do_make
    do_make check || true
    do_make install
}


setup_compilers()
{
    sudo rpm -e --nodeps \
	gcc \
	gcc-c++ \
	cpp \
	libgomp \
	libmpc \
	libstdc++-devel \
	mpfr

    sudo yum install -y \
	glibc-headers \
	glibc-devel

    export CC=$instroot/bin/gcc
    export CXX=$instroot/bin/g++
    export FC=$instroot/bin/gfortran
    export F77=$instroot/bin/gfortran
}


setup_env()
{
    export PATH=$instroot/bin:$qtroot/bin:/bin:/sbin:/usr/bin:/usr/sbin
    export PKG_CONFIG_PATH=$instroot/lib/pkgconfig:$instroot/lib64/pkgconfig:$qtroot/lib/pkgconfig:/usr/lib/pkgconfig:/lib64/pkgconfig:/usr/lib/pkgconfig

    export LD_LIBRARY_PATH=$instroot/lib64:$instroot/lib:$qtroot/lib

    export LDFLAGS="-L$instroot/lib -L$instroot/lib64 -L$qtroot/lib"
    export CPPFLAGS="-I$instroot/include -I$qtroot/include"

    export TERM=xterm-256color
}


build_lapack()
{
    local ver=3.8.0

    fetch_src http://www.netlib.org/lapack/lapack-$ver.tar.gz

    enter_builddir lapack
    cmake $srcroot/lapack-$ver \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX=$instroot \
	-DBUILD_SHARED_LIBS=ON \
	-DLAPACKE=OFF \
	-DBUILD_DEPRECATED=ON \
    2>&1 | tee conflog.txt
    
    do_make
    do_make test
    do_make install
}


build_pcre()
{
    local ver=8.43

    fetch_src https://ftp.pcre.org/pub/pcre/pcre-8.43.tar.gz

    enter_builddir pcre
    $srcroot/pcre-$ver/configure \
	--prefix=$instroot \
	--disable-silent-rules \
	--enable-shared \
	--disable-static \
	2>&1 | tee conflog.txt

    do_make
    do_make test
    do_make install
}


build_termcap()
{
    local ver=1.3.1

    fetch_src http://ftp.gnu.org/gnu/termcap/termcap-$ver.tar.gz

    enter_builddir termcap
    cp -a $srcroot/termcap-$ver/* .

    $CC -fPIC -c termcap.c -DHAVE_STRING_H=1 -DHAVE_UNISTD_H=1 -DSTDC_HEADERS=1
    $CC -fPIC -c tparam.c -DHAVE_STRING_H=1 -DHAVE_UNISTD_H=1 -DSTDC_HEADERS=1
    $CC -fPIC -c version.c -DHAVE_STRING_H=1 -DHAVE_UNISTD_H=1 -DSTDC_HEADERS=1

    $CC -shared -Wl,-soname,libtermcap.so.1 \
        -o libtermcap.so.1.3.1 termcap.o tparam.o version.o

    install -D -m755 libtermcap.so.1.3.1 $instroot/lib/libtermcap.so.1.3.1
    ln -f -s libtermcap.so.1.3.1 $instroot/lib/libtermcap.so.1
    ln -f -s libtermcap.so.1 $instroot/lib/libtermcap.so
    install -D -m644 termcap.h $instroot/include/termcap.h
    for infofile in termcap.info*
    do install -D -m644 "${infofile}" "${instroot}/share/info/${infofile}"
    done
}


build_readline()
{
    local ver=8.0

    fetch_src ftp://ftp.gnu.org/gnu/readline/readline-$ver.tar.gz

    patch -p1 -d $srcroot/readline-$ver < $rootdir/common_files/readline-pipe-eof.patch

    enter_builddir readline
    $srcroot/readline-$ver/configure \
	--prefix=$instroot \
	--enable-shared \
	--disable-static \
	--without-curses \
	2>&1 | tee conflog.txt

    do_make
    do_make install
}


# build_freetype()
# {
#     local ver=2.10.1

#     fetch_src https://download.savannah.gnu.org/releases/freetype/freetype-$ver.tar.gz

#     enter_builddir freetype
#     $srcroot/freetype-$ver/configure \
# 	--prefix=$instroot \
# 	--enable-shared \
# 	--disable-static 
# 	2>&1 | tee conflog.txt

#     do_make
#     do_make install
# }


# build_fontconfig()
# {
#     local ver=2.13.92

#     fetch_src https://www.freedesktop.org/software/fontconfig/release/fontconfig-$ver.tar.gz

#     enter_builddir fontconfig
#     $srcroot/fontconfig-$ver/configure \
# 	--prefix=$instroot \
# 	--disable-silent-rules \
# 	--enable-shared \
# 	--disable-static \
# 	2>&1 | tee conflog.txt

#     do_make
#     do_make install
# }


build_gl2ps() 
{
    local ver=1.4.0

    fetch_src https://geuz.org/gl2ps/src/gl2ps-$ver.tgz

    enter_builddir gl2ps
    cmake $srcroot/gl2ps-$ver-source \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX=$instroot \
	-DBUILD_SHARED_LIBS=ON \
	-DENABLE_PNG=OFF
    2>&1 | tee conflog.txt
    
    do_make
    do_make install
}


build_qt()
{
    local ver=5.9.7
    local _vermm=${ver%.*}

    fetch_src http://download.qt.io/official_releases/qt/$_vermm/$ver/submodules/qtbase-opensource-src-$ver.tar.xz
    fetch_src http://download.qt.io/official_releases/qt/$_vermm/$ver/submodules/qttools-opensource-src-$ver.tar.xz
    

    enter_builddir qtbase
    $srcroot/qtbase-opensource-src-$ver/configure \
    	--prefix=$qtroot \
    	-opensource -confirm-license \
    	-release \
    	-no-sse3 -no-ssse3 -no-sse4.1 -no-sse4.2 -no-avx \
    	-no-libudev \
    	-qt-xcb -qt-zlib -qt-libpng -qt-libjpeg \
    	-make libs -make tools \
    2>&1 | tee conflog.txt
    
    do_make
    do_make install


    enter_builddir qttools
    $qtroot/bin/qmake $srcroot/qttools-opensource-src-$ver

    do_make
    do_make install
}


patch_octave()
{
    patch -p1 -d $srcroot/octave-$octver < $rootdir/common_files/bug_49053_1.patch
    patch -p1 -d $srcroot/octave-$octver < $rootdir/common_files/bug_50025_1.patch
    patch -p1 -d $srcroot/octave-$octver < $rootdir/common_files/source_file.patch
    patch -p1 -d $srcroot/octave-$octver < $rootdir/common_files/eval_string_reader.patch

    patch -p1 -d $srcroot/octave-$octver < $rootdir/common_files/0cedd1e23c1f.cset
    patch -p1 -d $srcroot/octave-$octver < $rootdir/common_files/377f069841c1.cset
    patch -p1 -d $srcroot/octave-$octver < $rootdir/common_files/bug_51632_list_global_OCTAVE_HOME.cset

    patch -p1 -d $srcroot/octave-$octver < $rootdir/common_files/version-rcfile.patch
}


build_octave()
{
    local ver=$octver

    fetch_src https://ftp.gnu.org/gnu/octave/octave-$ver.tar.xz

    patch_octave

    ( cd $srcroot/octave-$ver && autoreconf -f -i )
    
    enter_builddir octave
    $srcroot/octave-$ver/configure      \
    	--prefix=$octprefix             \
	--disable-silent-rules          \
	--enable-shared	                \
	--disable-static	        \
	--enable-link-all-dependencies  \
	--disable-java 		       	\
	--disable-docs 		       	\
   	2>&1 | tee conflog.txt
	
    do_make
    do_make check
    do_make install
}


dependencies()
{
    local fname=$1
    ldd "$1" | grep '.*=>.*' | sed -e 's/.*=>[[:space:]]*//' | sed -e 's/(.*)//' | sed -e '/^[[:space:]]*$/d'
}


elf_list()
{
    local dir=$1
    find $dir -executable -type f -exec bash -c "file {} | grep -i elf -q && echo {}" \;
}


blacklisted()
{
    local lib=$1
    grep -q $(basename $lib) <<EOF

libstdc++.so.6
libgomp.so.1
libgcc_s.so.1

EOF
}


gather_dependencies()
{
    while read -r elf; do

	echo "Processing elf file $elf ..."

	while read -r dep; do 

	    if $(echo $dep | grep -q "^${instroot}") && ! $(blacklisted $dep); then
		echo "[COPY] $dep"
		[ -e $octprefix/$depsdir/$(basename $dep) ] || cp -L $dep $octprefix/$depsdir
	    else
		echo "[SKIP] $dep"
	    fi

	done < <(dependencies $elf)

	echo ""

    done < <(elf_list $octprefix)
}


elf_set_rpath()
{
    while read -r elf; do

	echo "Processing elf file $elf ..."
	
	local elfdir=$(dirname $elf)

	local paths=()
	paths+=("\$ORIGIN")
	paths+=(":\$ORIGIN/$(realpath --relative-to=$elfdir $octprefix/$depsdir)")
	paths+=(":\$ORIGIN/$(realpath --relative-to=$elfdir $octprefix/lib/octave/$octver)")
	local rpath=$(IFS= ; echo "${paths[*]}")

	echo "$rpath"
	echo

	patchelf --set-rpath "$rpath" $elf

    done < <(elf_list $octprefix)
}


copy_qt_plugins()
{
    mkdir -p $octprefix/$depsdir/plugins
    cp -a $qtroot/plugins/* $octprefix/$depsdir/plugins
}


startup_script()
{
    local dir=$(dirname $1)
    local link=$(basename $1)

    local octhome_rel=$2
    local hooks=($3 $4 $5)

    pushd $dir
    
    [ -L $link ] || exit -1 

    local script=$link-$octver
    local oldbinary=$link-$octver
    local newbinary=$oldbinary.bin
    
    rm $link
    mv $oldbinary $newbinary

    cat > $script <<EOF
#!/bin/sh
scriptdir=\`dirname "\$0"\`
tmp=\${scriptdir#?}
if [ \${scriptdir%\$tmp} != "/" ]; then
    scriptdir=\$PWD/\$scriptdir
fi
export OCTAVE_HOME=\$( cd "\$scriptdir/$octhome_rel" && pwd )
export LD_LIBRARY_PATH=\$OCTAVE_HOME/lib/octave/$octver:\$OCTAVE_HOME/$depsdir
EOF

    for f in ${hooks[@]}; do
	echo "$($f)" >> $script
    done

    cat >> $script <<EOF
exec "\$scriptdir/$newbinary" "\$@"
EOF

    chmod a+x $script
    ln -s $script $link

    popd
}


_script_qt_plugins()
{
    cat <<EOF
export QT_PLUGIN_PATH="\$OCTAVE_HOME/$depsdir/plugins"   
EOF
}


_script_mkoctfile_vars()
{
    local octhome="\$OCTAVE_HOME"
    local depsdir=$octhome/$depsdir
    
    cat <<EOF
: "\${BLAS_LIBS=-L$depsdir -lblas}"
: "\${CC=gcc}"
: "\${CXX=g++ -std=gnu++11}"
: "\${CPPFLAGS= }"
: "\${DL_LD=\$CXX}"
: "\${F77=gfortran}"
: "\${FLIBS=-L$depsdir -lgfortran -lquadmath -lm}"
: "\${LAPACK_LIBS=-L$depsdir -llapack}"
: "\${LD_CXX=\$CXX}"
: "\${OCTAVE_LINK_DEPS=-L$depsdir -lfreetype -lz -lGL -lGLU -lfontconfig -lX11 -lgl2ps -llapack -lblas -lreadline -ltermcap  -lpcre -ldl -lgfortran -lm -lquadmath -lutil}"
: "\${OCTAVE_LINK_OPTS= }"
: "\${OCT_LINK_OPTS= }"
export BLAS_LIBS CC CXX CPPFLAGS DL_LD F77 FLIBS LAPACK_LIBS LD_CXX OCTAVE_LINK_DEPS OCTAVE_LINK_OPTS OCT_LINK_OPTS
EOF
}


remove_doc()
{
    rm -rf $octprefix/share/octave/$octver/doc
}


install_forge_packages()
{
    local ctrlpack=control-3.2.0.tar.gz
    local signalpack=signal-1.4.1.tar.gz
    
    ( cd $srcroot \
	&& curl -L -o $ctrlpack   "https://octave.sourceforge.io/download.php?package=$ctrlpack" \
	&& curl -L -o $signalpack "https://octave.sourceforge.io/download.php?package=$signalpack" )


    local prefix_setup_code=$(cat <<-EOF
	pkg_prefix = fullfile (OCTAVE_HOME (), 'share', 'octave', 'packages');
	pkg_archprefix = fullfile (OCTAVE_HOME (), 'lib', 'octave', 'packages');
	pkg_list = fullfile (OCTAVE_HOME (), 'share', 'octave', 'octave_packages');
	pkg ('prefix', pkg_prefix, pkg_archprefix);
	pkg ('global_list', pkg_list);
	clear ('pkg_prefix', 'pkg_archprefix', 'pkg_list');
EOF
    )
    
    $octprefix/bin/octave-cli <<-EOF

	$prefix_setup_code

	old_cxx_flags = getenv ('CXXFLAGS')
	setenv ('CXXFLAGS', '-std=gnu++11 -g -O2')

	pkg ('install', '$srcroot/$ctrlpack',   '-global', '-verbose')
	pkg ('install', '$srcroot/$signalpack', '-global', '-verbose')

	setenv ('CXXFLAGS', old_cxx_flags)

EOF

    local rcfile=$octprefix/share/octave/$octver/m/startup/octaverc
    echo >> $rcfile
    echo "## Setup package paths" >> $rcfile
    echo "$prefix_setup_code" >> $rcfile
}


package_octave()
{
    install_forge_packages

    mkdir -p $octprefix/$depsdir

    copy_qt_plugins
    gather_dependencies

    elf_strip
    elf_set_rpath

    # setup helper scripts
    startup_script "$octprefix/bin/octave"         ".."  _script_qt_plugins
    startup_script "$octprefix/bin/octave-cli"     ".."
    startup_script "$octprefix/bin/mkoctfile"      ".."  _script_mkoctfile_vars
    startup_script "$octprefix/bin/octave-config"  ".."

    remove_doc

    ( cd $rootdir && \
	tar -cvzf plx-octave-${octver}_linux.tar.gz plx-octave-$octver )
}


container_entrypoint()
{
    mkdir -p $srcroot
    mkdir -p $buildroot
    mkdir -p $instroot

    build_gcc
    
    setup_compilers
    setup_env

    build_lapack

    build_pcre

    build_termcap
    build_readline

#   build_freetype
#   build_fontconfig

    build_gl2ps

    build_qt

    build_octave
  
    package_octave
}


do_build()
{
    mkdir -p $rootdir
    cp $scriptpath $rootdir/build_script.sh
    cp -a $scriptdir/common_files $rootdir

    local cmd="\
    	 docker run --rm -t -i \
         --name $container_name \
	 -u $container_user:$container_group \
	 -v $rootdir:$container_rootdir \
	 $container_tag \
	 bash -c 'cd $container_rootdir && ./build_script.sh __container_build__' \
    "

    echo $cmd
    eval $cmd
}


main()
{
    create_container_image
    do_build
#   delete_container_image
}



## Entry point

if [ "$#" -eq 0 ]; then
    if [ `id -u` -eq 0 ]; then
	echo "Please do not run this script as root."
	exit 1
    fi
    main
    exit
fi

case "$1" in
    __container_build__)
	container_entrypoint
	exit
	;;

    *)
	echo "Error: unknown command $1"
	exit 1
	;;
esac
