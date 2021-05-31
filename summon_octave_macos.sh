#!/bin/bash

#
# Build system: Xcode 10.1 (MacOSX10.14.sdk).
# Make sure the correct SDK is returned by 'xcrun --show-sdk-path'.
#

octver=4.4.1

set -o errexit
set -o pipefail

scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
scriptpath=$scriptdir/$( basename "${BASH_SOURCE[0]}" )

rootdir=$(pwd)/octave-macos
    
octprefix=$rootdir/plx-octave-$octver
srcroot=$rootdir/src
buildroot=$rootdir/build
instroot=$rootdir/install
qtroot=$instroot/qt5

depsdir=lib


# warning: this has to be compatible with the chosen Qt version
macosx_deployment_target=10.13
export MACOSX_DEPLOYMENT_TARGET=$macosx_deployment_target


ncores="${NCORES:-4}"


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


build_buildtools()
{
    # m4
    (
	local ver=1.4.18

	fetch_src ftp://ftp.gnu.org/gnu/m4/m4-$ver.tar.xz
	enter_builddir m4
    	$srcroot/m4-$ver/configure \
    	    --prefix=$instroot \
    	    --enable-shared \
    	    --disable-static \
    	    2>&1 | tee conflog.txt
	do_make
	do_make install
    )

    
    # autoconf
    (
	local ver=2.69
	
    	fetch_src ftp://ftp.gnu.org/gnu/autoconf/autoconf-$ver.tar.gz
	enter_builddir autoconf
    	$srcroot/autoconf-$ver/configure \
    	    --prefix=$instroot \
    	    --enable-shared \
    	    --disable-static \
    	    2>&1 | tee conflog.txt
	do_make
	do_make install
    )
    
    # automake
    (
	local ver=1.16
	
    	fetch_src ftp://ftp.gnu.org/gnu/automake/automake-$ver.tar.gz
	enter_builddir automake
    	$srcroot/automake-$ver/configure \
    	    --prefix=$instroot \
    	    --enable-shared \
    	    --disable-static \
    	    2>&1 | tee conflog.txt
	do_make
	do_make install
    )

    # libtool
    (
	local ver=2.4.6
	
    	fetch_src ftp://ftp.gnu.org/gnu/libtool/libtool-$ver.tar.gz
	enter_builddir libtool
    	$srcroot/libtool-$ver/configure \
    	    --prefix=$instroot \
    	    --enable-shared \
    	    --disable-static \
    	    2>&1 | tee conflog.txt
	do_make
	do_make install
    )

    
    # sed
    (
	local ver=4.7
	
    	fetch_src ftp://ftp.gnu.org/gnu/sed/sed-$ver.tar.xz
	enter_builddir sed
    	$srcroot/sed-$ver/configure \
    	    --prefix=$instroot \
    	    --enable-shared \
    	    --disable-static \
    	    2>&1 | tee conflog.txt
	do_make
	do_make install
    )


    # pkg-config
    (
	local ver=0.29.2
	
    	fetch_src https://pkg-config.freedesktop.org/releases/pkg-config-$ver.tar.gz
	enter_builddir pkg-config
    	$srcroot/pkg-config-$ver/configure \
    	    --prefix=$instroot \
    	    --enable-shared \
    	    --disable-static \
    	    --with-internal-glib \
    	    2>&1 | tee conflog.txt
	do_make
	do_make install
    )

    # gettext
    (
	local ver=0.20.1
	
	fetch_src https://ftp.gnu.org/gnu/gettext/gettext-$ver.tar.gz
	enter_builddir gettext
	$srcroot/gettext-$ver/configure \
	    --prefix=$instroot \
	    --enable-shared \
	    --disable-static \
            --with-included-gettext \
            --with-included-glib \
            --with-included-libcroco \
            --with-included-libunistring \
            --disable-java \
            --disable-csharp \
            --without-git \
            --without-cvs \
            --without-xz \
	    2>&1 | tee conflog.txt
	do_make
	do_make install
    )

    # cmake
    (
	local ver=3.15.4
    
	fetch_src https://github.com/Kitware/CMake/releases/download/v$ver/cmake-$ver.tar.gz
	enter_builddir cmake
	$srcroot/cmake-$ver/bootstrap -- -DCMAKE_BUILD_TYPE:STRING=Release -DCMAKE_INSTALL_PREFIX:STRING=$instroot
	do_make
	do_make install
    )
}


