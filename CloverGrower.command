#!/bin/bash
myV="5.0i"
checkDay="Mon"
gccVersToUse="4.8.0" # failsafe check
# Reset locales (important when grepping strings from output commands)
export LC_ALL=C

# Retrieve full path of the command
declare -r CMD=$([[ $0 == /* ]] && echo "$0" || echo "${PWD}/${0#./}")

# Retrieve full path of CloverGrower
declare -r CLOVER_GROWER_SCRIPT=$(readlink "$CMD" || echo "$CMD")
declare -r CLOVER_GROWER_DIR="${CLOVER_GROWER_SCRIPT%/*}"
theShortcut=`echo ~/Desktop`
# Source librarie
source "${CLOVER_GROWER_DIR}"/CloverGrower.lib
export myArch=`uname -m`
if [[ "$1" == ""  && "$myArch" == "x86_64" ]]; then # if NO parameter build 32&64
	target="X64/IA32"
elif [[ "$myArch" == "i386" ]]; then
	target="IA32"
else		
	target="X64"
fi
if [[ "$myArch" == "i386" ]]; then
	archBit='i686'
else
	archBit='x86_64'
fi		
# don't use -e
set -u
user=$(id -un)
theBoss=$(id -ur)
hours=$(get_hours)
theLink=/usr/local/bin/clover
useDEFAULT="No"
gccUpdated="No"
if [[ -L "$theShortcut"/CloverGrower.command ]]; then
	theLink="$theShortcut"/CloverGrower.command
fi
CLOVER_GROWER_DIR_SPACE=`echo "$CLOVER_GROWER_DIR" | tr ' ' '_'`
if [ ! -f /usr/bin/gcc ]; then
	echob "ERROR:"
	echob "      Xcode Command Line Tools from Apple"
	echob "      NOT FOUND!!!!"
	echob "      CloverGrower.command needs it";echo
	echob "      Going To Apple Developer Site"
	echob "      Download & Install XCode Command Line Tools"
	echob "      then re-run CloverGrower.command"
	open "https://developer.apple.com/downloads/"
	wait
	echob "Good $hours $user"
	tput bel
	exit 1
fi
if [[ "$CLOVER_GROWER_DIR_SPACE" != "$CLOVER_GROWER_DIR" ]]; then
	echob "Space in Volume Name Detected!!"
	echob "Recomend you change Volume Name"
	echob " From:" 
	echob "      ${CLOVER_GROWER_DIR}"
	echob "   To:"
	echob "      ${CLOVER_GROWER_DIR_SPACE}"
	echob "You MUST change name to continue"
	echob "Press any to exit "
	read ansr
	echob "OK, change name yourself and re-run ${CLOVER_GROWER_SCRIPT}"
	echob "Good $hours $user"
	exit		
fi	

if [[ ! -L "$theShortcut"/CloverGrower.command || $(readlink "$theShortcut"/CloverGrower.command) != "$CLOVER_GROWER_SCRIPT" ]]; then
	if [[ ! -L /usr/local/bin/clover || $(readlink /usr/local/bin/clover) != "$CLOVER_GROWER_SCRIPT" ]]; then
		echob "Running CloverGrower.command"
		theText="link"
		echob "To make it easier to use I will do one of the following"
		echob "Create link, in /usr/local/bin.     Select any key"
		echob "Create Shortcut, put it on Desktop. Select 's'"
		echob "Type 's' OR any key"
		read theSelect
		case "$theSelect" in
                s|S)
                     theLink="$theShortcut"/CloverGrower.command
                     theText="shortcut"
                     sudoit=
                     ;;
                *)
                sudoit="sudo"
        esac
		printf "Will create link %s to %s\n" $(echob "$theLink") $(echob "CloverGrower.command")
		if [ "$theLink" == /usr/local/bin/clover ]; then
			echob "You can THEN 'run' CloverGrower.command by typing 'clover' ;)"
			if [ ! -d /usr/local/bin ]; then
				command='sudo mkdir -p /usr/local/bin'; echob "$command" ; eval "$command"
			fi
		else
			echob "You can THEN run by double clicking CloverGrower.command on Desktop"
		fi		
		command='$sudoit ln -sf "${CLOVER_GROWER_SCRIPT}" "$theLink" && $sudoit chown $theBoss "$theLink"'
		echob "$command" ; eval "$command"
	fi
fi

#vars
export WORKDIR="${CLOVER_GROWER_DIR}"
export TOOLCHAIN="${WORKDIR}/toolchain"
workSpace=$(df -m "${WORKDIR}" | tail -n1 | awk '{ print $4 }')
workSpaceNeeded="522"
workSpaceMin="104"
filesDIR="${WORKDIR}"/Files
CustomRCFiles="${WORKDIR}"/CustomRCFiles
srcDIR="${WORKDIR}"/src
edk2DIR="${srcDIR}"/edk2
CloverDIR="${edk2DIR}"/Clover
rEFItDIR="${CloverDIR}"/rEFIt_UEFI
buildDIR="${edk2DIR}"/Build
cloverPKGDIR="${CloverDIR}"/CloverPackage
builtPKGDIR="${WORKDIR}"/builtPKG
theBuiltVersion=""

# Some Flags
buildClover=0

flagTime="No" # flag for complete download/build time, GCC, edk2, Clover, pkg

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
    9) export rootSystem="Leopard" ;;
    10) export rootSystem="Snow Leopard" ;;
    11) export rootSystem="Lion" ;;
    12)	export rootSystem="Mountain Lion" ;;
    [13-20]) sysmess="Unknown" ;;
esac

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
function checkSites(){
checkSiteExists=`curl -s "$2" | grep '404'`
wait
if [[ "${checkSitExists:7:13}" == "404 Not Found" ]]; then
	echob "$1 ERROR!"
	exit 1
fi
getSOURCEFILE "$1" "$2"
wait
}
				
# set up Revisions
function getREVISIONSClover(){
cloverstats=`svn info svn://svn.code.sf.net/p/cloverefiboot/code | grep 'Revision'`
export CloverREV="${cloverstats:10}"
if [ "$1" == "Initial" ]; then
	echo "${CloverREV}" > "${CloverDIR}"/Lvers.txt	# make initial revision txt file
fi			
#rEFIt
refitstats=`svn info svn://svn.code.sf.net/p/cloverefiboot/code/rEFIt_UEFI | grep 'Last Changed Rev:'`
export rEFItREV="${refitstats:18}"
wait
}

# set up Revisions
function getREVISIONSedk2(){
checksvn=`curl -s http://edk2.svn.sourceforge.net/viewvc/edk2/ | grep "Revision"`
wait
export edk2REV="${checksvn:53:5}"
wait
if [ "$1" == "Initial" ]; then
	basestats=`curl -s  http://edk2.svn.sourceforge.net/viewvc/edk2/trunk/edk2/BaseTools/ | grep 'Revision'`
	basetools="${basestats:53:5}" # grab basetools revision, rebuild tools IF revision has changed
	echo "${edk2REV}" > "${edk2DIR}"/Lvers.txt	# update revision
	echo "${basetools}" > "${edk2DIR}"/Lbasetools.txt	# update revision
	wait
fi
}

function getREVISIONSgcc() {
	checkgccsvn=`curl -s http://gcc.gnu.org/viewcvs/gcc/ | grep "Revision"`
	wait
	export releaseGCC="${checkgccsvn:53:6}"
	echo $releaseGCC
}	

# check URL IS IN FACT, ONLINE, fail IF NOT.
function checkURL {
	[[ "$2" == "gcc" ]] && echob "$3"
	echob "    Verifying $2 URL"
	echob "    $1"
	curl -s -o "/dev/null" "$1"
	wait
    if [ $? -ne 0 ] ; then
        echob "    Error occurred"
        if [[ "$2" != "gcc" ]]; then
        	if [ $? -eq 6 ]; then
            	echob "    Unable to resolve host"
        	fi
        	if [$? -eq 7 ]; then
            	echob "    Unable to connect to host"
        	fi
        	echob "    Appears to be URL Problem"
        	exit 1
        fi
        useDEFAULT="Yes"	
    else
     	echob "    VERIFIED"
     	sleep 3 
    fi

}

# checkout/update svn
# $1=Local folder, $2=svn Remote folder
function getSOURCEFILE() {
	checkURL "$2" "$1"
	if [ ! -d "$1" ]; then
        mkdir "$1"
		getREVISIONS${1} Initial # flag to write initial revision
		wait
      	echo -n "    Check out $1  "
		(svn co "$2" "$1" --non-interactive --trust-server-cert >/dev/null) &
	else
    	echo -n "    Auto Update $1  "
    	(cd "$1" && svn up --non-interactive --trust-server-cert >/dev/null) &
    fi
	spinner $!
	checkit "  SVN $1"
}

# sets up svn sources
function getSOURCE() {
    if [ ! -d "${srcDIR}" ]; then
        echob "    Make src Folder.."
        mkdir "${srcDIR}"
    fi
   
    # Don't update edk2 if no Clover updates
    if [[  "${cloverUpdate}" == "Yes" || ! -d "${edk2DIR}" || "$gccUpdated" == "Yes" ]]; then
        # Get edk2 source
        cd "${srcDIR}"
	    getSOURCEFILE edk2 "https://edk2.svn.sourceforge.net/svnroot/edk2/trunk/edk2"
	    wait
	    if [[ -f "${edk2DIR}"/Basetools/Source/C/bin/VfrCompile ]]; then 
	    	if [[ "${cloverUpdate}" == "Yes" ]]; then
				basestats=`curl -s  http://edk2.svn.sourceforge.net/viewvc/edk2/trunk/edk2/BaseTools/ | grep 'Revision'`
				basetools="${basestats:53:5}" # grab basetools revision, rebuild tools IF revision has changed
				Lbasetools=`cat "${edk2DIR}"/Lbasetools.txt`
			    if [[ "$basetools" -gt "$Lbasetools" ]]; then # rebuild tools IF revision has changed
			    	echob "    BaseTools @ Revision $basetools"
					echob "    Updated BaseTools Detected"
					echo -n "    Clean EDK II BaseTools "
					make -C "${edk2DIR}"/BaseTools clean >/dev/null
					wait
				fi								
			fi	
		fi	
	fi
	cd "${edk2DIR}"
	if [[ ! -f ./Basetools/Source/C/bin/VfrCompile  && -f ./edksetup.sh ]]; then # build tools ONCE, unless they get UPDATED,then they will be built, as above
      	echo -n "    Make edk2 BaseTools.. "
        make -C "${edk2DIR}"/BaseTools &>/dev/null &
        spinner $!
        checkit "Basetools Compile"
    fi
	# Get Clover source
    getSOURCEFILE Clover "svn://svn.code.sf.net/p/cloverefiboot/code/"
    wait
}

# compiles X64 or IA32 versions of Clover and rEFIt_UEFI
function cleanRUN(){
	builder=gcc
	bits=$1
	theBits=$(echo "$bits" | awk '{print toupper($0)}')
	theBuilder=$(echo "$builder" | awk '{print toupper($0)}')
	theStyle=$(echo "$style" | awk '{print toupper($0)}')
	clear
	echo "	Starting Build Process: $(date -j +%T)"
	echo "	Building Clover$theBits: gcc${mygccVers} $style"
	clear
	if [ "$bits" == "X64/IA32" ]; then
		archBits='x64 mc ia32'	
	elif [[ "$myArch" == "i386" ]]; then
		archBits='ia32'
	else
		archBits='x64'
	fi		
	cd "${CloverDIR}"
	for az in $archBits ; do
		echob "	 running ./ebuild.sh -gcc${mygccVers} -$az -$style"
		./ebuild.sh -gcc${mygccVers} -$az -"$style"
		checkit "Clover$az $theStyle"
		if [[ $az == ia32 ]]; then 
			cd "${rEFItDIR}"
			clear
			echob "	 Building rEFIt32: $builder $style $(date -j +%T)"
			echob "	 With build32.sh"
			./"build32.sh" 
			checkit "rEFIT_UEFI_$theBits: $theStyle" 
			cd ..
		fi
		rm -rf "${buildDIR}"
	done	
}
	
# sets up 'new' sysmlinks for >=gcc47
function MakeSymLinks() {
# Function: SymLinks in CG_PREFIX location
# Need this here to fix links if Files/.CloverTools gets removed
    if [[ "$target" == "IA32" ]]; then
    	DoLinks "ia32" "i686-linux-gnu"
    else	
        DoLinks "x64"  "x86_64-linux-gnu"
    fi    
}

#makes 'new' syslinks
function DoLinks(){
    ARCH="$1"
    TARGETARCH="$2"
    if [[ ! -d "${TOOLCHAIN}/${ARCH}" ]]; then
        mkdir -p "${TOOLCHAIN}/${ARCH}"
    fi
    if [[ $(readlink "${TOOLCHAIN}/${ARCH}"/gcc) != "${CG_PREFIX}"/bin/"$TARGETARCH-gcc" ]]; then # need to do this
        echo "  Fixing your GCC${mygccVers} ${ARCH} Symlinks"
        for bin in gcc ar ld objcopy; do
            ln -sf "${CG_PREFIX}"/bin/$TARGETARCH-$bin  "${TOOLCHAIN}/${ARCH}"/$bin
        done
        echo "  Finished: Fixing"
        echo "  symlinks are in: ${TOOLCHAIN}/$ARCH"
    fi
}

# checks for gcc install and installs if NOT found
function checkGCC(){
    export mygccVers="${gccVers:0:1}${gccVers:2:1}" # needed for BUILD_TOOLS e.g GCC46
    gccDIRS="/usr/local /opt/local $WORKDIR/src/CloverTools" # user has 3 choices for gcc install
    echob "Checking gcc $gccVers INSTALL status"
    for theDIRS in $gccDIRS; do # check install dirs for gcc
        CG_PREFIX="${theDIRS}" #else
        echo "  Checking ${theDIRS}"
        if [ -x "${CG_PREFIX}/bin/${archBit}"-linux-gnu-gcc ]; then
            local lVers=$("${CG_PREFIX}/bin/${archBit}"-linux-gnu-gcc -dumpversion)
            export mygccVers="${lVers:0:1}${lVers:2:1}" # needed for BUILD_TOOLS e.g GCC46
            echo "  gcc $lVers detected in ${theDIRS}"
            read -p "  Do you want to use it [y/n] " choose
            case "$choose" in
                n|N)
                     CG_PREFIX=""
                     break
                     ;;
                y|Y)
                     echo "  Fixing gcc…"
                     MakeSymLinks
                     echo "${lVers}" > "${filesDIR}"/.gccVersion
                     return
                     ;;
                *)
                   echob "  Good $hours $user"
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
echob "CloverTools using gcc $gccVers NOT installed";echo
echob "Install CloverTools using gcc $gccVers to folder"
echo "  Enter 'o'"
echob "  to PERMANENTLY install to: /opt/local (RECOMMENDED)"
echo "  Enter 'c'"
echob "  to install to: $WORKDIR/src/CloverTools"
echo "  Enter 'u'"
echob "  to PERMANENTLY install to: /usr/local"
echob "  Hit 'return' to EXIT"
echob "  Type letter and hit <RETURN>: "
sudoIT="sudo" # install to /opt OR /usr need sudo
read choose
case $choose in
	c|C)
	CG_PREFIX="${WORKDIR}"/src/CloverTools
	sudoIT="sh" # if install to above NO need to sudo ( well hopefully)
	;;
	o|O)
	CG_PREFIX="/opt/local"
	;;
	u|U)
	CG_PREFIX="/usr/local"
	;;
	*)
	echob "	 Good $hours"
	exit 1
	esac
if [ "$sudoIT" == "sudo" ];then
	echob "  Need Admin Privileges for ${CG_PREFIX}"
	[ ! -d "${CG_PREFIX}"/src ] && "$sudoIT" mkdir -p "${CG_PREFIX}"/src && "$sudoIT" chown -R root:wheel "${CG_PREFIX}"
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
("$sudoIT" ./buildgcc.sh -all "${CG_PREFIX}" "$gccVers") #& # build all to CG_PREFIX with gccVers
wait    
tput bel
cd ..
if [ -f "${CG_PREFIX}"/ia32/gcc ] || [ -f "${CG_PREFIX}"/x64/gcc ]; then
	echo "${CG_PREFIX}" >"${filesDIR}"/.CloverTools # if 2 above are found write into gcc config file
	MakeSymLinks
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
edk2Local=$(cat "${edk2DIR}"/Lvers.txt)
echo $(date)
cloverLocal=${cloverLocal:=''}
echob "*******************************************"
echob "$buildMess"
echob "*    Revisions:- edk2: $edk2Local              *"
echob "*              Clover: $CloverREV            *"
echob "*    Using Flags: gcc$mygccVers ${targetBitsMess} $style  *"
echob "*******************************************"
STARTT=$(date -j "+%H:%M")
STARTM=$(date -u "+%s")
cleanRUN "$theARCHS"
}

autoBuild(){
	
	if [ "$built" == "No " ]; then
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
	getREVISIONSClover "test" # get Clover SVN revision, returns in CloverREV, "test" is dummy flag, does NOT write revision in folder
	versionToBuild="${CloverREV}" # Clover not checked out so use it.
	if [ -f "${builtPKGDIR}/${versionToBuild}/Clover_v2_r${versionToBuild}".pkg ] && [ -d "${CloverDIR}" ]; then # don't build IF pkg already here
		if [ -f "${builtPKGDIR}/${versionToBuild}"/CloverCD/EFI/BOOT/BOOTX64.efi ]; then
			theBuiltVersion=$(strings "${builtPKGDIR}/${versionToBuild}/CloverCD/EFI/BOOT/BOOTX64.efi" | sed -n 's/^Clover revision: *//p')
			if [ "${theBuiltVersion}" == "${versionToBuild}" ]; then
				built="Yes"
			else
				built="No "
				cloverUpdate="Yes"
			fi
			clear
			echob "*********Clover Build STATS***********"
			echob "*      remote revision at ${CloverREV}       *" 
			echob "*      local  revision at ${versionToBuild}       *"
			if [ "$built" == "Yes" ]; then
				echob "* Clover_v2_r${versionToBuild}.pkg ALREADY Made! *"
				echob "**************************************"
				return
			fi
			echob "*      Package Built   =  $built        *"
			echob "**************************************"
		fi
	fi	
	echo
	echob "********************************************"
	echob "*             Good $hours              *"
	echob "*      Welcome To CloverGrower V$myV       *"
	echob "*        This script by STLVNUB            *"
	echob "* Clover Credits: Slice, dmazar and others *"
	echob "********************************************"
	echob "Forum: http://www.projectosx.com/forum/index.php?showtopic=2562";echo
	echob "$user running '$(basename $CMD)' on '$rootSystem'"
	echob "Build  Stats:-"
	echob "             Clover  : revision: ${CloverREV}"
	echob "             Target  : $target"
	echob "             Compiler: GCC $gccVers";echo
	echob "Folder Stats:-"
	echob "             Work Folder     : $WORKDIR"
	echob "             Available Space : ${workSpaceAvail} MB"
	echo
	if [[ -f "${edk2DIR}"/Basetools/Source/C/bin/VfrCompile ]]; then
		if [[ -d "${CloverDIR}" && -d "${rEFItDIR}" ]]; then
			cloverLVers=$(getSvnRevision "${CloverDIR}")
			if [[ "${cloverLVers}" != "${CloverREV}" ]]; then
            	echob "Clover Update Detected !"
            	cloverUpdate="Yes"
            	echo "$CloverREV" > "${CloverDIR}"/Lvers.txt # update the version
				echob "*********Clover Build STATS***********"
				echob "*      local  revision at ${cloverLVers}       *"
				echob "*      remote revision at ${CloverREV}       *"
				echob "*      Package Built   =  $built        *"
				echob "**************************************"
   				echob "svn changes for $CloverREV"
				cd "${CloverDIR}"
       			changesSVN=$(svn log -v -r "$CloverREV")
       			echob "$changesSVN"
       			tput bel
       			cd ..
       		elif [[ ! -f "${builtPKGDIR}/${versionToBuild}/Clover_v2_r${versionToBuild}".pkg ]]; then
       			echob "Clover_v2_r${versionToBuild}.pkg NOT built"
    		else
            	echob "No Clover Update found."
            	echob "Current revision: ${cloverLVers}"
            fi
    	fi
    	sleep 3
    elif [[ -d "${edk2DIR}" && ! -f "${edk2DIR}"/Basetools/Source/C/VfrCompile && ! -f "${edk2DIR}"/edksetup.sh ]]; then
    		getREVISIONSedk2 "test"
    		echob "svn edk2 revision: ${edk2REV}"
    		echob "error!!! DELETE & RETRY"
	    	rm -rf "${edk2DIR}"
	else    	
	      	cloverUpdate="Yes"
    fi
    if [[ ! -d "${rEFItDIR}" || "$cloverUpdate" == "Yes" ]]; then # only get source if NOT there or UPDATED.
    	echob "Getting SVN Source Files, Hang ten…"
    	getSOURCE
   	 	versionToBuild="${CloverREV}"
   	else
   		versionToBuild="${cloverLVers}" 	
   	fi 
   	if [[ ! -f "${CloverDIR}"/HFSPlus/X64/HFSPlus.efi ]]; then  # only needs to be done ONCE.
        echob "    Copy Files/HFSPlus Clover/HFSPlus"
    	cp -R "${filesDIR}/HFSPlus/" "${CloverDIR}/HFSPlus/"
    fi
    if [[ ! -f "${CloverDIR}/ebuild.sh.CG" ]]; then
         # Patch ebuild.sh
       echob "    Patching ebuild to GCC${mygccVers}"
       sed -i'.CG' -e "s!export TOOLCHAIN=GCC47!export TOOLCHAIN=GCC${mygccVers}!g" -e "s!-gcc47  | --gcc47)   TOOLCHAIN=GCC47   ;;!-gcc${mygccVers}  | --gcc${mygccVers})   TOOLCHAIN=GCC${mygccVers}   ;;!g" \
         "${CloverDIR}/ebuild.sh"
       wait
       checkit "    Patched Clover ebuild.sh"
    fi
    if [[ ! -f "${rEFItDIR}/build32.sh.CG" ]]; then
         # Patch build32.sh
       echob "    Patching rEFIt/build32.sh to GCC${mygccVers}"
       sed -i'.CG' -e "s!TARGET_TOOLS=GCC47!TARGET_TOOLS=GCC${mygccVers}!g" -e "s!RELEASE_GCC47!RELEASE_GCC${mygccVers}!" "${rEFItDIR}/build32.sh"
       wait
       checkit "    Patched rEFIt build32.sh"
    fi
    if [[ ! -f "${edk2DIR}"/Conf/tools_def.txt.CG ]]; then
    	# Remove old edk2 config files
      	rm -f "${edk2DIR}"/Conf/{BuildEnv.sh,build_rule.txt,target.txt,tools_def.txt}
		wait
       	# Create new default edk2 files in edk2/Conf
      	"${edk2DIR}"/edksetup.sh >/dev/null
    	# get configuration files from Clover
        cp "${CloverDIR}/Patches_for_EDK2/tools_def.txt"  "${edk2DIR}"/Conf/
        cp "${CloverDIR}/Patches_for_EDK2/build_rule.txt" "${edk2DIR}"/Conf/

       # Patch edk2/Conf/tools_def.txt for GCC
       	echob "Patching tools_def.txt to GCC${mygccVers}"
        sed -i'.CG' -e "s!ENV(HOME)/src/opt/local!$TOOLCHAIN!g" -e "s!GCC47!GCC${mygccVers}!g" \
        "${edk2DIR}"/Conf/tools_def.txt
        wait
        checkit "    Patched edk2 Conf/tools_def.txt"
    fi
    echob "    Ready to build Clover $versionToBuild, Using Gcc $gccVers"
    sleep 3
    autoBuild "$1"
    tput bel
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
		echob "Clover revision $CloverREV Compile process took $TTIMEM to complete" 
	fi
	echo "$CloverREV" > "${CloverDIR}"/Lvers.txt
	if [ ! -f "${builtPKGDIR}/${versionToBuild}/Clover_v2_r${versionToBuild}".pkg ]; then # make pkg if not there
		echob "Making Clover_v2_r${versionToBuild}.pkg..."
		sleep 3
		if [ -d "${CloverDIR}"/CloverPackage/sym ]; then
			rm -rf "${CloverDIR}"/CloverPackage/sym
		fi
		cd "${CloverDIR}"/CloverPackage
		#if [[ ! -f "${CloverDIR}"/CloverPackage/package/buildpkg.sh.CG ]]; then
         	# Patch buildpkg.sh 
       		#sed -i'.CG' -e "s!add_ia32=0!add_ia32=1!g" "${CloverDIR}"/CloverPackage/package/buildpkg.sh
       		#wait
       		#checkit "    Patched Clover buildpkg.sh"
    	#fi
		echob "cd to src/edk2/Clover/CloverPackage and run ./makepkg."
		./makepkg "No"
		wait
		echob "mkdir buildPKG/${versionToBuild}."
		[[ ! -d "${builtPKGDIR}" ]] && mkdir "${builtPKGDIR}"
		mkdir "${builtPKGDIR}"/"${versionToBuild}"
		echob "cp src/edk2/Clover/CloverPackage/sym/ builtPKG/${versionToBuild}."
		cp -R "${CloverDIR}"/CloverPackage/sym/ "${builtPKGDIR}"/"${versionToBuild}"/
		echob "rm -rf src/edk2/Clover/CloverPackage/sym."
		rm -rf "${CloverDIR}"/CloverPackage/sym
		echob "rm -rf src/edk2/Build Folder"
		rm -rf "${buildDIR}"
		echob "rm -rf builtPKG/${versionToBuild}/package Folder, it is 'NOT NEEDED'"
		rm -rf "${builtPKGDIR}"/"${versionToBuild}"/package
		echob "open builtPKG/${versionToBuild}."
		open "${builtPKGDIR}"/"${versionToBuild}"
		tput bel
	fi
	
}
[[ ! -f "${filesDIR}/.gccVersion" ]] && echo "${gccVersToUse}" >"${filesDIR}/.gccVersion"

gccVers=$(cat "${filesDIR}/.gccVersion")

# setup gcc
gVers=""
if [ -f "${filesDIR}"/.CloverTools ]; then # Path to GCC4?
	export CG_PREFIX=$(cat "${filesDIR}"/.CloverTools) # get Path
	if [[ -x "${CG_PREFIX}/bin/${archBit}"-linux-gnu-gcc ]]; then
		gVers=$("${CG_PREFIX}/bin/${archBit}-linux-gnu-gcc" -dumpversion)
	fi
fi

if [[ "${gVers}" == "" ]];then
    checkGCC
    [[ -n "${CG_PREFIX}" ]] && echo "${CG_PREFIX}" >"${filesDIR}/.CloverTools"
fi

export mygccVers="${gccVers:0:1}${gccVers:2:1}" # needed for BUILD_TOOLS e.g >GCC47 
buildMess="*    Auto-Build Full Clover rEFIt_UEFI    *"
cleanMode=""
built="No "
makePKG "$target" # do complete build
echob "Good $hours $user, Thanks for using CloverGrower" 
