#!/bin/bash

#
# Cross-compile Octave for Windows and dependencies
# with mingw-w64 in a Debian container using mxe-octave.
#

octver=4.4.1

set -o errexit
set -o pipefail

arch="$1"

scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
scriptpath=$scriptdir/$( basename "${BASH_SOURCE[0]}" )

container_tag=octave_windows_build
container_user=developer
container_group=developer
container_name=$container_tag.$arch

container_rootdir=/home/$container_user/octave-windows.$arch
if [ "$2" = "__container_build__" ]; then
    rootdir=$container_rootdir
else
    rootdir=$(pwd)/$(basename $container_rootdir)
fi

mxeroot=$rootdir/mxe-octave
plxoct=plx-octave-$octver

ncores="${NCORES:-4}"


create_container_image()
{
    local uid=`id -u`
    local gid=`id -g`

    docker build -t $container_tag - <<EOF
FROM debian:stretch

RUN apt-get -y update
RUN apt-get -y install \
    autoconf \
    automake \
    bash \
    bison \
    bzip2 \
    cmake \
    flex \
    gettext \
    git \
    g++ \
    intltool \
    libffi-dev \
    libtool \ 
    libltdl-dev \
    mercurial \
    openssl \
    libssl-dev \
    libxml-parser-perl \
    make \
    patch \
    perl \
    pkg-config \
    scons \
    sed \
    unzip \
    wget \
    xz-utils \
    yasm \
    autopoint \
    zip

RUN apt-get -y install \
    zlib1g-dev \
    p7zip \
    gperf

RUN apt-get -y install \
    llvm \
    libclang-dev

RUN apt-get -y install \
    qttools5-dev-tools

RUN bash -c ' \
        groupadd -g ${gid} ${container_group} && \
        useradd -u ${uid} -g ${gid} -m -s /bin/bash --no-log-init ${container_user} \
        '

USER ${container_user}:${container_group}
ENV HOME /home/${container_user}

EOF
}


delete_container_image()
{
    docker image rm $container_tag
} 


apply_patches()
{
    # patch mxe-octave makefiles

    patch -d $mxeroot -p0 < $scriptdir/windows_files/release-octave.mk.patch
    patch -d $mxeroot -p0 < $scriptdir/windows_files/binary-dist-rules.mk.patch
    patch -d $mxeroot -p0 < $scriptdir/windows_files/ghostscript.mk.patch
    patch -d $mxeroot -p0 < $scriptdir/windows_files/qtbase.mk.patch
    patch -d $mxeroot -p0 < $scriptdir/windows_files/of-control.mk.patch
    patch -d $mxeroot -p1 < $scriptdir/windows_files/of-signal.mk.patch && \
	rm $mxeroot/src/of-signal-1-fixes.patch && \
	rm $mxeroot/src/of-signal-2-fixes.patch

    # patch pkg-build.py

    patch -d $mxeroot -p1 < $scriptdir/windows_files/4eae7db624e8.cset
    patch -d $mxeroot -p1 < $scriptdir/windows_files/Makefile.in-pkg-install.patch

    # copy remaining patches to mxe-root src folder

    cp $scriptdir/windows_files/readline-3-pipe-input.patch \
	$mxeroot/src

    cp $scriptdir/common_files/bug_49053_1.patch \
	$mxeroot/src/release-octave-2-bug49053.patch
    
    cp $scriptdir/common_files/bug_50025_1.patch \
	$mxeroot/src/release-octave-3-bug50025.patch
    
    cp $scriptdir/windows_files/release-octave-4-print-tools-path.patch \
	$mxeroot/src
    
    cp $scriptdir/common_files/source_file.patch \
	$mxeroot/src/release-octave-5-source-file.patch
    
    cp $scriptdir/common_files/eval_string_reader.patch \
	$mxeroot/src/release-octave-6-eval-string-reader.patch

    cp $scriptdir/common_files/0cedd1e23c1f.cset \
	$mxeroot/src/release-octave-7-0cedd1e23c1f.patch

    cp $scriptdir/common_files/377f069841c1.cset \
	$mxeroot/src/release-octave-8-377f069841c1.patch

    cp $scriptdir/common_files/bug_51632_list_global_OCTAVE_HOME.cset \
	$mxeroot/src/release-octave-9-bug_51632_list_global_OCTAVE_HOME.patch

    cp $scriptdir/common_files/version-rcfile.patch \
	$mxeroot/src/release-octave-10-version-rcfile.patch
}


