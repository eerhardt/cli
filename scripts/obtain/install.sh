# Copyright (c) .NET Foundation and contributors. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.
#

# Note: This script should be compatible with the dash shell used in Ubuntu. So avoid bashisms! See https://wiki.ubuntu.com/DashAsBinSh for more info

# This is a herestring Everything from the line AFTER the "read" until the line containing ONLY "EOF" is part of the string
# The quotes around "EOF" ensure that $ is not interpreted as a variable expansion. The indentation of the herestring must be
# kept exactly consistent
LINK_SCRIPT_CONTENT=$(cat <<-"EOF"
#!/usr/bin/env bash

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

if [ -z "$DOTNET_TOOLS" ]; then
    # We should be in $PREFIX/bin, so just get the directory above us.
    PREFIX="$( cd -P "$DIR/.." && pwd)"

    # The tools are in $PREFIX/share/dotnet/cli by default
    DOTNET_TOOLS_DEFAULT=$PREFIX/share/dotnet/cli

    # Check the default location
    if [ -d "$DOTNET_TOOLS_DEFAULT" ]; then
        export DOTNET_TOOLS=$DOTNET_TOOLS_DEFAULT
    else
        echo "error: the .NET tools installation appears to be corrupt!" 1>&2
        echo "error: specifically, the tools could not be located in the $DOTNET_TOOLS_DEFAULT directory" 1>&2
        exit 1
    fi
fi

MY_NAME=$(basename ${BASH_SOURCE[0]})
MY_TARGET=$DOTNET_TOOLS/bin/$MY_NAME

if [ ! -e "$MY_TARGET" ]; then
    echo "error: the tool $MY_TARGET cannot be found" 1>&2
    exit 1
fi

if [ ! -x "$MY_TARGET" ]; then
    echo "error: the tool $MY_TARGET is not executable" 1>&2
    exit 1
fi

exec "$MY_TARGET" "$@"
EOF
)

#setup some colors to use. These need to work in fairly limited shells, like the Ubuntu Docker container where there are only 8 colors.
#See if stdout is a terminal
if [ -t 1 ]; then
    # see if it supports colors
    ncolors=$(tput colors)
    if [ -n "$ncolors" ] && [ $ncolors -ge 8 ]; then
        bold="$(tput bold)"
        normal="$(tput sgr0)"
        black="$(tput setaf 0)"
        red="$(tput setaf 1)"
        green="$(tput setaf 2)"
        yellow="$(tput setaf 3)"
        blue="$(tput setaf 4)"
        magenta="$(tput setaf 5)"
        cyan="$(tput setaf 6)"
        white="$(tput setaf 7)"
    fi
fi

#Standardise OS name to what is put into filenames of the tarballs.
current_os()
{
    local uname=$(uname)
    if [ "$uname" = "Darwin" ]; then
        echo "osx"
    else
        # Detect Distro
        if [ "$(cat /etc/*-release | grep -cim1 ubuntu)" -eq 1 ]; then
            echo "ubuntu"
        elif [ "$(cat /etc/*-release | grep -cim1 centos)" -eq 1 ]; then
            echo "centos"
        elif [ "$(cat /etc/*-release | grep -cim1 rhel)" -eq 1 ]; then
            echo "rhel.7"
        fi
    fi
}

machine_has() {
    type "$1" > /dev/null 2>&1
    return $?
}

#Not 100% sure at the moment that these checks are enough. We might need to take version into account or do something
#more complicated. This seemed like a good beginning though as it should catch the default "clean" machine case and give
#people an appropriate hint.
check_pre_reqs() {
    local os=$(current_os)
    local _failing=false;

    if [ "$DOTNET_INSTALL_SKIP_PREREQS" = "1" ]; then
        return 0
    fi

    if [ "$(uname)" = "Linux" ]; then
        [ -z "$(ldconfig -p | grep libunwind)" ] && say_err "Unable to locate libunwind. Install libunwind to continue" && _failing=true
        [ -z "$(ldconfig -p | grep libssl)" ] && say_err "Unable to locate libssl. Install libssl to continue" && _failing=true
        [ -z "$(ldconfig -p | grep libcurl)" ] && say_err "Unable to locate libcurl. Install libcurl to continue" && _failing=true
        [ -z "$(ldconfig -p | grep libicu)" ] && say_err "Unable to locate libicu. Install libicu to continue" && _failing=true
        [ -z "$(ldconfig -p | grep gettext)" ] && say_err "Unable to locate gettext. Install gettext to continue" && _failing=true
    fi

    if [ "$_failing" = true ]; then
       return 1
    fi
}

