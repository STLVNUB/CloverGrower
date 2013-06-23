#!/bin/bash

declare -r CloverGrowerVersion="5.0"
declare -r gccVersToUse="4.7.2" # failsafe check
declare -r self="${0##*/}"

# Reset locales (important when grepping strings from output commands)
export LC_ALL=C

# Retrieve full path of the command
declare -r CMD=$([[ $0 == /* ]] && echo "$0" || echo "${PWD}/${0#./}")

# Retrieve full path of CloverGrowerPro
declare -r CLOVER_GROWER_PRO_SCRIPT=$(readlink "$CMD" || echo "$CMD")
declare -r CLOVER_GROWER_PRO_DIR=${CLOVER_GROWER_PRO_SCRIPT%/*}
declare -r CLOVER_GROWER_PRO_CONF="$CLOVER_GROWER_PRO_DIR/CloverGrowerPro.conf"

# Source librarie
source "$CLOVER_GROWER_PRO_DIR/CloverGrowerPro.lib"

# Check that CloverGrowerPro is well installed
if [[ ! -e "$CLOVER_GROWER_PRO_DIR"/.git ]]; then
    error "Bad installation !"
    sayColor red "$self must be installed with the git clone command and not from an archive !"
    sayColor red "See https://github.com/JrCs/CloverGrowerPro/blob/master/README.md for more information"
    exit 1
fi

# Source config file
[[ ! -f "$CLOVER_GROWER_PRO_CONF" ]] && touch "$CLOVER_GROWER_PRO_CONF"
source "$CLOVER_GROWER_PRO_CONF"

DO_SETUP=
MAKE_PACKAGE=1
CLOVER_REMOTE_REV=
CLOVER_LOCAL_REV=
FORCE_REVISION=
FORCE_CHECK_UPDATE=0
FW_VBIOS_PATH=

# Usage: usage
# Print the usage.
usage () {
    printf "Usage: %s [OPTION]\n" "$self"
    echo "Compile Clover UEFI/Bios OS X Booter"
    echo
    printOptionHelp "-r, --revision"     "compile a specific Clover revision"
    printOptionHelp "-t, --target"       "choose target(s) to build [default=x64]. You can specify multiple targets (ie. --target=\"ia32 x64\")"
    printOptionHelp "-u, --check-update" "force check update."
    printOptionHelp "-s, --setup"        "setup $self."
    printOptionHelp "-h, --help"         "print this message and exit"
    printOptionHelp "-v, --version"      "print the version information and exit"
    echo
    echo "Report any issue to https://github.com/JrCs/CloverGrowerPro/issues"; echo
}

function checkOptions() {
    if [[ -n "$FORCE_REVISION" && ! "$FORCE_REVISION" =~ ^[0-9]*$ ]];then
        die "Invalid revision '$FORCE_REVISION': must be an integer !"
    fi
}

function checkConfig() {
    if [[ -z "$CHECKUPDATEINTERVAL" || -n "$DO_SETUP" ]];then
        local updateInterval
        local msg=$(printf "Check for CloverGrowerPro update every %say/%seek/%sonth/%sever" \
                    $(echob "D") $(echob "W") $(echob "M") $(echob "N"))

        local default_checkupdateinterval='W'

        case ${CHECKUPDATEINTERVAL} in
            -1)       default_checkupdateinterval='N' ;;
            86400)    default_checkupdateinterval='D' ;;
            18446400) default_checkupdateinterval='M' ;;
        esac

        CHECKUPDATEINTERVAL=
        while [[ -z "$CHECKUPDATEINTERVAL" ]]; do
            CHECKUPDATEINTERVAL=$(prompt "$msg" "$default_checkupdateinterval")
            case "$CHECKUPDATEINTERVAL" in
                [Nn]) CHECKUPDATEINTERVAL=-1       ;;
                [Dd]) CHECKUPDATEINTERVAL=86400    ;;
                [Ww]) CHECKUPDATEINTERVAL=604800   ;;
                [Mm]) CHECKUPDATEINTERVAL=18446400 ;;
                *)    CHECKUPDATEINTERVAL= ;;
            esac
        done
        storeConfig 'CHECKUPDATEINTERVAL' "$CHECKUPDATEINTERVAL"
        echo
    fi

    if [[ -z "$TOOLCHAIN" || -n "$DO_SETUP" ]];then
        echo "Where to put the toolchain directory ?"
        local default_toolchain="${TOOLCHAIN:-${CLOVER_GROWER_PRO_DIR}/toolchain}"
        TOOLCHAIN=$(prompt "TOOCHAIN directory" "$default_toolchain")
        storeConfig 'TOOLCHAIN' "$TOOLCHAIN"
        echo
    fi

    if [[ -z "$EDK2DIR" || -n "$DO_SETUP" ]];then
        echo "Where to put the edk2 source files ?"
        local default_edk2dir="${EDK2DIR:-${CLOVER_GROWER_PRO_DIR}/edk2}"
        EDK2DIR=$(prompt "edk2 directory" "$default_edk2dir")
        storeConfig 'EDK2DIR' "$EDK2DIR"
        echo
    fi

    if [[ -z "$CLOVERSVNURL" || -n "$DO_SETUP" ]]; then
        local default_developer='No'
        local default_login=''
        case "$CLOVERSVNURL" in
            *svn+ssh:*) default_developer='Yes'
                        default_login=$(echo "$CLOVERSVNURL" | sed -nE 's#.*//(.+)@.*#\1#p')
                        ;;
        esac
        local developer=$(prompt "Do you have the rights to commit Clover source files" "$default_developer")
        local login
        if [[ $(lc "$developer") == y* ]];then
            login=$(prompt "What is your login on sourceforge.net" "$default_login")
        fi
        if [[ -n "$login" ]];then
            CLOVERSVNURL="svn+ssh://$login@svn.code.sf.net/p/cloverefiboot/code"
        else
            CLOVERSVNURL='svn://svn.code.sf.net/p/cloverefiboot/code'
        fi
        storeConfig 'CLOVERSVNURL' "$CLOVERSVNURL"
        echo
    fi

    if [[ -z "$DEFAULT_TARGET" || -n "$DO_SETUP" ]];then
        DEFAULT_TARGET=$(prompt "Default target to use" "${DEFAULT_TARGET:-x64}")
        storeConfig 'DEFAULT_TARGET' "$DEFAULT_TARGET"
        echo
    fi

    if [[ -z "$VBIOS_PATCH_IN_CLOVEREFI" || -n "$DO_SETUP" ]];then
        local default_vbios_patch_in_cloverefi='No'
        [[ "$VBIOS_PATCH_IN_CLOVEREFI" -ne 0 ]] && \
         default_vbios_patch_in_cloverefi='Yes'
        local answer=$(prompt "Activate VBios Patch in CloverEFI by default" \
         "$default_vbios_patch_in_cloverefi")
        VBIOS_PATCH_IN_CLOVEREFI=0
        [[ $(lc "$answer") == y* ]] && VBIOS_PATCH_IN_CLOVEREFI=1
        storeConfig 'VBIOS_PATCH_IN_CLOVEREFI' "$VBIOS_PATCH_IN_CLOVEREFI"
        echo
    fi

    if [[ -z "$ONLY_SATA0_PATCH" || -n "$DO_SETUP" ]];then
        local default_only_sata0_patch='No'
        [[ "$ONLY_SATA0_PATCH" -ne 0 ]] && \
         default_only_sata0_patch='Yes'
        local answer=$(prompt "Activate Only SATA0 Patch by default" \
         "$default_only_sata0_patch")
        ONLY_SATA0_PATCH=0
        [[ $(lc "$answer") == y* ]] && ONLY_SATA0_PATCH=1
        storeConfig 'ONLY_SATA0_PATCH' "$ONLY_SATA0_PATCH"
        echo
    fi

    if [[ -n "$DO_SETUP" ]];then
        local default_ebuild_optional_args=''
        EBUILD_OPTIONAL_ARGS=$(prompt "Additionnal parameters to pass to ebuild.sh script" "${EBUILD_OPTIONAL_ARGS:-}")
        storeConfig 'EBUILD_OPTIONAL_ARGS' "$EBUILD_OPTIONAL_ARGS"
        echo
    fi

}

function checkUpdate() {
    [[ "$CHECKUPDATEINTERVAL" -lt 0 && "$FORCE_CHECK_UPDATE" -eq 0 ]] && return
    local check_timestamp_file="$CLOVER_GROWER_PRO_DIR/.last_check"
    local last_check=0
    [[ "$FORCE_CHECK_UPDATE" -eq 0 ]] && last_check=$(cat "$check_timestamp_file" 2>/dev/null)
    local now=$(date '+%s')
    if [[ $(( ${last_check:-0} + $CHECKUPDATEINTERVAL )) -lt $now ]]; then
        echo "Checking for new version of CloverGrowerPro..."
        (cd "$CLOVER_GROWER_PRO_DIR" && LC_ALL=C git pull --rebase -f) || exit 1
        echo "$now" > "$check_timestamp_file"
        exec "$0" "${ARGS[@]}"
    fi
}

argument() {
    local opt=$1
    shift
    if [[ $# -eq 0 ]]; then
        die $(printf "%s: option \`%s' requires an argument\n" "$0" "$opt")
    fi
    echo $1
}

# Check the arguments.
declare -a ARGS=()
force_target=

set -e
while [[ $# -gt 0 ]]; do
    option=$1

    case "$option" in
        -h | --help)
                     usage
                     exit 0 ;;
        -v | --version)
                     echo "$self $CloverGrowerVersion"
                     exit 0 ;;
        -r | --revision)
                     shift
                     FORCE_REVISION=$(argument $option "$@"); shift
                     ARGS[${#ARGS[*]}]="--revision=$FORCE_REVISION" ;;
        --revision=*)
                     shift
                     FORCE_REVISION=$(echo "$option" | sed 's/--revision=//')
                     ARGS[${#ARGS[*]}]="--revision=$FORCE_REVISION" ;;
        -t | --target)
                     shift
                     force_target=$(argument $option "$@"); shift
                     ARGS[${#ARGS[*]}]="--target=$target" ;;
        --target=*)
                     shift
                     force_target=$(echo "$option" | sed 's/--target=//')
                     ARGS[${#ARGS[*]}]="--target=$target" ;;
        -s | --setup)
                     shift
                     DO_SETUP=1
                     ARGS[${#ARGS[*]}]="$option" ;;
        -u | --check-update)
                     shift
                     FORCE_CHECK_UPDATE=1 ;;
        *)
            printf "Unrecognized option \`%s'\n" "$option" 1>&2
            usage
            exit 1
            ;;
    esac

done
set +e

checkOptions
checkUpdate
checkConfig

target="${force_target:-$DEFAULT_TARGET}"
unset force_target

# don't use -e
set -u

theBoss=$(id -ur)
hours=$(get_hours)

#vars
export WORKDIR="$CLOVER_GROWER_PRO_DIR"
export TOOLCHAIN="${CLOVER_GROWER_PRO_DIR}/toolchain"
workSpace=$(df -m "${WORKDIR}" | tail -n1 | awk '{ print $4 }')
workSpaceNeeded="522"
workSpaceMin="104"
filesDIR="${WORKDIR}"/Files
UserDIR="${WORKDIR}"/User/etc
etcDIR="${WORKDIR}"/Files/etc
srcDIR="${WORKDIR}"/src
CloverDIR="${EDK2DIR}"/Clover
rEFItDIR="${CloverDIR}"/rEFIt_UEFI
buildDIR="${EDK2DIR}"/Build
cloverPKGDIR="${CloverDIR}"/CloverPackage
builtPKGDIR="${WORKDIR}"/builtPKG
lastModifiedFile="$filesDIR"/.last_modified
theBuiltVersion=""

# Some Flags
buildClover=0

[[ ! -d "${builtPKGDIR}" ]] && mkdir "${builtPKGDIR}"

style=release

if [[ ! -d "$EDK2DIR" && "$workSpace" -lt "$workSpaceNeeded" ]]; then
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
    [0-8]) rootSystem="unsupported" ;;
    9) rootSystem="Leopard" ;;
    10) rootSystem="Snow Leopard" ;;
    11) rootSystem="Lion" ;;
    12) rootSystem="Mountain Lion" ;;
    13) rootSystem="Mavericks" ;;
    [14-20]) rootSystem="Unknown" ;;
