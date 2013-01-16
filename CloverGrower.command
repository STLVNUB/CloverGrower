#!/bin/bash

myV="4.9a"
gccVersToUse="4.7.2" # failsafe check

# Reset locales (important when grepping strings from output commands)
export LC_ALL=C

# Retrieve full path of the command
declare -r CMD=$([[ $0 == /* ]] && echo "$0" || echo "${PWD}/${0#./}")

# Retrieve full path of CloverGrower
declare -r CLOVER_GROWER_SCRIPT=$(readlink "$CMD" || echo "$CMD")
declare -r CLOVER_GROWER_DIR=${CLOVER_GROWER_SCRIPT%/*}

# Source librarie
source "$CLOVER_GROWER_DIR/CloverGrower.lib"

target="64"
if [ "$1" == "" ]; then
	target="X64/IA32"
fi

set -ue

theBoss=$(id -ur)
hours=$(get_hours)

if [ ! -f /usr/bin/gcc ]; then
	echob "ERROR:"
	echob "      Xcode command line Tools from Apple"
	echob "      NOT FOUND!!!"
	echob "      CloverGrower.command needs it";echo
	echob "      Going To Apple Developer Site"
	echob "      Download & Install XCode then re-run CloverGrower.command"
	open "http://www.google.com.au/url?sa=t&rct=j&q=xcode%20command%20line%20tools&source=web&cd=2&ved=0CCkQFjAB&url=http%3A%2F%2Fdeveloper.apple.com%2Fxcode%2F&ei=RVNBUM7OGNGViQe2soCoDQ&usg=AFQjCNHQA6GfwnaQsSz6TRPjvUEhcQ-ysw"
	wait
	echob "Good $hours"
	tput bel
	exit 1
fi

if [[ ! -L "/usr/local/bin/clover" || $(readlink "/usr/local/bin/clover") != "$CLOVER_GROWER_SCRIPT" ]]; then
	echob "Running CloverGrower.command"
	printf "Will create link %s to %s\n" $(echob "/usr/local/bin/clover") $(echob "CloverGrower.command")
	echob "You can THEN 'run' CloverGrower.command by typing 'clover' ;)"
	read -p "Press 'c' to 'CREATE' the link or else to 'quit': " theKey
	[[ $(lc "$theKey") != "c" ]] && echob "Ok, Bye" && exit
	if [ ! -d /usr/local/bin ]; then
		command="sudo mkdir -p /usr/local/bin"; echob "$command" ; eval $command
	fi	
	command="sudo ln -sf $CLOVER_GROWER_SCRIPT /usr/local/bin/clover && sudo chown $theBoss /usr/local/bin/clover"
	echob "$command" ; eval $command
fi

#vars
export WORKDIR="$CLOVER_GROWER_DIR"
workSpace=$(df -m "${WORKDIR}" | tail -n1 | awk '{ print $4 }')
workSpaceNeeded="522"
workSpaceMin="104"
HFSPlus="${WORKDIR}"/Files/HFSPlus
filesDIR="${WORKDIR}"/Files
UserDIR="${WORKDIR}"/User/etc
etcDIR="${WORKDIR}"/Files/etc
srcDIR="${WORKDIR}"/src
edk2DIR="${WORKDIR}"/src/edk2
CloverDIR="${WORKDIR}"/src/edk2/Clover
rEFItDIR="${WORKDIR}"/src/edk2/Clover/rEFIt_UEFI
buildDIR="${WORKDIR}"/src/edk2/Build
buildAPPS="${WORKDIR}"/src/edk2/BaseTools/Source/C/bin
cloverPKGDIR="${WORKDIR}"/src/edk2/Clover/CloverPackage
builtPKGDIR="${WORKDIR}"/builtPKG
theBuiltVersion=""

flagTime="No" # flag for complete download/build time, GCC, edk2, Clover, pkg
[[ ! -d "${builtPKGDIR}" ]] && mkdir "${builtPKGDIR}"

# Check for svn
[[ -z $(type -P svn) ]] && { echob "svn command not found. Exiting..." >&2 ; exit 1; }

style=release

if [[ ! -d "$edk2DIR" && "$workSpace" -lt "$workSpaceNeeded" ]]; then
	echob "error!!! Not enough free space"
	echob "Need at least $workSpaceNeeded bytes free"
	echob "Only have $workSpace bytes"
	echob "move CloverGrower to different Folder"
	echob "OR free some space"
	exit 1
elif [[ "$workSpace" -lt "$workSpaceMin" ]]; then
	echob "Getting low on free space"
fi
workSpaceAvail="$workSpace"

#what system
theSystem=$(uname -r)
theSystem="${theSystem:0:2}"
case "${theSystem}" in
    [0-8]) sysmess="unsupported" ;;
    9) rootSystem="Leopard" ;;
    10) rootSystem="Snow Leopard" ;;
    11) rootSystem="Lion" ;;
    12)	rootSystem="Mountain Lion" ;;
    [13-20]) sysmess="Unknown" ;;
esac

# set up Revisions
function getREVISIONSClover(){
    # Clover
    export CloverREV=$(svn info svn://svn.code.sf.net/p/cloverefiboot/code | sed -n 's/^Revision: *//p')
    if [ "$1" == "Initial" ]; then
        echo "${CloverREV}" > "${CloverDIR}"/Lvers.txt	# make initial revision txt file
    fi
    # rEFIt
    export rEFItREV=$(svn info svn://svn.code.sf.net/p/cloverefiboot/code/rEFIt_UEFI | sed -n 's/^Last Changed Rev: *//p')
    export cloverVers="${CloverREV}:${rEFItREV}"
}

# set up Revisions
function getREVISIONSedk2(){
	# EDK2
	export edk2REV=$(svn info http://edk2.svn.sourceforge.net/svnroot/edk2/ | sed -n 's/^Revision: *//p')
	echo "${edk2REV}"   > "${edk2DIR}"/Lvers.txt      # update edk2 revision
}

# simple check return value function, does it actually work!!
function checkit(){
	return_val=$?
	if [ ${return_val} == "0" ]; then
		echob "$1 OK"
	else
		echob "$1 $2 error!!"
		exit 1
	fi
}			

# checkout/update svn
# $1=Local folder, $2=svn Remote folder
function getSOURCEFILE(){
edk2REV=""
edk2local=""
access="up"
update=""		
if [ ! -d "$1" ]; then
	echob "    ERROR:"
	echo "          Local $1 Folder Not Found.."
	echob "          Making Local ${1} Folder..."
	mkdir "$1"
	access="co"
	getREVISIONS${1} Initial # flag to write initial revision
	echob "    Checking out Remote $1:"
	echob "    revision: "$(cat $1/Lvers.txt)
	echo "    svn co $2"
	svn co "$2" "$1"
	return 
fi

if [ "${cloverUpdate}" == "Yes" ];then		
	getREVISIONSedk2 
	if [ "$1" == "edk2" ]; then # check for updates
		edk2Local=$(cat "${edk2DIR}"/Lvers.txt)
		if [  "${edk2REV}" == "${edk2Local}" ]; then
			update="No"
			echob "    Checked edk2 SNV, 'No updates were found...'"
			return
		else
			echo "    Remote Svn at revision: $edk2REV"
			echo "    Local edk2 at revision: $edk2Local"
			echob "    Will Auto Update edk2 From $edk2Local TO $edk2REV As Well"
			tput bel
			access="up"
			echo "${edk2REV}" > "${edk2DIR}"/Lvers.txt	# updated revision, so write it	
			update="Yes"	
		fi
	fi
fi
echo "   cd $1"
cd "$1"
echo "   svn $access" # oh yeah
svn up
echo "   cd .."
cd ..
checkit "    Svn $access $1" "$2"
echo
}

# sets up svn sources
function getSOURCE(){
if [ ! -d "${srcDIR}" ]; then
	echob "  Make src Folder.."
	mkdir "${srcDIR}"
fi	
if [ ! -d "${edk2DIR}"/Build/CloverX64 ] && [ ! -d "${edk2DIR}"/Build/CloverIA32 ]; then
	buildMode=">CleanAll< Build  "
fi
if [ -d "${edk2DIR}"/Build/CloverX64 ] || [  -d "${edk2DIR}"/Build/CloverIA32 ]; then
	buildMode=">>>Clean<<< Build "
fi	

cd "${srcDIR}"
getSOURCEFILE edk2 "https://edk2.svn.sourceforge.net/svnroot/edk2/trunk/edk2"

if [ ! -f "${edk2DIR}"/BaseTools/Source/C/bin/VfrCompile ]; then
	echob "  Make EDK II Revision $basetools BaseTools"
	make -C "${edk2DIR}"/BaseTools
fi	

cd "${edk2DIR}"
getSOURCEFILE Clover "svn://svn.code.sf.net/p/cloverefiboot/code/"

if [ -d "${buildDIR}" ] && [ "$cloverUpdate" == "Yes" ]; then
	echob "Clover updated, so rm the build folder"
	rm -Rf "${buildDIR}"/*
fi

if [ "$access" == "co" ]; then # should only need to do this once, on checkout.
	echob "Copy Files/HFSPlus Clover/HFSPlus" 
	cp -R "${HFSPlus}/" "${CloverDIR}"/HFSPlus
	# Path GCC Prefix
	echob "Patching edk2/Conf/tools_def.txt"
	sed -E "s!/opt/local!$CG_PREFIX!g" "${WORKDIR}/Files/tools_def.txt" \
  	> "${edk2DIR}/Conf/tools_def.txt" # changes CG_PREFIX
fi
echo
}

# compiles X64 or IA32 versions of Clover and rEFIt_UEFI
function cleanRUN(){
	echob "Entering function cleanRUN:"
	builder=gcc
	bits=$1
	theBits=$(echo "$bits" | awk '{print toupper($0)}')
	theBuilder=$(echo "$builder" | awk '{print toupper($0)}')
	theStyle=$(echo "$style" | awk '{print toupper($0)}')
	clear
	echo "	Starting $buildMode Process: $(date -j +%T)"
	echo "	Building Clover$theBits: gcc${mygccVers} $style"
	if [ "$bits" == "X64/IA32" ]; then
		archBits='x64 ia32'
		cd "${CloverDIR}"
		for az in $archBits ; do
			echob "	 running ./ebuild.sh -gcc${mygccVers} -$az -$style"
			./ebuild.sh -gcc${mygccVers} -$az -"$style" 
			wait
			checkit "Clover$az $theStyle"
		done
		cd "${rEFItDIR}"
		echob "	 Building rEFIt32: $builder $style $(date -j +%T)"
		echob "	 With build32.sh"
		./"build32.sh" 
		checkit "rEFIT_UEFI_$theBits: $theStyle" 
	else
		cd "${CloverDIR}"
		echob "	 running ./ebuild.sh -gcc${mygccVers} -X64 -$style"
		./ebuild.sh -gcc${mygccVers} -x64 -"$style" 
		checkit "CloverX64 $theStyle"
	fi
	echob "Exiting function cleanRUN:";echo
}

# sets up 'new' sysmlinks for gcc47
function MakeSymLinks()
# Function: SymLinks in CG_PREFIX location
# Need this here to fix links if Files/.CloverTools gets removed
{
    ARCHs="ia32"
    TARGET="i686-linux-gnu"
    DoLinks
    ARCHs="x64"
    TARGET="x86_64-linux-gnu"
    DoLinks
}

#makes 'new' syslinks
function DoLinks(){  
	if [ ! -f "${CG_PREFIX}"/"$ARCHs"/gcc ] && [ -d "${CG_PREFIX}"/"$ARCHs" ]; then
   		if [ -f "${CG_PREFIX}"/bin/$TARGET-gcc ]; then
   			echo "Attempting To Fix your symlinks Folder"   			
   			rm -Rf "${CG_PREFIX}"/"$ARCHs"
   	   	fi
   	   	echo "  Making 'NEW' symlinks Folder $ARCHs"
   		[ ! -d "${CG_PREFIX}"/"$ARCHs" ] && mkdir -p "${CG_PREFIX}"/"$ARCHs"
      	echo "  Fixing your $gccVers Symlinks"
   		pushd "${CG_PREFIX}"/"$ARCHs" > /dev/null
    	ln -s "${CG_PREFIX}"/bin/$TARGET-gcc "${CG_PREFIX}"/$ARCHs/gcc #2> /dev/null 
    	ln -s "${CG_PREFIX}"/bin/$TARGET-ld "${CG_PREFIX}"/$ARCHs/ld #2> /dev/null 
    	ln -s "${CG_PREFIX}"/bin/$TARGET-objcopy "${CG_PREFIX}"/$ARCHs/objcopy #2> /dev/null 
    	ln -s "${CG_PREFIX}"/bin/$TARGET-ar "${CG_PREFIX}"/$ARCHs/ar #2> /dev/null 
    	wait
    	popd  > /dev/null
    	echo "  Finished: Fixing"
   		echo "  symlinks are in: ${CG_PREFIX}/$ARCHs"
    fi
    echo "${CG_PREFIX}" >"${WORKDIR}"/Files/.CloverTools
	
}

# checks for gcc install and installs if NOT found
function checkGCC(){
export mygccVers="${gccVers:0:1}${gccVers:2:1}" # needed for BUILD_TOOLS e.g GCC46
gccDIRS="/usr/local /opt/local $WORKDIR/src/CloverTools" # user has 3 choices for gcc install
echob "Entering function checkGCC:"
echo "  Checking gcc $gccVers INSTALL status"
for theDIRS in $gccDIRS; do # check install dirs for gcc
CG_PREFIX="${theDIRS}" #else
echo "  Checking ${theDIRS}"
if [ -f "${CG_PREFIX}"/bin/i686-linux-gnu-gcc ] || [ -f "${CG_PREFIX}"/bin/x86_64-linux-gnu-gcc ]; then
	lVers=$("${CG_PREFIX}/bin/i686-linux-gnu-gcc" --version | grep '(GCC)')
	lVers="${lVers:25:5}"
	ggVers="${lVers:0:1}${lVers:2:1}" 
	export mygccVers="${ggVers}" # needed for BUILD_TOOLS e.g GCC46
	if [ "${ggVers}" != "${mygccVers}" ]; then
		echo "  gcc $lVers detected, will use it"
		return 0
	else 
		echo "  gcc $gVers detected"
		echo "  in ${theDIRS}"
	fi
	echo "  Do you want to use it"
	echo "  Enter 'n' for 'no'"
	echo "         Or"
	echo "  Enter 'y' to continue..."
	echo -n "  Type letter and hit <RETURN>: "
	read choose
	case $choose in
	n|N)
	CG_PREFIX=""
	break
   	;;
   	y|Y)
	echo "  Fixing gcc…"
	MakeSymLinks
	echo "${gVers}" > "${filesDIR}"/.gccVersion
	return
	;;
	*)
	echob "  Good $hours"
	exit 1
	esac	
else
	sleep 1
	echob "  ...Not Found"	
fi	
done
installGCC
}

function installGCC(){
echob "  CloverTools using gcc $gccVers NOT installed"
echo ""
echo "  Enter 'o' to PERMANENTLY install CloverTools to working directory"
echob "            /opt/local (RECOMMENDED)"
echo "  Enter 't' to install CloverTools to working directory" 
echob "            $WORKDIR/src/CloverTools"
echo "  Enter 'p' to PERMANENTLY install CloverTools to working directory"
echob "            /usr/local"
echo "  Hit 'return' to EXIT"
echo "  Type letter and hit <RETURN>: "
sudoIT="sudo" # install to /opt OR /usr need sudo
read choose
case $choose in
	t|T)
	CG_PREFIX="${WORKDIR}"/src/CloverTools
	sudoIT="sh" # if install to above NO need to sudo ( well hopefully)
	;;
   	o|O)
	CG_PREFIX="/opt/local"
	;;
	p|P)
	CG_PREFIX="/usr/local"
	;;       	
	*)
	echob "  Good $hours"
	exit 1
	esac
if [ "$sudoIT" == "sudo" ];then
	echob "  Need Admin Privileges for ${CG_PREFIX}"
	[ ! -d "${CG_PREFIX}"/src ] && "$sudoIT" mkdir -p "${CG_PREFIX}"/src && "$sudoIT" chown -R 0:0 "${CG_PREFIX}"
else
	[ ! -d "${CG_PREFIX}"/src ] && mkdir -p "${CG_PREFIX}"/src
fi		
cd "${WORKDIR}"/Files
echo "  Download and install CloverGrower gcc Compile Tools"
echob "  To: ${CG_PREFIX}"
echo "  Press any key to start the process..."
read
echo "  $sudoIT Files/buildgcc -all ${CG_PREFIX} $gccVers"
echob "  Starting CloverGrower Compile Tools process..." 
STARTM=$(date -u "+%s")
date
"$sudoIT" ./buildgcc.sh -all "${CG_PREFIX}" "$gccVers" #& # build all to CG_PREFIX with gccVers
wait
tput bel
cd ..
if [ -f "${CG_PREFIX}"/ia32/gcc ] || [ -f "${CG_PREFIX}"/x64/gcc ]; then
	echo "${CG_PREFIX}" >"${WORKDIR}"/Files/.CloverTools # if 2 above are found write into gcc config file
	flagTime="Yes"
	return 
elif [ ! -f "$CG_PREFIX"/ia32/gcc ] && [ ! -f "$CG_PREFIX"/x64/gcc ]; then
	echob " Clover Compile Tools install ERROR: will re-try"
	checkGCC
	return
fi
}

# main function
function Main(){
STARTD=$(date -j "+%d-%h-%Y")
theARCHS="$1"
buildMode=">>>>New<<<< Build "
edk2Local=$(cat "${edk2DIR}"/Lvers.txt)
echo $(date)
cloverLocal=${cloverLocal:=''}
echob "*******************************************"
echob "$buildMess"
echob "*    Revisions:- edk2: $edk2Local              *"
echob "*              Clover: $cloverVers            *"
echob "*    Using Flags: gcc$mygccVers ${targetBitsMess} $style  *"
echob "*******************************************"
STARTT=$(date -j "+%H:%M")
STARTM=$(date -u "+%s")
cleanRUN "$theARCHS"
}

autoBuild(){
	
	if [ "$built" == "No" ]; then
		buildMess="*    Auto-Build Full Clover rEFIt_UEFI    *"
		cleanMode=""
		targetBits="$1"
		targetBitsMess="${targetBits}"
		Main "${targetBits}"
		built="Yes"
	fi	
}	

# makes pkg if Built OR builds THEN makes pkg
function makePKG(){
	versionToBuild=""
	cloverUpdate="No"
	clear;echo
	echob "********************************************"
	echob "*             Good $hours               *"         
	echob "*      Welcome To CloverGrower V$myV       *"
	echob "*        This script by STLVNUB            *"
	echob "* Clover Credits: Slice, dmazar and others *"
	echob "********************************************";echo
	echob "running '$(basename $CMD)' on '$rootSystem'";echo
	echob "Work Folder: $WORKDIR"
	echob "Available  : ${workSpaceAvail} MB"
	getREVISIONSClover "test" # get Clover SVN revision, returns in CloverREV, "test" is dummy flag, does NOT write revision in folder
	versionToBuild="${CloverREV}" # Clover not checked out so use it.
	if [ -f "${builtPKGDIR}/${versionToBuild}/Clover_v2_rL${versionToBuild}".pkg ] && [ -d "${CloverDIR}" ] && [ "$target" != "64" ]; then # don't build IF pkg already here
		if [ -f "${builtPKGDIR}/${versionToBuild}"/CloverCD/EFI/BOOT/BOOTX64.efi ]; then
			theBuiltVersion=$(strings "${builtPKGDIR}/${versionToBuild}/CloverCD/EFI/BOOT/BOOTX64.efi" | grep 'Clover revision:')
			theBuiltVersion="${theBuiltVersion:17:4}" # changed 3 to 4, DOH into 1000's now
			if [ "${theBuiltVersion}" == "${versionToBuild}" ]; then
				built="Yes"
			else
				built="No"
				cloverUpdate="Yes"
			fi
			echob "*********Clover Package STATS***********"
			echob "*       remote revision at ${CloverREV}         *" 
			echob "*       local  revision at ${versionToBuild}         *"
			echob "*       Package Built   =  $built         *"
			echob "****************************************"
			if [ "$built" == "Yes" ]; then
				echob "Clover_v2_rL${versionToBuild}.pkg ALREADY Made!!"
				return
			fi	
		fi
	fi	
	if [ -f "${CloverDIR}"/Lvers.txt ]; then # if NOT there, must be New, so check out needed
		cloverLVers=$(cat "${CloverDIR}"/Lvers.txt)
		edk2Local=$(cat "${edk2DIR}"/Lvers.txt)
		cloverLocal=$(svn info "${edk2DIR}"/Clover | sed -n 's/^Last Changed Rev: *//p')
		if [ "${cloverLVers}" != "${CloverREV}" ]; then
			echob "Update Detected:"
			cloverUpdate="Yes"
			versionToBuild="${CloverREV}" # use it
		elif [ "${cloverLocal}" != "${CloverREV}" ]; then
			versionToBuild="${cloverLocal}"
		else
			versionToBuild="${cloverLVers}" # use local revision
		fi
		echob "*********Clover STATS***********"
		echob "*   remote revision at ${CloverREV}     *" 
		echob "*   local  revision at ${cloverLVers}     *"
		echob "********************************"
	fi
	if [ "${cloverUpdate}" == "Yes" ] || [ "$built" == "No" ]; then
		if [ ! -f "${CloverDIR}"/Lvers.txt ] || [ "$cloverUpdate" == "Yes" ]; then
			echob "Getting SVN Source, Hang ten…"
			getSOURCE
			versionToBuild="${CloverREV}"
		fi
		if [ "${cloverUpdate}" == "Yes" ]; then
			echob "svn changes for $CloverREV"
			cd "${CloverDIR}"
			changesSVN=$(svn log -v -r "$CloverREV")
			echob "$changesSVN"
			echob "Press any key…"
			tput bel
			read
			cd ..
		fi
		echob "Ready to build Clover $CloverREV, Using Gcc $gccVers"
		sleep 2
		autoBuild "$1"
		wait
		tput bel
	fi
	if [ "$flagTime" == "Yes" ]; then
		STOPBM=$(date -u "+%s")
		RUNTIMEMB=$(expr $STOPBM - $STARTM)
		if (($RUNTIMEMB>59)); then
			TTIMEMB=$(printf "%dm%ds\n" $((RUNTIMEMB/60%60)) $((RUNTIMEMB%60)))
		else
			TTIMEMB=$(printf "%ds\n" $((RUNTIMEMB)))
		fi
		echob "Clover	Grower Complete Build process took $TTIMEMB to complete..."
	else
		STOPM=$(date -u "+%s")
		RUNTIMEM=$(expr $STOPM - $STARTM)
		if (($RUNTIMEM>59)); then
			TTIMEM=$(printf "%dm%ds\n" $((RUNTIMEM/60%60)) $((RUNTIMEM%60)))
		else
			TTIMEM=$(printf "%ds\n" $((RUNTIMEM)))
		fi	
		echob "Clover revision $cloverVers Compile process took $TTIMEM to complete" 
	fi
	echo "$CloverREV" > "${CloverDIR}"/Lvers.txt
	if [ "$target" == "X64/IA32" ]; then
		if [ ! -f "${builtPKGDIR}/${versionToBuild}/Clover_v2_rL${versionToBuild}".pkg ]; then # make pkg if not there
			echob "Type 'm' To make Clover_v2_rL${versionToBuild}.pkg..."
			read choose
			case $choose in
			m|M)
			if [ -d "${CloverDIR}"/CloverPackage/sym ]; then
			 	rm -rf "${CloverDIR}"/CloverPackage/sym
			fi
			if [ -f "${UserDIR}"/rc.local ] || [ -f "${UserDIR}"/rc.shutdown.local ]; then
				if [ -f "${UserDIR}"/rc.local ]; then
					echob "copy User rc.local To Package"
					cp -R "${UserDIR}"/rc.local "${CloverDIR}"/CloverPackage/CloverV2/etc
				fi
					
				if [ -f "${UserDIR}"/rc.shutdown.local ]; then
					echob "copy User rc.shutdown.local To Package"
					cp -R "${UserDIR}"/rc.shutdown.local "${CloverDIR}"/CloverPackage/CloverV2/etc
				fi	
			fi	
			cd "${CloverDIR}"/CloverPackage
			echob "cd to src/edk2/Clover/CloverPackage and run ./makepkg."
			./makepkg "No"
			wait
			echob "mkdir buildPKG/${versionToBuild}."
			mkdir "${builtPKGDIR}"/"${versionToBuild}"
			echob "cp src/edk2/Clover/CloverPackage/sym/ builtPKG/${versionToBuild}."
			cp -R "${CloverDIR}"/CloverPackage/sym/ "${builtPKGDIR}"/"${versionToBuild}"/
			echob "rm -rf src/edk2/Clover/CloverPackage/sym."
			rm -rf "${CloverDIR}"/CloverPackage/sym
			echob "rm -rf src/edk2/Build."
			rm -rf "${buildDIR}"
			echob "open builtPKG/${versionToBuild}."
			open "${builtPKGDIR}"/"${versionToBuild}"
	    	tput bel	
			;;
   			*)
   			esac
   		else
   			echob "Clover_v2_rL${versionToBuild}.pkg ALREADY Made!!."
   		fi
   	else 
   		echob "Skipping pkg creation, 64bit Build Only"
   		open "${buildDIR}"/Clover/${theStyle}_GCC${mygccVers}
   	fi	
}

# Check versionBuilt
if [[ -f "${filesDIR}/.gccVersion" ]];then
	gccVers=$(cat "${filesDIR}/.gccVersion")
else
	gccVers=$(curl -s http://gcc.gnu.org/index.html | sed -n 's/.*>GCC \([0-9.]*\)<.*/\1/p' | head -n1) # get latest version info ;)
	if [[ "${gccVers}" != "${gccVersToUse}" ]]; then
		echob "error!!"			  # may be possible that this may not work
		echob "check GCC ${gccVers} is ACTUALLY available"
		echob "EXPERIMENTAL!!!"
		tput bel
		exit
	fi
fi

# setup gcc
gVers=""
if [ -f "${WORKDIR}"/Files/.CloverTools ]; then # Path to GCC4?
	export CG_PREFIX=$(cat "${WORKDIR}"/Files/.CloverTools) # get PAth
	if [ -f "${CG_PREFIX}"/bin/i686-linux-gnu-gcc ] || [ -f "${CG_PREFIX}"/bin/x86_64-linux-gnu-gcc ]; then
		gVers=$("${CG_PREFIX}/bin/i686-linux-gnu-gcc" --version | grep '(GCC)')
		gVers="${gVers:25:5}"
	fi
fi		
if [ "${gVers}" == "" ];  then
	checkGCC
fi
echo "${gccVers}" > "${filesDIR}"/.gccVersion
export mygccVers="${gccVers:0:1}${gccVers:2:1}" # needed for BUILD_TOOLS e.g GCC47
buildMess="*    Auto-Build Full Clover rEFIt_UEFI    *"
cleanMode=""
built="No"
makePKG "$target" # do complete build
echob "Good $hours."