build_gcc()
{
    local ver=9.2.0
    
    fetch_src http://ftp.gnu.org/gnu/gcc/gcc-$ver/gcc-$ver.tar.gz

    ( cd $srcroot/gcc-$ver && \
	./contrib/download_prerequisites )

    enter_builddir gcc
    $srcroot/gcc-$ver/configure \
    	--prefix=$instroot \
    	--enable-languages=c,c++,fortran \
    	--disable-multilib \
 	--with-native-system-header-dir=/usr/include \
	--with-sysroot=$(xcrun --show-sdk-path) \
    2>&1 | tee conflog.txt

    do_make
    do_make check || true
    do_make install
}


setup_compilers()
{
    export CC="/usr/bin/gcc -mmacosx-version-min=$macosx_deployment_target"
    export CXX="/usr/bin/g++ -mmacosx-version-min=$macosx_deployment_target"
    export FC="$instroot/bin/gfortran -mmacosx-version-min=$macosx_deployment_target"
    export F77="$instroot/bin/gfortran -mmacosx-version-min=$macosx_deployment_target"
}


setup_env()
{
    export PATH=$instroot/bin:$qtroot/bin:$brewroot/bin:/bin:/sbin:/usr/bin:/usr/sbin
    export PKG_CONFIG_PATH=$instroot/lib/pkgconfig:$instroot/lib64/pkgconfig:$qtroot/lib/pkgconfig:/usr/lib/pkgconfig:/lib64/pkgconfig:/usr/lib/pkgconfig

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

    install_name_tool -id $instroot/lib/liblapack.3.dylib $instroot/lib/liblapack.$ver.dylib
    install_name_tool -id $instroot/lib/libblas.3.dylib $instroot/lib/libblas.$ver.dylib
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

    $CC -DHAVE_STRING_H=1 -DHAVE_UNISTD_H=1 -DSTDC_HEADERS=1 -fPIC  -c termcap.c
    $CC -DHAVE_STRING_H=1 -DHAVE_UNISTD_H=1 -DSTDC_HEADERS=1 -fPIC -c tparam.c
    $CC -DHAVE_STRING_H=1 -DHAVE_UNISTD_H=1 -DSTDC_HEADERS=1 -fPIC -c version.c

    $CC -dynamiclib -install_name $instroot/lib/libtermcap.1.3.1.dylib -o libtermcap.1.3.1.dylib termcap.o tparam.o version.o

    install -m755 libtermcap.1.3.1.dylib $instroot/lib
    ln -f -s libtermcap.1.3.1.dylib $instroot/lib/libtermcap.dylib
    install -m644 termcap.h $instroot/include
    for infofile in termcap.info*; do
	install -m644 "$infofile" "$instroot/share/info"
    done
}


build_readline()
{
    local ver=8.0

    fetch_src ftp://ftp.gnu.org/gnu/readline/readline-$ver.tar.gz

    patch -p1 -d $srcroot/readline-$ver < $scriptdir/common_files/readline-pipe-eof.patch
    
    enter_builddir readline
    $srcroot/readline-$ver/configure \
    	--prefix=$instroot \
    	--enable-shared \
    	--disable-static \
	--without-curses \
    	2>&1 | tee conflog.txt

    make SHLIB_LIBS="-L$instroot/lib -ltermcap"
    do_make install
}


build_freetype()
{
    local ver=2.10.1

    fetch_src https://download.savannah.gnu.org/releases/freetype/freetype-$ver.tar.gz

    enter_builddir freetype
    $srcroot/freetype-$ver/configure \
	--prefix=$instroot \
	--enable-shared \
	--disable-static 
	2>&1 | tee conflog.txt

    do_make
    do_make install
}