esac

function checkCloverLink() {
    if [[ ! -L "/usr/local/bin/cloverpro" || $(readlink "/usr/local/bin/cloverpro") != "$CLOVER_GROWER_PRO_SCRIPT" ]]; then
        echob "Running CloverGrowerPro.sh"
        printf "Will create link %s to %s\n" $(echob "/usr/local/bin/clover") $(echob "CloverGrowerPro.sh")
        echob "You can THEN 'run' CloverGrowerPro.sh by typing 'cloverpro' ;)"
        echob "Press Enter to continue"
        read
        if [ ! -d /usr/local/bin ]; then
            command="sudo mkdir -p /usr/local/bin"; echob "$command" ; eval $command
        fi
        command="sudo ln -sf $CLOVER_GROWER_PRO_SCRIPT /usr/local/bin/cloverpro && sudo chown $theBoss /usr/local/bin/cloverpro"
        echob "$command" ; eval $command
    fi
}

# Check XCode command line tools
function checkXCode() {
    if [[ ! -x /usr/bin/gcc ]]; then
        echob "ERROR:"
        echob "      Xcode Command Line Tools from Apple not found!"
        echob "      CloverGrowerPro.sh needs it";echo
        echob "      Going To Apple Developer Site"
        echob "      Download & Install XCode Command Line Tools then re-run CloverGrowerPro.sh"
        echo
        echob "      Press enter to open a browser to download XCode Command Line Tools"
        read
        open "https://developer.apple.com/downloads/"
        wait
        echob "Good $hours"
        tput bel
        exit 1
    fi
}

