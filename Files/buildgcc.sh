#!/bin/bash

# Script for GCC chainload in OS X made for EDKII
# 
# Primary use is for creating better crosscompile support than 
# mingw-gcc-build.py that is found in BaseTools/gcc/
# 
# With this we can use Native GCC chainload for EDKII  
# development
#
# Xcode Tools are required
# Script tested on "Xcode 3.2" - Snow Leopard  
#                  "Xcode 4.1" - Lion
#
#  
# Created by Jadran Puharic on 1/25/12.
# Improvements STLVNUB
# 
if [ "$1" == "-test" ]; then
	echo "Testing"
	exit 
fi	
# GCC chainload source version 
# here we can change source versions of tools
#
export PREFIX="$2"
export BINUTILS_VERSION=binutils-2.23.1
export GCC_VERSION="$3"
export GMP_VERSION=gmp-5.1.1
export MPFR_VERSION=mpfr-3.1.2
export MPC_VERSION=mpc-1.0.1
# Change PREFIX if you want gcc and binutils 
# installed on different place
#

#export PREFIX=/usr/local

# Change target mode of crosscompiler for
# IA32 and X64 - (we know that this one works best)
# 
export TARGET_IA32="i686-linux-gnu"
export TARGET_X64="x86_64-linux-gnu"


# ./configure arguments for GCC
# 
export GCC_CONFIG="--prefix=$PREFIX --with-sysroot=$PREFIX --disable-werror --with-gmp=$PREFIX --oldincludedir=$PREFIX/include --with-gnu-as --with-gnu-ld --with-newlib --verbose --disable-libssp --disable-nls --enable-languages=c,c++"

# ./configure arguments for Binutils
#
export BINUTILS_CONFIG="--prefix=$PREFIX  --with-sysroot=$PREFIX --disable-werror --with-gmp=$PREFIX --with-mpfr=$PREFIX --with-mpc=$PREFIX"

# You can change DIR_MAIN if u wan't gcc source downloaded 
# in different folder. 
#
export DIR_MAIN="$2"/src
export DIR_TOOLS=$DIR_MAIN/tools/
export DIR_GCC=$DIR_MAIN/tools/gcc 
export DIR_DOWNLOADS=$DIR_GCC/download
export DIR_LOGS=$DIR_GCC/logs

# Here we set MAKEFLAGS for GCC so it knows how many cores can use
# faster compile!
#
export MAKEFLAGS="-j `sysctl -n hw.ncpu`"

fnHelp ()
# Function: Help
{
echo 
echo " Script for building GCC chainload on Darwin OS X"
echo
echo "   Usage: ./buildgcc.sh [ARCH] [TOOL]"
echo 
echo "   [ARCH]     [TOOL]"
echo "   -ia32      -binutils"
echo "   -x64       -gcc"
echo "              -all"
echo
echo " Example: ./buildgcc.sh -ia32 -all"
echo
}


### Main Function START ### 

# Function: Creating directory structure for EDK

[ ! -d ${DIR_MAIN} ] && mkdir ${DIR_MAIN}
[ ! -d ${DIR_TOOLS} ] && mkdir ${DIR_TOOLS}
[ ! -d ${DIR_GCC} ] && mkdir ${DIR_GCC}
[ ! -d ${DIR_DOWNLOADS} ] && mkdir ${DIR_DOWNLOADS}
[ ! -d ${DIR_LOGS} ] && mkdir ${DIR_LOGS}
[ ! -d ${PREFIX}/include ] && mkdir ${PREFIX}/include
echo


# Download #
# simple spinner
function spinner()
{
    local pid=$1
    local delay=0.25
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}


fnDownloadLibs ()
{
    cd $DIR_DOWNLOADS
    [ ! -f ${DIR_DOWNLOADS}/${GMP_VERSION}.tar.bz2 ] && echo "Status: ${GMP_VERSION} not found." && curl --remote-name http://mirror.aarnet.edu.au/pub/gnu/gmp//${GMP_VERSION}.tar.bz2
    [ ! -f ${DIR_DOWNLOADS}/${MPFR_VERSION}.tar.bz2 ] && echo "Status: ${MPFR_VERSION} not found." && curl --remote-name http://mirror.aarnet.edu.au/pub/gnu/mpfr/${MPFR_VERSION}.tar.bz2
    [ ! -f ${DIR_DOWNLOADS}/${MPC_VERSION}.tar.gz ] && echo "Status: ${MPC_VERSION} not found." && curl --remote-name http://www.multiprecision.org/mpc/download/${MPC_VERSION}.tar.gz
    [ ! -f ${DIR_DOWNLOADS}/${BINUTILS_VERSION}.tar.bz2 ] && echo "Status: ${BINUTILS_VERSION} not found." && curl --remote-name http://mirror.aarnet.edu.au/pub/gnu/binutils/${BINUTILS_VERSION}.tar.bz2
    [ ! -f ${DIR_DOWNLOADS}/gcc-${GCC_VERSION}.tar.bz2 ] && echo "Status: gcc-${GCC_VERSION} not found." && curl --remote-name http://mirrors.kernel.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.bz2 & pidgcc=$!
    wait
    echo "Done!"
}