build_fontconfig()
{
    local ver=2.13.92

    fetch_src https://www.freedesktop.org/software/fontconfig/release/fontconfig-$ver.tar.gz

    enter_builddir fontconfig
    $srcroot/fontconfig-$ver/configure \
	--prefix=$instroot \
	--disable-silent-rules \
	--enable-shared \
	--disable-static \
	--with-add-fonts=/System/Library/Fonts,/Library/Fonts \
	2>&1 | tee conflog.txt

    do_make
    do_make install
}


build_gl2ps() 
{
    local ver=1.4.0

    fetch_src https://geuz.org/gl2ps/src/gl2ps-$ver.tgz

    enter_builddir gl2ps
    cmake $srcroot/gl2ps-$ver-source \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX=$instroot \
	-DBUILD_SHARED_LIBS=ON \
	-DENABLE_PNG=OFF \
    2>&1 | tee conflog.txt
    
    do_make
    do_make install

    install_name_tool -id $instroot/lib/libgl2ps.1.dylib $instroot/lib/libgl2ps.$ver.dylib
}


build_qt()
{
    local ver=5.12.8
    local _vermm=${ver%.*}

    fetch_src http://download.qt.io/official_releases/qt/$_vermm/$ver/submodules/qtbase-everywhere-src-$ver.tar.xz
    fetch_src http://download.qt.io/official_releases/qt/$_vermm/$ver/submodules/qttools-everywhere-src-$ver.tar.xz
    
    local mkspec=$srcroot/qtbase-everywhere-src-$ver/mkspecs/common/macx.conf
    grep -q 'QMAKE_MACOSX_DEPLOYMENT_TARGET = ' $mkspec
    sed -E -e 's/(QMAKE_MACOSX_DEPLOYMENT_TARGET = )(10.[0-9]+)/\1'$macosx_deployment_target'/' -i.orig $mkspec

    patch -p1 -d $srcroot/qtbase-everywhere-src-$ver < $scriptdir/macos_files/cocoa_screen.patch

    enter_builddir qtbase
    $srcroot/qtbase-everywhere-src-$ver/configure \
    	--prefix=$qtroot \
    	-opensource -confirm-license \
    	-release \
    	-no-framework \
    	-no-rpath \
    	-no-dbus -no-compile-examples -nomake examples -no-sql-mysql -no-feature-gestures \
    	-make libs -make tools \
    2>&1 | tee conflog.txt
    
    do_make
    do_make install


    enter_builddir qttools
    $qtroot/bin/qmake $srcroot/qttools-everywhere-src-$ver

    do_make
    do_make install

    find $qtroot/lib -iname '*.la' -exec sed "s/-framework\s\+\S\+[^']//g" -i.orig {} \;
}


build_glpk()
{
    local ver=5.0

    fetch_src https://ftp.gnu.org/gnu/glpk/glpk-$ver.tar.gz

    enter_builddir glpk
    $srcroot/glpk-$ver/configure \
	--prefix=$instroot \
	--disable-silent-rules \
	--enable-shared \
	--disable-static \
	2>&1 | tee conflog.txt

    do_make
    do_make check
    do_make install
}


build_rapidjson() 
{
    local ver=1.1.0

    fetch_src https://github.com/Tencent/rapidjson/archive/v$ver.tar.gz
    
    patch -p1 -d $srcroot/rapidjson-$ver < $scriptdir/common_files/rapidjson_prettywriter.patch

    enter_builddir rapidjson
    cmake $srcroot/rapidjson-$ver \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX=$instroot \
	-DRAPIDJSON_BUILD_DOC=OFF \
	-DRAPIDJSON_BUILD_EXAMPLES=OFF \
	-DRAPIDJSON_BUILD_TESTS=OFF \
	    2>&1 | tee conflog.txt
    
    do_make
    do_make install
}