# Check Toolchain
function checkToolchain() {
    [[ -z "$TOOLCHAIN" ]] && echob "variable TOOLCHAIN not defined !" && exit 1
    if [[ ! -x "${TOOLCHAIN}/bin/x86_64-linux-gnu-gcc" ]]; then
        installToolchain
    fi
    if [[ ! -x "${TOOLCHAIN}/bin/msgmerge" ]]; then
        installGettext
    fi
}

# Check the build environment
function checkEnv() {
    checkCloverLink
    checkXCode
    # Check for svn
    [[ -z $(type -P svn) ]] && { echob "svn command not found. Exiting..." >&2 ; exit 1; }
    # Check the toolchain
    checkToolchain
}

function getLastModifiedSource() {
    find "$CloverDIR"                                                                             \
     -type d \( -path '*/.svn' -o -path '*/.git' -o -path '*/CloverPackage/CloverV2' \) -prune -o \
     -type f -print0 | xargs -0 stat -f "%m %N" |                                                 \
     egrep -v 'vers.txt|Version.h|.DS_Store|\.efi$' | sort -n | tail -1 |                         \
     cut -f1 -d' ' # ' fix xemacs fontification
}

# checkout/update svn
# $1=name $2=Local folder, $3=svn Remote url
# return code:
#     0: no update found
#     1: update found
function getSOURCEFILE() {
    local name="$1"
    local localdir="$2"
    local svnremoteurl="$3"
    local remoteRev=$(getSvnRevision "$svnremoteurl")
    if [[ ! -d "$localdir" ]]; then
        echob "    ERROR:"
        echo  "        Local $localdir folder not found.."
        echob "        Making local ${localdir} folder..."
        mkdir "$localdir"
    fi
    if [[ ! -d "${localdir}/.svn" && ! -d "${localdir}/.git" ]]; then
        echob "    Checking out Remote $name revision $remoteRev"
        checkout_repository "$localdir" "$svnremoteurl"
        return 1
    fi

    local localRev=$(getSvnRevision "$localdir")
    local checkoutRev=$remoteRev
    [[ "$localdir" == */Clover ]] && checkoutRev=${FORCE_REVISION:-$remoteRev}

    if [[ "${localRev}" == "${checkoutRev}" ]]; then
        echob "    Checked $name SVN, 'No updates were found...'"
        return 0
    fi
    printf "    %s, %s\n" "$(echob Checked $name SVN)" "$(sayColor info Updates found...)"
    printf "    %s %s %s %s ...\n" "$(sayColor info Auto Updating $name From)" "$(sayColor yellow $localRev)" "$(sayColor info 'to')" "$(sayColor green $checkoutRev)"
    tput bel
    if [[ "$localdir" == */Clover ]]; then
        update_repository "$localdir" "$checkoutRev"
    else
        update_repository "$localdir"
    fi
    checkit "    Svn up $name" "$svnremoteurl"
    return 1
}

