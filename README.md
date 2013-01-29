CloverGrower
============

Simple compile Tool For Clover UEFI/bios OS X Booter

Downloads, Compiles and makes package for Clover UEFI/bios bootloader by slice & company

Boots the following: (will add more as they come to light)

OS X: Leopard, Snow Leopard, Lion and Mountain Lion

Windows:
Linux:
Unix:



Make sure you have Xcode Command Line Tools installed. Won't work without it.

Unzip and run CloverGrower.command, you only need to do this ONCE.
CloverGrower will download all sources, GCC4.7.2, edk2 and Clover.
First build will take some time as it needs to compile GCC4.7.2, then it builds edk2 BaseTools and then compiles Clover. 

On subsequent uses you only need to open terminal and type "clover"
CloverGrower will update any source files from edk2 or Clover and build you a package.


CloverGrower with JrCs enhancements at git://github.com/JrCs/CloverGrowerPro.git
This is more suited to the Developer/AdvancedUser and should probably be named
"CloverGrowerPro"