say_err() {
    printf "%b\n" "${red}dotnet_install: Error: $1${normal}" >&2
}

say() {
    printf "%b\n" "dotnet_install: $1"
}

make_link() {
    local target_name=$1
    local dest=$PREFIX/bin/$target_name
    say "Linking $dest -> $PREFIX/share/dotnet/cli/$target_name"
    if [ -e $dest ]; then
        rm $dest
    fi

    [ -d "$PREFIX/bin" ] || mkdir -p $PREFIX/bin

    echo "$LINK_SCRIPT_CONTENT" > $dest

    # Make mode: rwxr-xr-x
    chmod 755 $dest
}

install_dotnet()
{
    if ! machine_has "curl"; then
        printf "%b\n" "${red}curl is required to download dotnet. Install curl to proceed. ${normal}" >&2
        return 1
    fi

    say "Preparing to install .NET Tools from '$CHANNEL' channel to '$PREFIX'"

    if [ -e "$PREFIX/share/dotnet/cli/dotnet" ] && [ ! -w "$PREFIX/share/dotnet/cli/dotnet" ]; then
        say_err "dotnet cli is already installed and not writeable. Use 'curl -sSL <url> | sudo sh' to force install."
        say_err "If you have previously installed the cli using a package manager or installer then that is why it is write protected, and you need to run sudo to install the new version."
        say_err "Alternatively, removing the '$PREFIX/share/dotnet' directory completely before running the script will also resolve the issue."
        return 1
    fi

    if ! check_pre_reqs; then
        say_err "Ending install due to missing pre-reqs"
        return 1;
    fi

    if [ "$VERSION" == "Latest" ]; then
      local fileVersion=latest
    else
      local fileVersion=$VERSION
    fi

    local os=$(current_os)
    local installLocation="$PREFIX/share/dotnet"
    local dotnet_url="https://dotnetcli.blob.core.windows.net/dotnet/$CHANNEL/Binaries/$VERSION"
    local dotnet_filename="dotnet-$os-x64.$fileVersion.tar.gz"

    if [ "$RELINK" = "0" ]; then
        if [ "$FORCE" = "0" ]; then
            local localVersion=$(tail -n 1 "$installLocation/cli/.version" 2>/dev/null)
            if [ "$VERSION" == "Latest" ]; then
                # Check if we need to bother
                local remoteData="$(curl -s https://dotnetcli.blob.core.windows.net/dotnet/$CHANNEL/dnvm/latest.$os.version)"
                [ $? != 0 ] && say_err "Unable to determine latest version." && return 1

                local remoteVersion=$(IFS="\n" && echo $remoteData | tail -n 1)
                local remoteHash=$(IFS="\n" && echo $remoteData | head -n 1)

                [ -z $localVersion ] && localVersion='<none>'
                local localHash=$(head -n 1 "$installLocation/cli/.version" 2>/dev/null)

                say "Latest Version: $remoteVersion"
                say "Local Version: $localVersion"

                [ "$remoteHash" = "$localHash" ] && say "${green}You already have the latest version.${normal}" && return 0
            else
                [ "$fileVersion" = "$localVersion" ] && say "${green}You already have the version $fileVersion.${normal}" && return 0
            fi
        fi

        #This should noop if the directory already exists.
        mkdir -p $installLocation

        say "Downloading $dotnet_filename from $dotnet_url"

        #Download file and check status code, error and return if we cannot download a cli tar.
        local httpResult=$(curl -L -D - "$dotnet_url/$dotnet_filename" -o "$installLocation/$dotnet_filename" -# | grep "^HTTP/1.1" | head -n 1 | sed "s/HTTP.1.1 \([0-9]*\).*/\1/")
        [ $httpResult -ne "302" ] && [ $httpResult -ne "200" ] && echo "${Red}HTTP Error $httpResult fetching the dotnet cli from $dotnet_url ${RCol}" && return 1

        say "Extracting tarball"
        #Any of these could fail for various reasons so we will check each one and end the script there if it fails.
        rm -rf "$installLocation/cli_new"
        mkdir "$installLocation/cli_new"
        [ $? != 0 ] && say_err "failed to clean and create temporary cli directory to extract into" && return 1

        tar -xzf "$installLocation/$dotnet_filename" -C "$installLocation/cli_new"
        [ $? != 0 ] && say_err "failed to extract tar" && return 1

        say "Moving new CLI into install location and symlinking"

        rm -rf "$installLocation/cli"
        [ $? != 0 ] && say_err "Failed to clean current dotnet install" && return 1

        mv "$installLocation/cli_new" "$installLocation/cli"
    elif [ ! -e "$installLocation/cli" ]; then
        say_err "${red}cannot relink dotnet, it is not installed in $PREFIX!"
        return 1
    fi

    for f in $(find "$installLocation/cli" -regex ".*/dotnet[a-z\-]*$")
    do
        local baseFile=$(basename $f)
        make_link $baseFile
    done

    if [ -e "$installLocation/$dotnet_filename" ]; then
        say "Cleaning $dotnet_filename"
        if ! rm "$installLocation/$dotnet_filename"; then
            say_err "Failed to delete tar after extracting."
            return 1
        fi
    fi
}

FORCE=0
RELINK=0
while [ $# -ne 0 ]
do
    name=$1
    case $name in
        -f|--force)
            FORCE=1
            ;;
        -r|--relink)
            RELINK=1
            ;;
        -c|--channel)
            shift
            CHANNEL=$1
            ;;
        -v|--version)
            shift
            VERSION=$1
            ;;
        -d|--destination)
            shift
            DOTNET_INSTALL_DIR=$1
            ;;
        -?|-h|--help)
            echo ".NET Tools Installer"
            echo ""
            echo "Usage:"
            echo "  $0 [-f|--force] [-r|--relink] [-c|--channel <CHANNEL>] [-d|--destination <DESTINATION>]"
            echo "  $0 -h|-?|--help"
            echo ""
            echo "Options:"
            echo "  -f,--force                  Force reinstallation even if you have the most recent version installed"
            echo "  -r,--relink                 Don't re-download, just recreate the links in $PREFIX/bin"
            echo "  -c,--channel <CHANNEL>      Download from the CHANNEL specified (default: dev)"
            echo "  -d,--destination <PATH>     Install under the specified root (see Install Location below)"
            echo "  -?,-h,--help                Show this help message"
            echo ""
            echo "Install Location:"
            echo "  By default, this script installs the .NET Tools to /usr/local. However, if the PREFIX environment variable"
            echo "  is specified, that will be used as the installation root. If the DOTNET_INSTALL_DIR environment variable"
            echo "  is specified, it will be used as the installation root (overriding PREFIX). Finally, if the '--destination'"
            echo "  option is specified, it will override all environment variables and be used as the installation location"
            echo ""
            echo "  After installation, the .NET Tools will be installed to the 'share/dotnet/cli' subdirectory of the "
            echo "  installation location (i.e. /usr/local/share/dotnet/cli). Binaries will be symlinked to the 'bin'"
            echo "  subdirectory of the installation location (i.e. /usr/local/bin/dotnet)"
            exit 0
            ;;
    esac

    shift
done

#set default prefix (PREFIX is a fairly standard env-var, but we also want to allow the use the specific "DOTNET_INSTALL_DIR" one)
if [ ! -z "$DOTNET_INSTALL_DIR" ]; then
    PREFIX=$DOTNET_INSTALL_DIR
elif [ -z "$PREFIX" ]; then
    PREFIX=/usr/local
fi

[ -z "$CHANNEL" ] && CHANNEL="dev"
[ -z "$VERSION" ] && VERSION="Latest"

install_dotnet