patch_octave()
{
    patch -p1 -d $srcroot/octave-$octver < $scriptdir/common_files/bug_49053_1.patch
    patch -p1 -d $srcroot/octave-$octver < $scriptdir/common_files/bug_50025_1.patch
#   patch -p1 -d $srcroot/octave-$octver < $scriptdir/macos_files/octave_dock_icon.patch
    patch -p1 -d $srcroot/octave-$octver < $scriptdir/common_files/source_file.patch
    patch -p1 -d $srcroot/octave-$octver < $scriptdir/common_files/eval_string_reader.patch
    patch -p1 -d $srcroot/octave-$octver < $scriptdir/common_files/jsonencode_jsondecode.patch

    patch -p1 -d $srcroot/octave-$octver < $scriptdir/common_files/0cedd1e23c1f.cset
    patch -p1 -d $srcroot/octave-$octver < $scriptdir/common_files/377f069841c1.cset
    patch -p1 -d $srcroot/octave-$octver < $scriptdir/common_files/bug_51632_list_global_OCTAVE_HOME.cset

    patch -p1 -d $srcroot/octave-$octver < $scriptdir/common_files/version-rcfile.patch

    cat $scriptdir/macos_files/disable_dock_icon.patch \
	| sed -e 's|<SUBSTITUTE_ME_PLIST_FILE>|'$scriptdir/macos_files/octave-info.plist'|' \
	| patch -p1 -d $srcroot/octave-$octver
    patch -p1 -d $srcroot/octave-$octver < $scriptdir/macos_files/disable_insert_text_button.patch
}


build_octave()
{
    local ver=$octver

    fetch_src https://ftp.gnu.org/gnu/octave/octave-$ver.tar.xz

    patch_octave

    ( cd $srcroot/octave-$ver && autoreconf -f -i )
    
    enter_builddir octave
    $srcroot/octave-$ver/configure \
    	--prefix=$octprefix \
	--enable-shared \
	--disable-static \
	--disable-java \
	--disable-docs \
	--without-x \
	--enable-readline \
	--with-blas="-L$instroot/lib -lblas"   \
	--with-lapack="-L$instroot/lib -llapack" \
	--with-libiconv-prefix=/usr \
	--without-libpth-prefix \
	--with-pcre-includedir="$instroot/include" \
	--with-pcre-libdir="$instroot/lib" \
	--with-freetype \
	--with-fontconfig-includedir="$instroot/include" \
	--with-fontconfig-libdir="$instroot/lib" \
	--without-openssl \
	--without-arpack \
	--without-curl \
	--without-fftw3 \
	--without-fftw3f \
	--without-fltk \
	--without-gnuplot \
	--without-magick \
	--without-hdf5 \
	--without-qhull \
	--without-qrupdate \
	--without-sndfile \
	--without-portaudio \
	--without-suitesparseconfig \
	--without-amd \
	--without-camd \
	--without-colamd \
	--without-ccolamd \
	--without-cholmod \
	--without-cxsparse \
	--without-umfpack \
	--without-klu \
	--without-sundials_nvecserial \
	--without-sundials_ida \
   	2>&1 | tee conflog.txt

    do_make
    do_make check
    do_make install
}


build_texinfo()
{
    local ver=6.7

    fetch_src https://ftp.gnu.org/gnu/texinfo/texinfo-$ver.tar.xz

    enter_builddir texinfo
    $srcroot/texinfo-$ver/configure \
    	--prefix=$instroot \
    	--enable-shared \
    	--disable-static \
    	2>&1 | tee conflog.txt

    do_make
    do_make install
}


build_libtiff()
{
    local ver=4.1.0

    fetch_src https://download.osgeo.org/libtiff/tiff-$ver.tar.gz

    enter_builddir libtiff
    $srcroot/tiff-$ver/configure \
	--prefix=$instroot \
	--without-x \
	2>&1 | tee conflog.txt

    do_make
    do_make install
}


