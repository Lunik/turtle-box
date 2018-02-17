#!/usr/bin/env bash

# Sources parameters
MIRROR="http://dl-cdn.alpinelinux.org/alpine";
ARCH="x86_64";
VERSION="v3.7";
APK_TOOL="apk-tools-static-2.8.2-r0.apk";

# Comment this out to disable debugging
DEBUG="y"

#set -o xtrace

#------------------------------------------------------------------------------#
#                                                                              #
#                               Utility functions                              #
#                                                                              #
#------------------------------------------------------------------------------#

# Print usage for this tool
function print_usage {
    cat <<-EOF
		Usage : $0 <ACTION> <WORKING_DIR>

		Install Alpine on the specified directory.

		Actions :
		    build: Install Alpine on specified directory
		    shell: Open up a shell within Alpine
		    destroy: Destroy Alpine

		Options :
		   WORKING_DIR: Directory to use to setup Alpine
	EOF
}

# Print an error message
function error {
	echo "Error: ${@}" >&2;
}

# Print an informative message
function info {
	echo "==> ${@}";
}

# Print additional debugging output
function debug {
	[ -z "${DEBUG}" ] && echo "${@}";
}

# Prompt user if he wants to continue
function prompt_continue {
	echo -n "Continue ? (y/n)";
	while [[ "${answer}" != 'y' ]]; do
		read -n 1 -s answer;
		[[ "${answer}" == 'n' ]] && exit 0;
	done;
	echo "";
}



#------------------------------------------------------------------------------#
#                                                                              #
#                            Build Step functions                              #
#                                                                              #
#------------------------------------------------------------------------------#

# Performs required checks for running build
function build_checks {
	local answer="";

	# Check if device is set
    #if [ -z "$DEVICE" ]; then
    #    print_usage;
    #    exit 1;
    #fi

	# Check is shell really is bash
	if [ ! -v BASH ]; then
		echo "Warning : You should use bash to run this script.";
		prompt_continue;
    fi

	# Check user is root
	if [ "$UID" -ne 0 ]; then
		error "You are not root. Please use su to get root permissions.";
		exit 1;
	fi

	# Check if workdir exists
	if [ -d "${WORKDIR}" ] && [ -z "$(ls -A "${WORKDIR}")" ]; then
		echo "Warning : The working directory exist and is not empty.";
		echo "          Files may be deleted in this process";
		prompt_continue;
	fi;
}

# Create workdir and get utility files
function prepare_workdir {
	info "Creating working directory file structure";
	mkdir -p "${SRCDIR}" "${ROOTDIR}";

	pushd "${SRCDIR}";
		info "Downloading required files";
		wget "${MIRROR}/${VERSION}/main/${ARCH}/${APK_TOOL}";

		info "Extracting downloaded files";
		tar -xzf "${SRCDIR}/${APK_TOOL}";
	popd;
}

# Install Alpine onto the root directory
function install_alpine {
	info "Installing Alpine within chroot";

	# Install base Alpine
	set -e;
	"${SRCDIR}"/sbin/apk.static \
		-X "${MIRROR}/${VERSION}/main" \
		-U \
		--allow-untrusted \
		--root "${ROOTDIR}" \
		--initdb \
		add alpine-base alpine-sdk;
	set +e;

	# Create fs tree
	mkdir -p "${ROOTDIR}"/{root,etc/apk,proc};
}

# Minimal Alpine configuration
function configure_alpine {
	info "Configuring Alpine";
	set -e;
	echo "${MIRROR}/${VERSION}/main" > "${ROOTDIR}/etc/apk/repositories";
	cp --dereference /etc/resolv.conf "${ROOTDIR}"/etc/;
	set +e;
}




#------------------------------------------------------------------------------#
#                                                                              #
#                               Actions functions                              #
#                                                                              #
#------------------------------------------------------------------------------#

# Build Alpine
function build() {
	build_checks;
	prepare_workdir;
	install_alpine;
	configure_alpine;
}

# Destroy Alpine
function destroy() {
	echo "Warning : This will destroy '${WORKDIR}'";
	prompt_continue;
	info "Destroying Alpine in : ${WORKDIR}"

	# Unmount proc and dev if they exists
	set -e;
	if findmnt --source '/proc' --target "${ROOTDIR}/proc" -n >/dev/null; then
		umount "${ROOTDIR}"/proc;
	fi
	if findmnt --source 'dev' --target "${ROOTDIR}/dev" -n >/dev/null; then
		umount "${ROOTDIR}"/dev;
	fi
	set +e;

	# Destroy dir
	rm -rf "${WORKDIR}";
}

# Open Up a shell within the container
function alpine_shell() {
	info "Bind mounting required directories";
	set -e;
	if ! findmnt --source '/proc' --target "${ROOTDIR}/proc" -n >/dev/null; then
		mount -t proc {,"${ROOTDIR}"}/proc;
	fi
	if ! findmnt --source 'dev' --target "${ROOTDIR}/dev" -n >/dev/null; then
		mount --bind {,"${ROOTDIR}"}/dev;
	fi

	info "Chrooting into Alpine";
	chroot "${ROOTDIR}" /bin/su -;
	set +e;
}




#------------------------------------------------------------------------------#
#                                                                              #
#                                 Main functions                               #
#                                                                              #
#------------------------------------------------------------------------------#

# Performs checks to make sure this script will run alright
function init_checks {
	if [[ "${OSTYPE}" != "${OSTYPE}" ]]; then
		error "You must run Linux to use this script.";
		exit 1;
	fi

	if [ "$#" -lt 2 ]; then
		print_usage;
		exit 1;
	fi
}

# Determine action to perform
function main {
	init_checks "${@}";
	local action="${1}";

	# Setup directories structures according to user working dir
	WORKDIR="$(realpath "${2}")";
	SRCDIR="${WORKDIR}"/src;
	ROOTDIR="${WORKDIR}"/root;

	case "${action}" in
		'build' )
			build;
			;;
		'destroy' )
			destroy;
			;;
		'shell' )
			alpine_shell;
			;;
		* )
			error "Unknown action : ${1}";
	esac
}

main "${@}";