# sets up svn sources
function getSOURCE() {
    if [ ! -d "${EDK2DIR}"/Build/CloverX64 ] && [ ! -d "${EDK2DIR}"/Build/CloverIA32 ]; then
        buildMode=">CleanAll< Build  "
    fi
    if [ -d "${EDK2DIR}"/Build/CloverX64 ] || [  -d "${EDK2DIR}"/Build/CloverIA32 ]; then
        buildMode=">>>Clean<<< Build "
    fi

    # Don't update edk2 if no Clover updates
    if [[ "${cloverUpdate}" == "Yes" ]]; then
        # Get edk2 source
        cd "${srcDIR}"
        getSOURCEFILE edk2 "$EDK2DIR" "https://edk2.svn.sourceforge.net/svnroot/edk2/trunk/edk2"
        local buildBaseTools=$?

        # Is edk2 need to be update
        if [[ "$buildBaseTools" -eq 1 ]]; then
            cd "${EDK2DIR}"

            # Remove old edk2 config files
            rm -f "${EDK2DIR}"/Conf/{BuildEnv.sh,build_rule.txt,target.txt,tools_def.txt}

            # Create new default edk2 files in edk2/Conf
            ./edksetup.sh >/dev/null

            make -C BaseTools clean &>/dev/null
            # Basetool will be build automatically when Clover will be build
        fi
        echo
    fi

    # Get Clover source
    cd "${EDK2DIR}"
    getSOURCEFILE Clover "$CloverDIR" "$CLOVERSVNURL"
    buildClover=$?
    echo
}

