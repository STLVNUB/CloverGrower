CloverGrowerPro
===============

Compile Tool For Clover UEFI/bios OS X Booter

Downloads, Compiles and makes package for Clover UEFI/Bios Bootloader

This version is an enhanced version of CloverGrower by STLVNUB. It's more suited
to Developers or Advanced Users.


Make sure you have Xcode Command Line Tools installed. Won't work without it.

Unzip and run CloverGrowerPro.sh, you only need to do this ONCE.
CloverGrowerPro will download all sources, GCC4.7.2, edk2 and Clover.
First build will take some time as it needs to compile GCC4.7.2, then it builds
edk2 BaseTools and then compiles Clover.

On subsequent uses you only need to open terminal and type **cloverpro**.  
CloverGrowerPro will update any source files from edk2 or Clover and build you
a package.

## Installation
Do a ***git clone*** (don't use an archive) to install CloverGrowerPro:  

```bash
git clone git://github.com/JrCs/CloverGrowerPro.git
```
## Setup
Start the setup with the CloverGrowerPro.sh command:
```bash
cd CloverGrowerPro
./CloverGrowerPro.sh -s
```

## Build
Start the build with the cloverpro command:
```bash
cloverpro
```

## Help
If you want some help use the command:
```bash
cloverpro -h
```
