#!/bin/bash

###########################################
# Some initializations.                   #
###########################################
pkg='consul'
pkg_version=''
pkg_release=''
isDebug=false;
current_dir=$(dirname ${0})
build_root=(realpath $current_dir/rpmbuild)
download_url_root='https://releases.hashicorp.com/consul/'

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
    echo -e "  \tavailable upstream. See available versions below.";
    echo -e "\n-r\tRPM release version. Use this field to specify if this is a"
    echo -e "  \tcustom version for your needs. For example, if you are"
    echo -e "  \tbuilding this package for your company, you can set this"
    echo -e "  \tto company name.";
    echo -e "-b\tPath that will contain RPM build tree. Default is current dir.";
    echo -e "\n-h\tShow this help message and exit.";
    echo -e "\n-d\tPrint debugging statements.";
    echo -e "\nExample: ${0} -v 0.8.0";
    echo -e "\nAvailable versions:";
    print_available_versions
}

function parse_command()
{
    if [ -z "$1" ]; then
        usage;
        exit -4;
    fi

    SHORT=v:r:b:hd
    LONG=version:,release:,build_root:,help,debug
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
                pkg_version="$2"
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
            -h|--help)
                usage
                exit 0
                ;;
            --)
                shift
                break
                ;;
            *)
                usage
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
    curl --silent $download_url_root | grep -oP '(/\d\.\d\.\d/)?' | tr -d '/'
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
    remote_dir="${pkg}_${pkg_version}"
    core_archive_name="${pkg}_${pkg_version}_linux_amd64.zip"
    ui_archive_name="${pkg}_${pkg_version}_web_ui.zip"
    checksum="${pkg}_${pkg_version}_SHA256SUMS"
    sources_dir="$build_root/SOURCES"

    for file in $core_archive_name $ui_archive_name $checksum; do
        dl_url="$download_url_root/$remote_dir/$file"
        print_debug_line "${FUNCNAME[0]} : Downloading $dl_url to $sources_dir/$file"
        wget --max-redirect=0 -O $sources_dir/$file $dl_url &>/dev/null
    done

    if [ "$isDebug" = true ]; then
        sha256sum --ignore-missing --check $sources_dir/$checksum
    else
        sha256sum --ignore-missing --quiet --check $sources_dir/$checksum
    fi

    if [ "$?" -gt 0 ]; then
        echo -e "\nSeems like download has failed. :("
        echo    "Please verify connectivity and rerun the script."
        exit 5
    fi

}

##################
perform_safety_checks
# Pass all args of the script to the function.
parse_command "$@"
validate_inputs
setup_rpm_tree
download_and_verify
# Now that the sources are downloaded and verified we can actually make the RPM.
# _topdir and _tmppath are magic rpm variables that can be defined in ~/.rpmmacros
# For ease of reliable builds they are defined here on the command line.
rpmbuild -ba --define="_topdir $build_root" --define="buildroot $build_root/BUILDROOT" --define="pkg_version $pkg_version" --define="rpm_release $pkg_release" $build_root/SPECS/$pkg.spec