# compiles X64 or IA32 versions of Clover and rEFIt_UEFI
function cleanRUN(){
    local builder=gcc
    local archs=$(echo "$1" | awk '{print toupper($0)}')
    local ebuild_command=("./ebuild.sh" "-gcc${mygccVers}" "-$style")

    # Clear the package dir before compilation
    [[ "$versionToBuild" -ge 1166 ]] && ./ebuild.sh cleanpkg &>/dev/null

    echo
    echo "Starting $buildMode Process: $(date -j +%T)"
    echo "Building Clover$archs, gcc${mygccVers} $style"

    # Mount the RamDisk
    mountRamDisk "$EDK2DIR/Build"

    # We can activate VBios Patch in CloverEFI since revision 1162 of Clover
    [[ "$VBIOS_PATCH_IN_CLOVEREFI" -ne 0 && "$versionToBuild" -ge 1162 ]] && \
     ebuild_command+=("--vbios-patch-cloverefi")

    # We can activate Only SATA0 Patch in CloverEFI since revision 1853 of Clover
    [[ "$ONLY_SATA0_PATCH" -ne 0 && "$versionToBuild" -ge 1853 ]] && \
     ebuild_command+=("--only-sata0")

    [[ -n "${EBUILD_OPTIONAL_ARGS:-}" ]] && ebuild_command+=($EBUILD_OPTIONAL_ARGS)

    cd "${CloverDIR}"
    local IFS=" /" # archs can be separate by space or /
    local archs=$(lc $archs)
    unset IFS
    for arch in $archs; do
        echob "running ${ebuild_command[@]} -$arch"
        ${ebuild_command[@]} -$arch -$style
        checkit "Clover$arch $style"
    done

    echo
}