### Compile ###

fnCompileLibs ()
# Function: Compiling GMP/MPFR/MPC in PREFIX location
{
# Compile GMP
    cd $DIR_DOWNLOADS
    echo
    [ ! -f $DIR_DOWNLOADS/${GMP_VERSION}.tar.bz2.extracted ] && echo "-  ${GMP_VERSION} extract..." && tar -xf ${GMP_VERSION}.tar.bz2 > ${GMP_VERSION}.tar.bz2.extracted
    echo "-  ${GMP_VERSION} extracted"
    wait
    [ ! -d ${DIR_GCC}/$ARCH-gmp ] && mkdir ${DIR_GCC}/$ARCH-gmp 
    [ -d ${DIR_GCC}/$ARCH-gmp ] && cd ${DIR_GCC}/$ARCH-gmp && rm -rf * 
    echo "-  ${GMP_VERSION} configure..."
    ../download/${GMP_VERSION}/configure --prefix=$PREFIX > $DIR_LOGS/gmp.$ARCH.config.log.txt 2> /dev/null
    echo "-  ${GMP_VERSION} make..."
    make 1> /dev/null 2> $DIR_LOGS/gmp.$ARCH.make.log.txt
    wait
    make install 1> $DIR_LOGS/gmp.$ARCH.install.log.txt 2> /dev/null
    wait
    echo "-  ${GMP_VERSION} installed in $PREFIX  -"

# Compile MPFR
    cd $DIR_DOWNLOADS
    echo
    [ ! -f $DIR_DOWNLOADS/${MPFR_VERSION}.tar.bz2.extracted ] && echo "-  ${MPFR_VERSION} extract..." && tar -xf ${MPFR_VERSION}.tar.bz2 > ${MPFR_VERSION}.tar.bz2.extracted
    echo "-  ${MPFR_VERSION} extracted"
    wait
    [ ! -d ${DIR_GCC}/$ARCH-mpfr ] && mkdir ${DIR_GCC}/$ARCH-mpfr 
    [ -d ${DIR_GCC}/$ARCH-mpfr ] && cd ${DIR_GCC}/$ARCH-mpfr && rm -rf * 
    echo "-  ${MPFR_VERSION} configure..."
    ../download/${MPFR_VERSION}/configure --prefix=$PREFIX --with-gmp=$PREFIX > $DIR_LOGS/mpfr.$ARCH.config.log.txt 2> /dev/null
    echo "-  ${MPFR_VERSION} make..."
    make 1> /dev/null 2> $DIR_LOGS/mpfr.$ARCH.make.log.txt
    wait
    make install 1> $DIR_LOGS/mpfr.$ARCH.install.log.txt 2> /dev/null
    wait
    echo "-  ${MPFR_VERSION} installed in $PREFIX  -"

# Compile MPC
    cd $DIR_DOWNLOADS
    echo
    [ ! -f $DIR_DOWNLOADS/${MPC_VERSION}.tar.gz.extracted ] && echo "-  ${MPC_VERSION} extract..." && tar -xf ${MPC_VERSION}.tar.gz > ${MPC_VERSION}.tar.gz.extracted
    wait
    echo "-  ${MPC_VERSION} extracted"
    [ ! -d ${DIR_GCC}/$ARCH-mpc ] && mkdir ${DIR_GCC}/$ARCH-mpc 
    [ -d ${DIR_GCC}/$ARCH-mpc ] && cd ${DIR_GCC}/$ARCH-mpc && rm -rf * 
    echo "-  ${MPC_VERSION} configure..."
    ../download/${MPC_VERSION}/configure --prefix=$PREFIX --with-gmp=$PREFIX --with-mpfr=$PREFIX  > $DIR_LOGS/mpc.$ARCH.config.log.txt 2> /dev/null
    echo "-  ${MPC_VERSION} make..."
    make 1> /dev/null 2> $DIR_LOGS/mpc.$ARCH.make.log.txt
    wait
    make install 1> $DIR_LOGS/mpc.$ARCH.install.log.txt 2> /dev/null
    wait
    echo "-  ${MPC_VERSION} installed in $PREFIX  -"
}