build_ghostscript()
{
    gsver=9.50
    
    local ver=$gsver
    local _ver="${ver//./}"

    fetch_src https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs$_ver/ghostscript-$ver.tar.gz

    enter_builddir ghostscript
    $srcroot/ghostscript-$ver/configure \
	--prefix=$instroot \
	--disable-cups \
	--disable-gtk \
	--without-x \
	--without-libidn \
	--with-system-libtiff \
	2>&1 | tee conflog.txt
    
    make -j$ncores GS_LIB_DEFAULT="" GS_DOCDIR="www.ghostscript.com/doc/$ver" 2>&1 | tee buildlog.txt
    do_make install
}


gather_dependencies()
{
    make_relocatable=$scriptdir/macos_files/make_relocatable.py

    $make_relocatable "$instroot" "$octprefix" "$octprefix/$depsdir"
}


copy_qt_plugins()
{
    mkdir -p $octprefix/$depsdir/plugins
    cp -a $qtroot/plugins/* $octprefix/$depsdir/plugins
}


copy_makeinfo()
{
    cp -L -a $instroot/bin/makeinfo $octprefix/bin/makeinfo

    local tmppatch=$(mktemp)
    cat $scriptdir/macos_files/makeinfo.patch > $tmppatch
    sed -e "s|__INSTROOT__|$instroot|g" -i $tmppatch
    patch -d $octprefix/bin -p0 < $tmppatch
    rm "$tmppatch"
        
    local rcfile=$octprefix/share/octave/$octver/m/startup/octaverc
    echo '' >> $rcfile
    echo "makeinfo_program (strcat ('\"', fullfile (OCTAVE_HOME (), 'bin', 'makeinfo'), '\"'));" >> $rcfile

    [ -d $instroot/lib/texinfo ] && cp -a $instroot/lib/texinfo $octprefix/lib
    [ -d $instroot/share/texinfo ] && cp -a $instroot/share/texinfo $octprefix/share
}


copy_ghostscript()
{
    cp -L -a $instroot/bin/gs $octprefix/bin/gs
    cp -a $instroot/share/ghostscript $octprefix/share
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


_script_ghostscript_libs()
{
    local ver=$gsver
    
    cat <<EOF
export GS_LIB="\$OCTAVE_HOME/share/ghostscript/$ver/lib"   
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
: "\${DL_LDFLAGS=-bundle}"
: "\${F77=gfortran}"
: "\${FLIBS=-L$depsdir -lgfortran -lquadmath -lm}"
: "\${LAPACK_LIBS=-L$depsdir -llapack}"
: "\${LD_CXX=\$CXX}"
: "\${LDFLAGS= }"
: "\${OCTAVE_LINK_DEPS=-L$depsdir -lfreetype -framework OpenGL -lfontconfig -framework Carbon -lgl2ps -llapack -lblas -lreadline -ltermcap -lpcre -ldl -lgfortran -lquadmath -lm -liconv}"
: "\${OCTAVE_LINK_OPTS= }"
: "\${OCT_LINK_OPTS= }"
: "\${SED=sed}"
export BLAS_LIBS CC CXX CPPFLAGS DL_LD DL_LDFLAGS F77 FLIBS LAPACK_LIBS LD_CXX LDFLAGS OCTAVE_LINK_DEPS OCTAVE_LINK_OPTS OCT_LINK_OPTS SED
EOF
}


setup_fontconfig()
{    
    mkdir -p $octprefix/etc
    cp -R -L $instroot/etc/fonts $octprefix/etc

    sed -e 's|<cachedir>'"$instroot"'.*</cachedir>|<cachedir>~/.cache/fontconfig</cachedir>|' -i'' $octprefix/etc/fonts/fonts.conf
}


_script_fontconfig_vars()
{
    local octhome="\$OCTAVE_HOME"

    cat <<EOF
export FONTCONFIG_PATH=$octhome/etc/fonts
export FONTCONFIG_FILE=$octhome/etc/fonts/fonts.conf
EOF
}


strip_objects()
{
    find $octprefix \( -type f -perm +111 ! -iname '*.la' -or -type f -iname '*.oct' -or -type f -iname '*.dylib' \) \
	 -exec bash -c 'file {} | grep -q -i Mach-O && (echo Stripping {} ...; strip -x -S {})' \;
}


remove_doc()
{
    rm -rf $octprefix/share/octave/$octver/doc
}


install_forge_packages()
{
    local ctrlpack=control-3.2.0.tar.gz
    local signalpack=signal-1.4.1.tar.gz
    local instrumentpack=instrument-control-0.7.0.tar.gz
    
    ( cd $srcroot \
	  && curl -L -o $ctrlpack   "https://octave.sourceforge.io/download.php?package=$ctrlpack" \
	  && curl -L -o $signalpack "https://octave.sourceforge.io/download.php?package=$signalpack" \
	  && curl -L -o $instrumentpack "https://octave.sourceforge.io/download.php?package=$instrumentpack" )

    # patch instrument-control package before installing
    tar -C $srcroot -xf $srcroot/$instrumentpack
    rm $srcroot/$instrumentpack
    patch -p1 -d $srcroot/${instrumentpack%.tar.gz} < $scriptdir/common_files/of-instrument-control-1-fixes.patch
    tar -C $srcroot -czf $srcroot/$instrumentpack ${instrumentpack%.tar.gz}
    rm -rf $srcroot/${instrumentpack%.tar.gz}
    
    local prefix_setup_code=$(cat <<-EOF
	pkg_prefix = fullfile (OCTAVE_HOME (), 'share', 'octave', 'packages');
	pkg_archprefix = fullfile (OCTAVE_HOME (), 'lib', 'octave', 'packages');
	pkg_list = fullfile (OCTAVE_HOME (), 'share', 'octave', 'octave_packages');
	pkg ('prefix', pkg_prefix, pkg_archprefix);
	pkg ('global_list', pkg_list);
	pkg ('local_list', pkg_list);
	clear ('pkg_prefix', 'pkg_archprefix', 'pkg_list');
EOF
    )
    
    $octprefix/bin/octave-cli <<-EOF

	$prefix_setup_code

	old_cxx_flags = getenv ('CXXFLAGS')
	setenv ('CXXFLAGS', '-std=gnu++11 -g -O2')

	pkg ('install', '$srcroot/$ctrlpack',   '-global', '-verbose')
	pkg ('install', '$srcroot/$signalpack', '-global', '-verbose')
	pkg ('install', '$srcroot/$instrumentpack', '-global', '-verbose')

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
    copy_makeinfo
    copy_ghostscript
    
    gather_dependencies
    
    startup_script "$octprefix/bin/octave"         ".."  _script_qt_plugins _script_fontconfig_vars _script_ghostscript_libs
    startup_script "$octprefix/bin/octave-cli"     ".."
    startup_script "$octprefix/bin/mkoctfile"      ".."  _script_mkoctfile_vars
    startup_script "$octprefix/bin/octave-config"  ".."

    setup_fontconfig
    
    strip_objects

    remove_doc

    ( cd $rootdir && \
	tar -cvzf plx-octave-${octver}_macos.tar.gz plx-octave-$octver )
}


main()
{
    mkdir -p $srcroot
    mkdir -p $buildroot
    mkdir -p $instroot
    
    setup_env

    build_buildtools
    
    build_gcc
    setup_compilers
    
    build_lapack

    build_pcre

    build_termcap
    build_readline

    build_freetype
    build_fontconfig

    build_gl2ps

    build_qt
    
    build_glpk
    
    build_rapidjson
    
    build_octave

    build_texinfo

    build_libtiff
    build_ghostscript
    
    package_octave
}





## Entry point

if [ `id -u` -eq 0 ]; then
    echo "Please do not run this script as root."
    exit 1
fi

if [ "$#" -eq 0 ]; then
    main
    exit
else
    echo "Error: unknown command $1"
    exit 1
fi
