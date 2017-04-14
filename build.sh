#!/bin/bash

###########################################
# Some initializations.                   #
###########################################
pkg='consul'
pkg_version='latest'
pkg_release='1'
isDebug=false;
current_dir=$(dirname ${0})
build_root=$(realpath $current_dir/rpmbuild)
download_url_root='https://releases.hashicorp.com/consul'
# available_versions will always be sorted because hashicorp publishes new versions on top.
# This implies available_versions[0] will always be the latest version.
available_versions=( $(curl --silent $download_url_root/ | grep -oP '(/\d\.\d\.\d/)?' | tr -d '/') )

###########################################
# Functions                               #
###########################################
function print_debug_line()
{
    if [ "$isDebug" = true ]; then
        printf "DEBUG: $1\n"
    fi
}

function usage()
{
    echo "Script to setup RPM build environment and package $pkg.";
    echo "The script should _NOT_ be run as root. It will ask for";
    echo "password via sudo if something needs it.";
    echo "";
    echo "Usage: ${0} -v version_to_build";
    echo -e "-v\tVersion of $pkg to build. This version should be";
    echo -e "  \tavailable upstream. Default: latest";
    echo -e "\n-r\tRPM release version. Use this field to specify if this is a"
    echo -e "  \tcustom version for your needs. For example, if you are"
    echo -e "  \tbuilding this package for your company, you can set this"
    echo -e "  \tto company name. Default: 1";
    echo -e "\n-b\tPath that will contain RPM build tree. Default is current dir.";
    echo -e "\n-l\tList available versions.";
    echo -e "\n-h\tShow this help message and exit.";
    echo -e "\n-d\tPrint debugging statements.";
    echo -e "\nExample: ${0} -v 0.8.0";
}

function parse_command()
{
    if [ -z "$1" ]; then
        usage;
        exit -4;
    fi

    SHORT=v:r:b:lhd
    LONG=version:,release:,build_root:,list,help,debug
    PARSED=$(getopt --options $SHORT --longoptions $LONG --name "$0" -- "$@")
    if [[ $? -ne 0 ]]; then
        # e.g. $? == 1
        #  then getopt has complained about wrong arguments to stdout
        exit -4
    fi

    # use eval with "$PARSED" to properly handle the quoting
    eval set -- "$PARSED"

    # Parse options until we see --
    while true; do
        case "$1" in
            -d|--debug)
                isDebug=true;
                print_debug_line "ON";
                shift
                ;;
            -v|--version)
                if [ "$2" == 'latest' ]; then
                    pkg_version="${available_versions[0]}"
                else
                    pkg_version="$2"
                fi
                shift 2
                ;;
            -r|--release)
                pkg_release="$2"
                shift 2
                ;;
            -b|--build_root)
                build_root="$2"
                shift 2
                ;;
            -l|--list)
                echo "Available versions:"
                print_available_versions
                exit 0
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --)
                shift
                break
                ;;
            *)
                echo -e "\nProgrammer has the dumbz."
                exit 3
                ;;
        esac
    done
}

function perform_safety_checks()
{
    # Ensure we are not running as root.
    if [ $EUID -eq 0 ]; then
        echo 'Please do not run this script as root.'
        echo 'See https://fedoraproject.org/wiki/How_to_create_an_RPM_package#Preparing_your_system for details.'
        exit 1
    fi

    # Ensure we are on Red Hat or its derivatives.
    if [ -f "/proc/version" ]; then
        proc_version=`cat /proc/version`
    else
        proc_version=`uname -a`
    fi

    print_debug_line "${FUNCNAME[0]} : proc version = $proc_version"

    if [[ $proc_version != *"Red Hat"* ]]; then
        echo "ERROR: Your OS is not supported by this script! :("
        echo "At the moment only Red Hat and its derivatives are supported."
        exit 4
    fi

    # Check if sha256sum is installed
    which sha256sum &>/dev/null
    if [ "$?" -gt 0 ]; then
        echo "sha256sum is not installed. It is needed to verify if downloads are successful."
        echo "Please install coreutils and rerun the script."
        exit 4
    fi
}

function validate_inputs()
{
    if [[ "$pkg_version" =~ ^0\.[0-9]+\.[0-9]+$ ]]; then
        echo "Using version: $pkg_version"
    else
        echo "Invalid version format. Versions available for packaging:"
        print_available_versions
        exit 2
    fi
}

function print_available_versions()
{
    # Reference: http://www.tldp.org/LDP/abs/html/arrays.html
    echo ${available_versions[@]/%/,}
}

function setup_rpm_tree()
{
    # clean the working directories. Do not remove SOURCES dir if it is already there.
    print_debug_line "${FUNCNAME[0]} : Deleting and recreating RPM build tree folders."
    for dir in BUILD RPMS SRPMS BUILDROOT; do
        rm -rf $build_root/$dir || true
        mkdir -p $build_root/$dir
    done

    print_debug_line "${FUNCNAME[0]} : Copying SPECS and SOURCES to $build_root."
    # Copy spec dir to build dir
    cp -R $current_dir/SPECS $build_root/
    # Copy sources to the sources dir.
    cp -Rf $current_dir/SOURCES $build_root/
}

function download_and_verify()
{
    core_archive_name="${pkg}_${pkg_version}_linux_amd64.zip"
    ui_archive_name="${pkg}_${pkg_version}_web_ui.zip"
    checksum="${pkg}_${pkg_version}_SHA256SUMS"
    sources_dir="$build_root/SOURCES"

    for file in $core_archive_name $ui_archive_name $checksum; do
        dl_url="$download_url_root/$pkg_version/$file"
        print_debug_line "${FUNCNAME[0]} : Downloading $dl_url to $sources_dir/$file"
        wget --max-redirect=0 -O $sources_dir/$file $dl_url &>/dev/null

        # Print a message if download leads to file of size 0.
        if [ ! -s $sources_dir/$file ]; then
            echo
            echo "Failed to download $dl_url."
            echo "Please verify if the link is accurate and network connectivity"
            echo "is available."
        fi
    done

    # CentOS 7 is shipping with old sha256sum that does not contain --ignore-missing.
    # Calculate the checksum and then match it against the one in downloaded file.
    for file in $core_archive_name $ui_archive_name; do
        local_checksum=$(sha256sum $sources_dir/$file | cut -f 1 -d ' ')
        published_checksum=$(grep $file $sources_dir/$checksum | cut -f 1 -d ' ')
        print_debug_line "${FUNCNAME[0]} : $file local checksum = $local_checksum"
        print_debug_line "${FUNCNAME[0]} : $file published checksum = $published_checksum"
        if [ "$local_checksum" != "$published_checksum" ]; then
            echo "Checksum did not match for $file."
            exit 4
        fi
    done
}

##################
# Pass all args of the script to the function.
parse_command "$@"
perform_safety_checks
validate_inputs
setup_rpm_tree
download_and_verify
# Now that the sources are downloaded and verified we can actually make the RPM.
# _topdir and _tmppath are magic rpm variables that can be defined in ~/.rpmmacros
# For ease of reliable builds they are defined here on the command line.
rpmbuild -ba --define="_topdir $build_root" --define="buildroot $build_root/BUILDROOT" --define="pkg_version $pkg_version" --define="rpm_release $pkg_release" $build_root/SPECS/$pkg.spec
