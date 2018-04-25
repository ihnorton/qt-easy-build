#!/bin/bash
set -e
set -x
set -o pipefail

# ERISOne build: must load newer GCC
#module load gcc/7.1.0

#
# Configuration
#

# Qt version (major.minor.revision)
QT_VERSION=5.9.5

# OpenSSL version
OPENSSL_VERSION=1.0.2n
OPENSSL_MIDAS_PACKAGES_ITEM=10337

# MD5 checksums
OPENSSL_MD5="13bdc1b1d1ff39b6fd42a255e74676a4"
QT_MD5="0e6eaa2d118f9854345c2debb12e8536"
#QT_MD5="7e167b9617e7bd64012daaacb85477af"
       # old: c5e275ab0ed7ee61d0f4b82cd471770d"

QT_SRC_ARCHIVE_EXT="tar.xz"

#
# Generated configuration
#

QT_MAJOR_MINOR_VERSION=$(echo $QT_VERSION | awk -F . '{ print $1"."$2 }')

# Defaults
clean=0
nbthreads=12
confirmed=0
qt_targets=

# Check if building on MacOS or Linux
SYSTEM="Linux"
if [ "$(uname)" == "Darwin" ]
then
  SYSTEM="Darwin"
fi

export CFLAGS=""
export CXXFLAGS=""

show_help() {
cat << EOF
Usage: ${0##*/} [-h] [-c] [-j] [-s SYSROOT] [-d DEPLOYMENT_TARGET] [-a ARCHITECTURES] [-q QT_INSTALL_DIR] [-m CMAKE]

This script is a convenience script to install Qt on the system. It:

- Auto-detect if running on MacOS or Linux
- Compiles zlib.
- Compiles openssl.
- Compiles and install qt.

Options:

  -y             Do not prompt user and skip confirmation.
  -c             Clean directories that are going to be used. [default: $clean]
  -h             Display this help and exit.
  -j             Number of threads for parallel build. [default: $nbthreads]
  -m             Path for cmake.
  -q             Installation directory for Qt. [default: qt-everywhere-build-$QT_VERSION]
  -t             Specific Qt targets to build (e.g -t "module-qtbase module-qtbase-install_subtargets")

Environment variables:

  CFLAGS   [${CFLAGS}]
  CXXFLAGS [${CXXFLAGS}]

EOF

if [ $SYSTEM == "Darwin" ]
then
  cat << EOF
Options (macOS):
  -a             Set OSX architectures. (expected values: x86_64 or i386) [default: x86_64]
  -d             OSX deployment target. [default: 10.8]
  -s             OSX sysroot. [default: macosx10.12]

EOF
fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h)
      show_help
      exit 0
      ;;
    -c)
      clean=1
      ;;
    -q)
      install_dir=$2
      shift
      ;;
    -m)
      cmake=$2
      shift
      ;;
    -j)
      nbthreads=$2
      shift
      ;;
    -a)
      osx_architecture=$2
      shift
      ;;
    -d)
      osx_deployment_target=$2
      shift
      ;;
    -s)
      osx_sysroot=$2
      shift
      ;;
    -y)
      confirmed=1
      ;;
    -t)
      qt_targets=$2
      shift
      ;;
    *)
      show_help >&2
      exit 1
      ;;
  esac
  shift
done

openssl_archive=openssl-$OPENSSL_VERSION.tar.gz
openssl_download_url=https://packages.kitware.com/download/item/$OPENSSL_MIDAS_PACKAGES_ITEM/$openssl_archive

qt_archive=qt-everywhere-opensource-src-$QT_VERSION.${QT_SRC_ARCHIVE_EXT}
#qt_download_url=https://download.qt.io/official_releases/qt/$QT_MAJOR_MINOR_VERSION/$QT_VERSION/single/$qt_archive
# main mirror is blocked at partners.
qt_download_url=http://qtmirror.ics.com/pub/qtproject/official_releases/qt/5.9/5.9.5/single/qt-everywhere-opensource-src-5.9.5.tar.xz

cwd=$(pwd)

# Dependencies directory
deps_dir="$cwd/qt-everywhere-deps-$QT_VERSION"

# Source and Build directory
src_dir="$cwd/qt-everywhere-opensource-src-$QT_VERSION"

# Install directory
if [[ -z $install_dir ]]
then
  install_dir="$cwd/qt-everywhere-build-$QT_VERSION"
fi

# If cmake path was not given, verify that it is available on the system
# CMake is required to configure zlib
if [[ -z "$cmake" ]]
then
  cmake=`which cmake`
  if [ $? -ne 0 ]
  then
    echo "cmake not found"
    exit 1
  fi
fi

# Set macOS options
if [ $SYSTEM == "Darwin" ]
then
  # MacOS
  if [[ -z $osx_deployment_target ]]
  then
    osx_deployment_target=10.8
  fi
  if [[ -z $osx_sysroot ]]
  then
    osx_sysroot=macosx10.12
  fi
  if [[ -z $osx_architecture ]]
  then
    osx_architecture=x86_64
  fi
fi