function installToolchain() {
    cd "${WORKDIR}"/Files
    echo  "Download and install toolchain to compile Clover"
    printf "toolchain will be install in %s\n" $(echob ${TOOLCHAIN})
    echo  "Press any key to start the process..."
    read

    # Check that some directories exists
    if [ ! -d "${srcDIR}" ]; then
        echob "Make src Folder.."
        mkdir "${srcDIR}"
    fi

    # Get the latest version of buildgcc.sh from clover
    echob "Checking out last version of buildgcc.sh from clover..."
    svn export --force "$CLOVERSVNURL"/buildgcc.sh "$srcDIR"/buildgcc.sh >/dev/null

    echob "Starting CloverGrower Compile Tools process..."
    date
    # build only x64 because it can compile ia32 too
    PREFIX="$TOOLCHAIN" DIR_MAIN="$srcDIR" DIR_TOOLS="$srcDIR/CloverTools" \
     "$srcDIR"/buildgcc.sh -x64 -all
    tput bel
    cd ..
}

function installGettext() {
    cd "${WORKDIR}"/Files

    # Get the latest version of buildgettext.sh from clover
    echob "Checking out last version of buildgettext.sh from clover..."
    svn export --force "$CLOVERSVNURL"/buildgettext.sh "$srcDIR"/buildgettext.sh >/dev/null

    echob "Starting CloverGrower Compile Tools process..."
    date
    # build gettext
    PREFIX="$TOOLCHAIN" DIR_MAIN="$srcDIR" DIR_TOOLS="$srcDIR/CloverTools" \
     "$srcDIR"/buildgettext.sh
    tput bel
    cd ..
}

autoBuild(){
    local theARCHS="$1"
    if [ "$built" == "No" ]; then
        local buildMess="*    Auto-Build Full Clover rEFIt_UEFI    *"
        local cleanMode=""
        buildMode=">>>>New<<<< Build "
        local edk2LocalRev=$(getSvnRevision "$EDK2DIR")
        local buildVersioncolor='green'
        [[ "$CLOVER_LOCAL_REV" -ne "$CLOVER_REMOTE_REV" ]] && buildVersioncolor='yellow'
        echob "*******************************************"
        echob "$buildMess"
        echob "$(printf '*    Revisions:   %s: %-29s%s\n' $(sayColor info 'edk2') $(sayColor green $edk2LocalRev) $(echob '*'))"
        echob "$(printf '*               %s: %-29s%s\n' $(sayColor info 'Clover') $(sayColor $buildVersioncolor $versionToBuild) $(echob '*'))"
        local IFS=
        local flags="$mygccVers $theARCHS $style"
        echob "$(printf '*    Using Flags: gcc%-21s*\n' $flags)"
        echob "*******************************************"
        tput bel
        sleep 3
        local startEpoch=$(date -u "+%s")
        # Start build process
        cleanRUN "$theARCHS"
        built="Yes"
        local stopEpoch=$(date -u "+%s")

        local buildTime=$(expr $stopEpoch - $startEpoch)
        local timeToBuild
        if [[ $buildTime -gt 59 ]]; then
            timeToBuild=$(printf "%dm%ds\n" $((buildTime/60%60)) $((buildTime%60)))
        else
            timeToBuild=$(printf "%ds\n" $((buildTime)))
        fi
        printf "%s %s %s\n" "$(sayColor info 'Clover Grower Complete Build process took')" \
         "$(sayColor green $timeToBuild)" "$(sayColor info 'to complete...')"
        echo
    fi
}

