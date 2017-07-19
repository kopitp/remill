#!/usr/bin/env bash
# Copyright (c) 2017 Trail of Bits, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# General directory structure:
#   /path/to/home/remill
#   /path/to/home/remill-build

SCRIPTS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
SRC_DIR=$( cd "$( dirname "${SCRIPTS_DIR}" )" && pwd )
CURR_DIR=$( pwd )
BUILD_DIR=${CURR_DIR}/remill-build
INSTALL_DIR=/usr/local
LLVM_VERSION=llvm40
OS_VERSION=
BUILD_WITH_LLVM=1

function GetUbuntuOSVersion
{
  # Version name of Ubuntu (e.g. xenial, trusty).
  source /etc/lsb-release

  # There are pre-build versions of various libraries for specific
  # Ubuntu releases.
  case ${DISTRIB_CODENAME} in
    xenial)
      OS_VERSION=ubuntu1604
      return 0
    ;;
    trusty)
      OS_VERSION=ubuntu1404
      return 0
    ;;
    *)
      printf "[x] Ubuntu ${DISTRIB_CODENAME} is not supported.\n"
      return 1
  esac
}

function DownloadCxxCommon
{
  wget https://s3.amazonaws.com/cxx-common/${LIBRARY_VERSION}.tar.gz
  tar xf ${LIBRARY_VERSION}.tar.gz --warning=no-timestamp
  rm ${LIBRARY_VERSION}.tar.gz

  # Make sure modification times are not in the future.
  find ${BUILD_DIR}/libraries -type f -exec touch {} \;
}

# Download pre-compiled version of cxx-common for this OS. This has things like
# google protobuf, gflags, glog, gtest, capstone, and llvm in it.
function DownloadLibraries
{
  # mac os x packages
  if [[ "$OSTYPE" == "darwin"* ]]; then
    printf "[x] macOS is not yet supported\n"
    return 1

  # unsupported systems
  elif [[ "$OSTYPE" != "linux-gnu" ]]; then
    return 1
  fi

  # attempt to detect the distribution
  local distribution_name=`cat /etc/issue`

  case "$distribution_name" in
    *Ubuntu*)
      GetUbuntuOSVersion
    ;;

    *Arch\ Linux*)
      printf "[x] Arch Linux is not yet supported\n"
      return 1
    ;;

    *)
      printf "[x] Failed to download the required dependencies\n"
      return 1
  esac

  LIBRARY_VERSION=libraries-${LLVM_VERSION}-${OS_VERSION}

  printf "[-] Library version is ${LIBRARY_VERSION}\n"

  if [[ ! -d "${BUILD_DIR}/libraries" ]] ; then
    DownloadCxxCommon
  fi

  return 0
}

# Configure the build.
function Configure
{
  # Tell the remill CMakeLists.txt where the extracted libraries are. 
  export TRAILOFBITS_LIBRARIES=${BUILD_DIR}/libraries

  # Use the pre-built versions of Clang for compiling.
  if [[ ${BUILD_WITH_LLVM} -eq 1 ]] ; then
    export CC=${TRAILOFBITS_LIBRARIES}/llvm/bin/clang
    export CXX=${TRAILOFBITS_LIBRARIES}/llvm/bin/clang++
  fi

  if [[ -z "${CC}" ]] ; then
    export CC=$(which cc)
  fi

  if [[ -z "${CXX}" ]] ; then
    export CXX=$(which c++)
  fi

  # Configure the remill build, specifying that it should use the pre-built
  # Clang compiler binaries.
  ${TRAILOFBITS_LIBRARIES}/cmake/bin/cmake \
      -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR} \
      -DCMAKE_C_COMPILER=${CC} \
      -DCMAKE_CXX_COMPILER=${CXX} \
      ${SRC_DIR}

  return $?
}

# Compile the code.
function Build
{
  NPROC=$( nproc )
  make -j${NPROC}
  return $?
}

# Get a LLVM version name for the build. This is used to find the version of
# cxx-common to download.
function GetLLVMVersion
{
  case ${1} in
    3.6)
      LLVM_VERSION=llvm36
      return 0
    ;;
    3.7)
      LLVM_VERSION=llvm37
      return 0
    ;;
    3.8)
      LLVM_VERSION=llvm38
      return 0
    ;;
    3.9)
      LLVM_VERSION=llvm39
      return 0
    ;;
    4.0)
      LLVM_VERSION=llvm40
    ;;
    *)
      # unknown option
      printf "[x] Unknown LLVM version ${1}\n"
      exit 1
    ;;
  esac
}

function main
{
  
  while [[ $# -gt 0 ]] ; do
    key="$1"

    case $key in

      # Change the default installation prefix.
      --prefix)
        INSTALL_DIR=$(python -c "import os; import sys; sys.stdout.write(os.path.abspath('${2}'))")
        printf "[+] New install directory is ${INSTALL_DIR}\n"
        shift # past argument
      ;;

      # Change the default LLVM version.
      --llvm-version)
        GetLLVMVersion ${2}
        if [[ $? -ne 0 ]] ; then
          return 1
        fi
        printf "[+] New LLVM version is ${LLVM_VERSION}\n"
        shift
      ;;

      # Change the default build directory.
      --build-dir)
        BUILD_DIR=$(python -c "import os; import sys; sys.stdout.write(os.path.abspath('${2}'))")
        printf "[+] New build directory is ${BUILD_DIR}\n"
        shift # past argument
      ;;

      # Use the system compiler for building? In general, use this if you
      # are using LLVM < 3.9. This lets you avoid breaking changes in the
      # GNU C++ ABI.
      --use-system-compiler)
        BUILD_WITH_LLVM=0
      ;;

      *)
        # unknown option
        printf "[x] Unknown option: ${key}\n"
        return 1
      ;;
    esac

    shift # past argument or value
  done
  
  mkdir -p ${BUILD_DIR}
  cd ${BUILD_DIR}

  DownloadLibraries && Configure && Build
  return $?
}

main $@
exit $?