fnCompileBinutils ()
# Function: Compiling Binutils in PREFIX location
{
    export BUILD_BINUTILS_DIR=$DIR_GCC/$ARCH-binutils
    cd $DIR_DOWNLOADS
    echo
    [ ! -f $DIR_DOWNLOADS/${BINUTILS_VERSION}.tar.bz2.extracted ] && echo "-  ${BINUTILS_VERSION} extract" && tar -xf ${BINUTILS_VERSION}.tar.bz2 > ${BINUTILS_VERSION}.tar.bz2.extracted
    wait
    echo "-  ${BINUTILS_VERSION} extracted"
    
    # Check GMP/MPFR/MPC
    [ ! -f $PREFIX/include/gmp.h ] && echo "Error: ${GMP_VERSION} not installed, check logs" && exit
    [ ! -f $PREFIX/include/mpfr.h ] && echo "Error: ${MPFR_VERSION} not installed, check logs" && exit
    [ ! -f $PREFIX/include/mpc.h ] && echo "Error: ${MPC_VERSION} not installed, check logs" && exit

    # Binutils build
    [ ! -d ${DIR_GCC}/$ARCH-binutils ] && mkdir ${DIR_GCC}/$ARCH-binutils 
    [ -d ${DIR_GCC}/$ARCH-binutils ] && cd ${DIR_GCC}/$ARCH-binutils && rm -rf * 
    echo "-  ${BINUTILS_VERSION} configure..."
    ../download/${BINUTILS_VERSION}/configure --target=$TARGET $BINUTILS_CONFIG 1> $DIR_LOGS/binutils.$ARCH.config.log.txt 2> /dev/null
    wait
    echo "-  ${BINUTILS_VERSION} make..."
    make all 1> /dev/null 2> $DIR_LOGS/binutils.$ARCH.make.log.txt
    wait
    make install 1> $DIR_LOGS/binutils.$ARCH.install.log.txt 2> /dev/null
    wait
    [ ! -f $PREFIX/bin/$TARGET-ld ] && echo "Error: binutils-${BINUTILS_VERSION} not installed, check logs" && exit
    echo "-  ${BINUTILS_VERSION} installed in $PREFIX  -"
}

fnCompileGCC ()
# Function: Compiling GCC in PREFIX location
{
    export PATH=$PATH:$PREFIX/bin
    cd $DIR_DOWNLOADS
    echo
   [ ! -f $DIR_DOWNLOADS/gcc-${GCC_VERSION}.tar.bz2.extracted ] && echo "-  gcc-${GCC_VERSION} extract..." && tar -xf gcc-${GCC_VERSION}.tar.bz2 > gcc-${GCC_VERSION}.tar.bz2.extracted 
    echo "-  gcc-${GCC_VERSION} extracted"
    wait
    [ ! -d ${DIR_GCC}/$ARCH-gcc ] && mkdir ${DIR_GCC}/$ARCH-gcc 
    [ -d ${DIR_GCC}/$ARCH-gcc ] && cd ${DIR_GCC}/$ARCH-gcc && rm -rf * 
    echo "-  gcc-${GCC_VERSION} configure..."
    ../download/gcc-${GCC_VERSION}/configure --target=$TARGET $GCC_CONFIG > $DIR_LOGS/gcc.$ARCH.config.log.txt 2> /dev/null
    wait
    echo "-  gcc-${GCC_VERSION} make..."
    make all-gcc 1> /dev/null 2> $DIR_LOGS/gcc.$ARCH.make.log.txt
    wait
    make install-gcc 1> $DIR_LOGS/gcc.$ARCH.install.log.txt 2> /dev/null
    wait
    [ ! -f $PREFIX/bin/$TARGET-gcc ] && echo "Error: gcc-${GCC_VERSION} not installed, check logs" && exit
    echo "-  gcc-${GCC_VERSION} installed in $PREFIX  -"  
    echo
}

fnMakeSymLinks ()
# Function: SymLinks in PREFIX location
{
    [ ! -d ${PREFIX}/$ARCH ] && mkdir ${PREFIX}/$ARCH
    cd $PREFIX/$ARCH
    ln -s $PREFIX/bin/$TARGET-gcc $PREFIX/$ARCH/gcc 2> /dev/null 
    ln -s $PREFIX/bin/$TARGET-ld $PREFIX/$ARCH/ld 2> /dev/null 
    ln -s $PREFIX/bin/$TARGET-objcopy $PREFIX/$ARCH/objcopy 2> /dev/null 
    ln -s $PREFIX/bin/$TARGET-ar $PREFIX/$ARCH/ar 2> /dev/null 
    wait
    echo "Finished: symlinks are in: "$PREFIX/$ARCH
}

### ARGUMENTS fnFunctions ### 


fnALL ()
# Functions: Build all source
{
    fnDownloadLibs
    fnCompileLibs
    fnCompileBinutils
    fnCompileGCC
    fnMakeSymLinks
}

fnArchIA32 ()
# Function: setting arch type ia32
{
    export TARGET="$TARGET_IA32"
    echo "-  Building GCC chainload for $TARGET_IA32  -"
    echo "-  To: $PREFIX  -"
    export ARCH="ia32"
    export ABI_VER="32"
}

fnArchX64 ()
# Function: setting arch type x64
{
    export TARGET="$TARGET_X64"
    echo "-  Building GCC chainload for $TARGET_X64  -"
    echo "-  To: $PREFIX  -"
    export ARCH="x64"
    export ABI_VER="64"
}

# 1. Argument ARCH
case "$1" in
''|'-help')
fnHelp && exit
;;
'-all')
if [[ "$rootSystem" == "Leopard" ]]; then
	fnArchIA32
	fnALL
fi	
fnArchX64
fnALL
;;
*)
echo $"Error!"
echo $"Usage: Hello there!!}"
exit 1
esac