setup_mxe()
{
    hg clone https://hg.octave.org/mxe-octave $mxeroot
    
    ( cd $mxeroot && hg checkout octave-release-$octver )
      
    apply_patches

    ( cd $mxeroot && aclocal && autoconf )
}


build_octave()
{
    pushd $mxeroot

    if [ "$arch" = "w64" ]; then
    local arch_options="        \
    	--enable-windows-64 	\
    	--enable-64 		\
    	--disable-fortran-int64 \
    	"  
    else
    local arch_options="        \
    	--disable-windows-64 	\
    	--disable-64 		\
    	--disable-fortran-int64 \
    	"  
    fi
    
    local options=" \
        --disable-jit \
        --disable-java \
        --disable-docs \
        --disable-openblas \
        --disable-devel-tools \
        --enable-binary-packages \
        --enable-qt5 \
        --disable-dep-docs \
        --disable-system-opengl \
    "

    ./configure \
    	$arch_options \
    	--enable-octave=release \
        $options


    make release-octave JOBS=$ncores
    make binary-dist-files JOBS=$ncores
    
    popd        
}


collect_dist_files()
{
    local distroot=$mxeroot/dist
    local origdir=$distroot/octave-$octver-$arch
    local plxdir=$distroot/$plxoct

    rm -rf $plxdir && mkdir -p $plxdir
    while read -r path; do
	if ! [ -z "$path" ] && ! [[ "$path" =~ ^#.* ]]; then
	    echo "Copying $path ..."
	    if ! [[ "$path" =~ ^@.* ]]; then
		( cd $origdir; find . -path "./$path" -exec cp -a --parents {} $plxdir \; )
	    else
		local findcmd="${path:1}"
		( cd $origdir; eval find . "$findcmd" -exec cp -a --parents {} "$plxdir" '\;' )
	    fi
	fi
    done <<-EOF

bin/cat.exe
bin/cp.exe
bin/mv.exe

@ -path './bin/*.dll' ! -name 'Qt5*.dll' ! -name 'LLVM*.dll'
bin/Qt5Core.dll
bin/Qt5Gui.dll
bin/Qt5Help.dll
bin/Qt5Network.dll
bin/Qt5OpenGL.dll
bin/Qt5PrintSupport.dll
bin/Qt5Sql.dll
bin/Qt5Widgets.dll

bin/opengl32.dll

bin/octave-gui.exe
bin/octave-cli.exe
bin/octave-config.exe
bin/mkoctfile.exe
# bin/mkoctfile-$octver.exe
bin/qt.conf

bin/makeinfo.bat
bin/makeinfo
bin/gs.exe
bin/perl.exe
bin/perl5.8.8.exe

etc/fonts

include/octave-$octver

lib/octave
lib/perl5

qt5/plugins/*

# share/fontconfig
share/ghostscript/lib/*
share/icons

@ -type f -path './share/octave/*' ! -path './share/octave/$octver/etc/config.log' ! -name '*.qhc' ! -name '*.qch'

share/texinfo
# share/xml/fontconfig

EOF
}


add_mkoctfile_bat()
{
    cat > $mxeroot/dist/$plxoct/bin/mkoctfile.bat <<'EOF'
@echo off

set OCTAVE_HOME=%~dp0..
for %%I in ("%OCTAVE_HOME%") do set OCTAVE_HOME=%%~sI

IF NOT DEFINED CPPGLAGS (set CPPFLAGS= )
IF NOT DEFINED FLIBS (set FLIBS=-lm -lgfortran -lmingw32 -lmoldname -lmingwex -lmsvcrt -lquadmath -lpthread -ladvapi32 -lshell32 -luser32 -lkernel32)
IF NOT DEFINED LDFLAGS (set LDFLAGS= )
IF NOT DEFINED OCT_LINK_OPTS (set OCT_LINK_OPTS= )
IF NOT DEFINED XTRA_CFLAGS (set XTRA_CFLAGS= )
IF NOT DEFINED XTRA_CXXFLAGS (set XTRA_CXXFLAGS= )

%OCTAVE_HOME%\bin\mkoctfile.exe %*
EOF
}


add_octave_bat()
{
    cat > $mxeroot/dist/$plxoct/bin/octave.bat <<'EOF'
@echo off

set OCTAVE_HOME=%~dp0..
for %%I in ("%OCTAVE_HOME%") do set OCTAVE_HOME=%%~sI

set TERM=cygwin
set QT_PLUGIN_PATH=%OCTAVE_HOME%\qt5\plugins
set PATH=%OCTAVE_HOME%\bin;%PATH%

"%OCTAVE_HOME%\bin\octave-gui.exe" %*
EOF
}


add_octave_cli_bat()
{
    cat > $mxeroot/dist/$plxoct/bin/octave-cli.bat <<'EOF'
@echo off

set OCTAVE_HOME=%~dp0..
for %%I in ("%OCTAVE_HOME%") do set OCTAVE_HOME=%%~sI

set TERM=cygwin
set PATH=%OCTAVE_HOME%\bin;%PATH%

"%OCTAVE_HOME%\bin\octave-cli.exe" %*
EOF
}


patch_site_octaverc()
{
    patch -d $mxeroot/dist/$plxoct -p1 < $scriptdir/windows_files/site_octaverc.patch
}


setup_pkg_paths()
{
    local distdir=$mxeroot/dist/$plxoct

    local rcfile=$distdir/share/octave/$octver/m/startup/octaverc
    cat >> $rcfile <<-EOF

	## Setup package paths
	pkg_prefix = fullfile (OCTAVE_HOME (), 'share', 'octave', 'packages');
	pkg_archprefix = fullfile (OCTAVE_HOME (), 'lib', 'octave', 'packages');
	pkg_list = fullfile (OCTAVE_HOME (), 'share', 'octave', 'octave_packages');
	pkg ('prefix', pkg_prefix, pkg_archprefix);
	pkg ('global_list', pkg_list);
	clear ('pkg_prefix', 'pkg_archprefix', 'pkg_list');
EOF
}


package_octave()
{
    collect_dist_files

    add_mkoctfile_bat
    add_octave_bat
    add_octave_cli_bat

    patch_site_octaverc
    setup_pkg_paths

    if [ "$arch" = "w64" ]; then
	local octzip=$rootdir/${plxoct}_win64.zip
    else
    	local octzip=$rootdir/${plxoct}_win32.zip
    fi
    
    ( rm -f $octzip && \
      cd $mxeroot/dist && zip -r $octzip $plxoct )
}


container_entrypoint()
{
    setup_mxe
    build_octave
    package_octave
}


do_build()
{
    mkdir -p $rootdir
    cp $scriptpath $rootdir/build_script.sh
    cp -a $scriptdir/common_files $rootdir
    cp -a $scriptdir/windows_files $rootdir

    local cmd="\
    	 docker run --rm -t -i \
         --name $container_name \
	 -u $container_user:$container_group \
	 -v $rootdir:$container_rootdir \
	 $container_tag \
	 bash -c 'cd $container_rootdir && ./build_script.sh $arch __container_build__' \
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

print_usage()
{
    echo "Usage:"
    echo "\$ $(basename ${BASH_SOURCE[0]}) w64"
    echo "\$ $(basename ${BASH_SOURCE[0]}) w32"
}


if [ `id -u` -eq 0 ]; then
    echo "Please do not run this script as root."
    exit 1
fi


if [ "$1" != "w64" ] && [ "$1" != "w32" ]; then
    print_usage
    exit 1
fi


if [ "$#" -eq 1 ]; then
    main
    exit
fi

case "$2" in
    __container_build__)
	container_entrypoint
	exit
	;;

    *)
	echo "Error: unknown command $2"
	exit 1
	;;
esac