show_summary() {
cat << EOF

This script will build Qt for $SYSTEM system

QT_VERSION      : $QT_VERSION
OPENSSL_VERSION : $OPENSSL_VERSION

Script options:

 -c Clean directories that are going to be used .. $clean
 -q Installation directory for Qt ................ $install_dir
 -m Path to cmake ................................ $cmake
 -j Number of threads for parallel build.......... $nbthreads

Download URLs:
* Qt      : $qt_download_url
* OpenSSL : $openssl_download_url

Environment variables:

  CFLAGS   [${CFLAGS}]
  CXXFLAGS [${CXXFLAGS}]

EOF

if [ $SYSTEM == "Darwin" ]
then
  cat << EOF
Script options (macOS):

 -a OSX architectures ............................ $osx_architecture
 -d OSX deployment target ........................ $osx_deployment_target
 -s OSX sysroot .................................. $osx_sysroot

EOF
  fi
}

# Show summary and prompt user
show_summary
if [ $confirmed -eq 0 ]
then
  read -p "Do you want to continue [y/N] ? " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
    confirmed=1
  else
    echo "Aborting ..."
    exit 1
  fi
fi

# If "clean", remove all directories and temporary files
# that are downloaded and used in this script.
if [ $clean -eq 1 ]
then
  echo "Remove previous files and directories"
  rm -rf $deps_dir
  rm -rf $src_dir
  rm -rf $install_dir
fi

mkdir -p $deps_dir
pushd $deps_dir

# Download archives
echo "Download openssl"
if ! [ -f $openssl_archive ]
then
  curl -# -OL $openssl_download_url
else
  echo "  skipping (found $openssl_archive)"
fi
echo "Download Qt"
if ! [ -f $qt_archive ]
then
  curl -# -OL $qt_download_url
else
  echo "  skipping (found $qt_archive)"
fi

# Check if building on MacOS or Linux
# And verifies downloaded archives accordingly
if [ $SYSTEM == "Darwin" ]
then
  # MacOS
  zlib_macos_options="-DCMAKE_OSX_ARCHITECTURES=$osx_architecture
                -DCMAKE_OSX_SYSROOT=$osx_sysroot
                -DCMAKE_OSX_DEPLOYMENT_TARGET=$osx_deployment_target"
  export KERNEL_BITS=64
  qt_macos_options="-sdk $osx_sysroot"

  md5_openssl=`md5 ./$openssl_archive | awk '{ print $4 }'`
  md5_qt=`md5 ./$qt_archive | awk '{ print $4 }'`
else
  # Linux
  md5_openssl=`md5sum ./$openssl_archive | awk '{ print $1 }'`
  md5_qt=`md5sum ./$qt_archive | awk '{ print $1 }'`
fi
if [ "$md5_openssl" != "$OPENSSL_MD5" ]
then
  echo "MD5 mismatch. Problem downloading OpenSSL"
  exit 1
fi
if [ "$md5_qt" != "$QT_MD5" ]
then
  echo "MD5 mismatch. Problem downloading Qt"
  exit 1
fi

# Build zlib
echo "Build zlib"

cwd=$(pwd)

mkdir -p zlib-install
mkdir -p zlib-build
if [[ ! -d zlib ]]
then
  git clone git://github.com/commontk/zlib.git
fi
cd zlib-build
$cmake -DCMAKE_BUILD_TYPE:STRING=Release             \
       -DZLIB_MANGLE_PREFIX:STRING=slicer_zlib_      \
       -DCMAKE_INSTALL_PREFIX:PATH=$cwd/zlib-install \
       $zlib_macos_options                           \
       ../zlib
make -j $nbthreads
make install
cd ..
cp zlib-install/lib/libzlib.a zlib-install/lib/libz.a

# Build OpenSSL
echo "Build OpenSSL"

cwd=$(pwd)

if [[ ! -d openssl-$OPENSSL_VERSION ]]
then
  tar --no-same-owner -xf $openssl_archive
fi
cd openssl-$OPENSSL_VERSION/
./config zlib -I$cwd/zlib-install/include -L$cwd/zlib-install/lib shared
make -j 1 build_libs
# If MacOS, install openssl libraries
if [ "$(uname)" == "Darwin" ]
then
  install_name_tool -id $cwd/openssl-$OPENSSL_VERSION/libcrypto.dylib $cwd/openssl-$OPENSSL_VERSION/libcrypto.dylib
  install_name_tool                                                                            \
          -change /usr/local/ssl/lib/libcrypto.1.0.0.dylib $cwd/openssl-$OPENSSL_VERSION/libcrypto.dylib \
          -id $cwd/openssl-$OPENSSL_VERSION/libssl.dylib $cwd/openssl-$OPENSSL_VERSION/libssl.dylib
fi
cd ..

popd

# Build Qt
echo "Build Qt in: $src_dir"

cwd=$(pwd)

mkdir -p $install_dir
qt_install_dir_options="-prefix $install_dir"

if [[ ! -d $src_dir ]]
then
  tar --no-same-owner -xf $deps_dir/$qt_archive
fi
cd $src_dir

# qtwebengine requires glibc >= 2.17
./configure $qt_install_dir_options \
  -release -opensource -confirm-license \
  -c++std c++11 \
  -skip qtwebengine \ 
  -nomake examples \
  -nomake tests \
  -silent \
  -qt-xcb \
  -qt-zlib \
  -qt-libjpeg \
  -qt-libpng \
  -qt-xkbcommon \
  -qt-freetype \
  -qt-pcre \
  -qt-freetype \
  -qt-harfbuzz \
  -openssl -I $deps_dir/openssl-$OPENSSL_VERSION/include           \
  ${qt_macos_options}                                         \
  -L $deps_dir/openssl-$OPENSSL_VERSION

if [[ -z $qt_targets ]]
then
  make -j $nbthreads
  make install
else
  for target in $qt_targets; do
    make $target -j $nbthreads
  done
fi