# makes pkg if Built OR builds THEN makes pkg
function makePKG(){
    echo
    echob "********************************************"
    echob "*              Good $hours              *"
    echob "*     Welcome To CloverGrowerPro v$CloverGrowerVersion      *"
    echob "*           This script by JrCs            *"
    echob "*        Original script by STLVNUB        *"
    echob "* Clover Credits: Slice, dmazar and others *"
    echob "********************************************"
    echo
    echob "running '$(basename $CMD)' on '$rootSystem'"
    echo
    echob "Work Folder: $WORKDIR"
    echob "Available  : ${workSpaceAvail} MB"
    echo

    cloverUpdate="No"
    versionToBuild=

    if [[ -d "${CloverDIR}" ]]; then
        CLOVER_LOCAL_REV=$(getSvnRevision "${CloverDIR}")
        if [[ -d "${CloverDIR}/.git" ]]; then
            # Check if we are on the master branch
            local branch=$(cd "$CloverDIR" && LC_ALL=C git rev-parse --abbrev-ref HEAD)
            if [[ "$branch" != master ]]; then
                echob "You're not on the 'master' branch. Can't update the repository !"
                versionToBuild=$CLOVER_LOCAL_REV
            fi
        fi
        if [[ -z "$versionToBuild" ]]; then
            if [[ -n "$FORCE_REVISION" ]]; then
                versionToBuild=$FORCE_REVISION
            else
                CLOVER_REMOTE_REV=$(getSvnRevision "$CLOVERSVNURL")
                versionToBuild=$CLOVER_REMOTE_REV
            fi

            if [[ -n "$FORCE_REVISION" ]]; then
                versionToBuild=$FORCE_REVISION
                if [[ "${CLOVER_LOCAL_REV}" -ne "${versionToBuild}" ]]; then
                    printf "%s %s\n" "$(sayColor info 'Forcing Clover revision')" "$(sayColor yellow $versionToBuild)"
                    cloverUpdate="Yes"
                fi
            else
                if [[ "${CLOVER_LOCAL_REV}" -ne "${versionToBuild}" ]]; then
                    sayColor info "Clover Update Detected !"
                    echob  "******** Clover Package STATS **********"
                    echob "$(printf '*       local  revision at %-23s%s\n' $(sayColor yellow $CLOVER_LOCAL_REV)  $(echob '*'))"
                    echob "$(printf '*       remote revision at %-23s%s\n' $(sayColor green  $CLOVER_REMOTE_REV) $(echob '*'))"
                    echob "$(printf '*       Package Built   =  %-23s%s\n' $(sayColor info   $built) $(echob '*'))"
                    echob "****************************************"
                    cloverUpdate="Yes"
                else
                    printf "%s %s %s\n" "$(sayColor info 'No Clover Update found.')" \
                     "$(echob 'Current revision:')" "$(sayColor green ${CLOVER_LOCAL_REV})"
                fi
            fi
        fi
    else
        CLOVER_LOCAL_REV=0
        cloverUpdate="Yes"
    fi

    # if [ -f "${builtPKGDIR}/${versionToBuild}/Clover_v2_rL${versionToBuild}".pkg ] && [ -d "${CloverDIR}" ] && [ "$target" != "X64" ]; then # don't build IF pkg already here
    #     if [ -f "${builtPKGDIR}/${versionToBuild}"/CloverCD/EFI/BOOT/BOOTX64.efi ]; then
    #         theBuiltVersion=$(strings "${builtPKGDIR}/${versionToBuild}/CloverCD/EFI/BOOT/BOOTX64.efi" | sed -n 's/^Clover revision: *//p')
    #         if [ "${theBuiltVersion}" == "${versionToBuild}" ]; then
    #             built="Yes"
    #         else
    #             built="No "
    #             cloverUpdate="Yes"
    #         fi
    #         echob  "******** Clover Package STATS **********"
    #         echob "$(printf '*       local  revision at %-12s*\n' $CLOVER_LOCAL_REV)"
    #         echob "$(printf '*       remote revision at %-12s*\n' $CLOVER_REMOTE_REV)"
    #         echob "$(printf '*       Package Built   =  %-12s*\n' $built)"
    #         echob "****************************************"
    #         if [ "$built" == "Yes" ]; then
    #             echob "Clover_v2_rL${versionToBuild}.pkg ALREADY Made!!"
    #             return
    #         fi
    #     fi
    # fi

    echo
    if [[ "${cloverUpdate}" == "Yes" ]]; then
        echob "Getting SVN Source, Hang ten…"
        getSOURCE
        CLOVER_LOCAL_REV=$(getSvnRevision "${CloverDIR}") # Update
        versionToBuild=$CLOVER_LOCAL_REV
    fi

    if [[ "$cloverUpdate" == "Yes" || ! -f "${EDK2DIR}/Conf/tools_def.txt" || \
          $(grep -c 'GCC47_' "${EDK2DIR}/Conf/tools_def.txt") -eq 0 ]]; then
        # get configuration files from Clover
        cp "${CloverDIR}/Patches_for_EDK2/tools_def.txt"  "${EDK2DIR}/Conf/"
        cp "${CloverDIR}/Patches_for_EDK2/build_rule.txt" "${EDK2DIR}/Conf/"

        # Patch edk2/Conf/tools_def.txt for GCC
        sed -i'.orig' -e 's!^\(DEFINE GCC47_[IA32X64]*_PREFIX *= *\).*!\1'${TOOLCHAIN}'/bin/x86_64-linux-gnu-!' \
         "${EDK2DIR}/Conf/tools_def.txt"
        checkit "Patching edk2/Conf/tools_def.txt"

        rm -Rf "${buildDIR}"/*
        checkit "Clover updated, so rm the build folder"

        cp -R "${filesDIR}/HFSPlus/" "${CloverDIR}/HFSPlus/"
        checkit "Copy Files/HFSPlus Clover/HFSPlus"
    fi

    # Check last modified file
    local last_timestamp=$(getLastModifiedSource)
    local last_save_timestamp=$(cat "$lastModifiedFile" 2>/dev/null || echo '0')

    # If not already built force Clover build
    if [[ "$built" == "No" && "$last_timestamp" -ne "$last_save_timestamp" ]]; then
        printf "%s %s\n" "$(echob 'No build already done.')" \
         "$(sayColor info 'Forcing Clover build...')"
        echo
        buildClover=1
    fi

    if [[ "$buildClover" -eq 1 ]]; then
        echob "Ready to build Clover $versionToBuild, Using Gcc $gccVersToUse"
        autoBuild "$1"
        echo "$last_timestamp" > "$lastModifiedFile"
    fi

    if [ "$MAKE_PACKAGE" -eq 1 ]; then
        local package_name="Clover_v2_r${versionToBuild}.pkg"
        if [[ ! -f "${builtPKGDIR}/$package_name" ]]; then # make pkg if not there
            echob "Type 'm' To make ${package_name}..."
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
            echob "cd to ${CloverDIR}/CloverPackage and run ./makepkg."
            export GETTEXT_PREFIX="$TOOLCHAIN"
            ./makepkg "No" || exit $?
            [[ ! -d "${builtPKGDIR}" ]] && mkdir "${builtPKGDIR}"
            cp -p "${CloverDIR}"/CloverPackage/sym/*.pkg "${builtPKGDIR}"/
            rm -rf "${CloverDIR}"/CloverPackage/sym
            echob "open builtPKG"
            open "${builtPKGDIR}"/
            tput bel
            ;;
            *)
            esac
        else
            echob "$package_name ALREADY Made !"
        fi
    else
        echob "Skipping pkg creation,"
        open "${cloverPKGDIR}"/CloverV2/
    fi
}

# Check CloverGrower build environment
checkEnv

export mygccVers="${gccVersToUse:0:1}${gccVersToUse:2:1}" # needed for BUILD_TOOLS e.g GCC47
buildMess="*    Auto-Build Full Clover rEFIt_UEFI    *"
cleanMode=""
built="No"

makePKG "$target" # do complete build

echob "Good $hours."

# Local Variables:      #
# mode: ksh             #
# tab-width: 4          #
# indent-tabs-mode: nil #
# End:                  #
#
# vi: set expandtab ts=4 sw=4 sts=4: #
