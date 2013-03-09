#Building
#Prepare and build your EDKII environment (outside of the scope of this document).
#Clone the repository into the root directory of the EDKII.
#  $ cd /path/to/edk2
#  $ git clone https://github.com/snarez/refind-edk2.git RefindPkg
#Download the latest version of the rEFInd source into the RefindPkg directory and unpack it.
#  $ cd RefindPkg
 # $ wget http://downloads.sourceforge.net/project/refind/0.4.5/refind-src-0.4.5.zip
#  $ unzip refind-src-0.4.5.zip
#Create a symlink so that the path referred to in the DSC file makes sense.
#  $ ln -s refind-0.4.5 refind
#Build the package.
#  $ cd ..
#  $ source edksetup.sh
#  $ build -p RefindPkg/RefindPkg.dsc
#!/bin/sh
function echob() {
  echo "`tput bold`$1`tput sgr0`"
}
STARTH=`date "+%H"`
if [ $STARTH -ge 04 -a $STARTH -le 12 ]; then
    hours="Morning  "
elif [ $STARTH -ge 12 -a $STARTH -le 17 ]; then
     hours="Afternoon"
elif [ $STARTH -ge 18 -a $STARTH -le 21 ]; then
	hours="Evening  "
else
	hours="Night    "	
fi
WORKDIR=$(cd -P -- $(dirname -- "${0}") && pwd -P)
export TOOLCHAIN="${WORKDIR}/toolchain"

cd "${WORKDIR}"
echob "Good $hours"
[ ! -d EFI/BOOT ] && mkdir -p EFI/BOOT 
initialize(){
	echob "Get Sources: edk2, rEFInd and RefindPkg"
	cd src
	svn co https://edk2.svn.sourceforge.net/svnroot/edk2/trunk/edk2 &
	cd edk2
	git clone https://github.com/snarez/refind-edk2.git RefindPkg
	cd RefindPkg
	git clone git://git.code.sf.net/p/refind/code refind
	#ln -s refind-code refind
	wait
	echob "Done..."
}
[ ! -d "${WORKDIR}"/src/edk2 ] && mkdir -p src/edk2 
if [ -d "${WORKDIR}"/src/edk2 ] && [ -d "${WORKDIR}"/src/edk2/RefindPkg/refind ]; then
	cd "${WORKDIR}"/src/edk2
	svn up https://edk2.svn.sourceforge.net/svnroot/edk2/trunk/edk2
	cd RefindPkg/refind
	git stash
	git pull
	[ -d "${WORKDIR}"/src/edk2/Build ] && rm -rf "${WORKDIR}"/src/edk2/Build 
else
	initialize
	
fi		
cd "${WORKDIR}"/src/edk2
if [ ! -f "${WORKDIR}"/src/edk2/BaseTools/Source/C/bin/VfrCompile ]; then
	echob "  Make EDK II BaseTools"
	make -C "${WORKDIR}"/src/edk2/BaseTools
	wait
fi	
source edksetup.sh
build -p RefindPkg/RefindPkg.dsc -a X64 -b RELEASE  -t GCC47 -n 3 $*
wait
cp "${WORKDIR}"/src/edk2/Build/rEFInd/RELEASE_GCC47/X64/REFIND.efi "${WORKDIR}"/EFI/BOOT/bootx64.efi
build -p RefindPkg/RefindPkg.dsc -a IA32 -b RELEASE  -t GCC47 -n 3 $*
wait
cp "${WORKDIR}"/src/edk2/Build/rEFInd/RELEASE_GCC47/IA32/REFIND.efi "${WORKDIR}"/EFI/BOOT/bootia32.efi
