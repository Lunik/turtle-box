#!/usr/bin/env bash

# -----------------------------------#
#          Sources Settings          #
# -----------------------------------#
MIRROR="http://dl-cdn.alpinelinux.org/alpine";
ARCH="x86_64";
VERSION="v3.7";
APK_TOOL="apk-tools-static-2.8.2-r0.apk";

# -----------------------------------#
#        TurtleBox Parameters        #
# -----------------------------------#

# Default user settings
DEFAULT_USER='turtle';                 # User name
DU_GROUP="${DEFAULT_USER}";            # Group name
DU_DESC='Turtle Default User';         # User description
DU_HOME="/home/${DEFAULT_USER,,}";     # User home
DU_SHELL='/bin/sh';                    # User shell
DU_UID="501";                          # User UID
DU_GID="${DU_UID}";                    # User GID

# Network settings
HOSTNAME="alpine"
DHCP_IFACE="eth0";                     # Interface plugged to a DHCP server
CLIENT_IFACE="eth1";                   # Interface plugged to the spoofed client

# Spoofing settings
DHCP_NETWORK="192.168.100.0/24";       # DHCP Range to use for the spoofed iface

# Required packages
TURTLE_PACKAGES=(
	'sudo'
	'dnsmasq'
	'iptables'
)

# -----------------------------------#
#         Debugging Settings         #
# -----------------------------------#
DEBUG="y";

#set -o xtrace

################################################################################
#                                                                              #
#                               Utility functions                              #
#                                                                              #
################################################################################

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

# Convert a mask address to a CIDR
function mask2cdr {
	local mask="${1}";

	# Table of bytes : groups of 4 chars representing 1 bit in the mask
	local table='0ˆˆˆ128ˆ192ˆ224ˆ240^248^254^';

	# Assumes there's no "255." after a non-255 byte in the mask
	# Then lift all 255 bytes (except 4th one if so)
	local lifted_mask="${mask##*255.}";

	# Lift the table of all values >= next_byte
	local lifted_table="${table%%${lifted_mask%%.*}*}";

	# Echo total count of bits lifted
	#   First pass : 255 value = 8 bits ==> 4 chars lifted = 8 bits lifted
	#   Second pass : 4chars = 1 bit ==> 4 chars lifted = 1 bit lifted
	echo "$(( ( (${#mask} - ${#lifted_mask}) * 2 )  + ( ${#lifted_table} / 4 ) ))";
}

# Convert a CIDR to a mask address
function cdr2mask {
	local cidr="${1}";

	# How to calculate non 255 byte
	local special_byte="( 255 << ( 8 - (${cidr} % 8) ) ) & 255";

	# Build the mask within positional parameters
	set -- '255' '255' '255' '255' "$(( ${special_byte} ))";

	# Shift unused bytes to position the mask
	shift "$(( 4 - (${cidr} / 8) ))";

	# Print the mask
	echo "${1:-0}.${2:-0}.${3:-0}.${4:-0}";
}

# Get address of network ${1} + count ${2}
function netaddr_add {
	local netaddr="${1}";
	local count="${2}";

	# Make bytes more accessible
	local bytes=( ${netaddr//./ } );

	# Add it
	local x;
	local next=${count};
	for index in {3..0}; do
		# Add count to current value
		x="$(( ${bytes[${index}]} + ${next} ))";
		# Calculate count to add to next byte
		next="$(( ${x} / 256 ))";
		# Calculate value
		bytes[${index}]="$(( ${x} % 256  ))";
	done

	# Print new one
	local res="${bytes[*]}";
	echo "${res// /.}";
}

# Count of viable host addresses for a cidr
function net_host_count {
	local cidr="${1}";
	echo "$(( 2**(32 - ${cidr} ) - 2 ))";
}




################################################################################
#                                                                              #
#                            Build Step functions                              #
#                                                                              #
################################################################################

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

	# Check if cidr >=0 <=30
	local cidr="${DHCP_NETWORK##*/}"
	if [ "${cidr}" -lt 0 ] || [ "${cidr}" -gt 30 ]; then
		error "DHCP Network has an incorrect CIDR";
		exit 1;
	fi
}

# Create workdir and get utility files
function prepare_workdir {
	info "Creating working directory file structure";
	mkdir -p "${SRCDIR}" "${ROOTDIR}";
	chmod 755 "${ROOTDIR}";

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

# Configure Alpine to be a TurtleBox
function configure_turtlebox {
	# User lines for files contents
	local du_passwd="${DEFAULT_USER,,}:x:${DU_UID}:${DU_GID}:${DU_HOME}:${DU_SHELL}:${DU_SHELL}";
	local du_group="${DU_GROUP,,}:x:${DU_GID}:${DEFAULT_USER,,}";
	local du_home="${ROOTDIR}/${DU_HOME}";

	# DHCP settings
	local network="${DHCP_NETWORK%%/*}";
	local cidr="${DHCP_NETWORK##*/}";
	local netmask="$(cdr2mask "${cidr}")";
	local first_netaddr="$(netaddr_add "${network}" 1)";
	local second_netaddr="$(netaddr_add "${first_netaddr}" 1)";
	local last_netaddr="$(netaddr_add "${network}" "$(net_host_count ${cidr})")";
	local lifted_netmask="${netmask%%.0*}";

	# Install additional packages
	info "Installing additional packages : ${TURTLE_PACKAGES[@]}";
	"${SRCDIR}"/sbin/apk.static \
		-X "${MIRROR}/${VERSION}/main" \
		-U \
		--allow-untrusted \
		--root "${ROOTDIR}" \
		--initdb \
		add "${TURTLE_PACKAGES[@]}";

	info "Creating user ${DEFAULT_USER}"
	set -e
	# Create user and group
	echo "${du_passwd}" >> "${ROOTDIR}"/etc/passwd;
	echo "${du_group}" >> "${ROOTDIR}"/etc/group;

	# Create his home dir
	mkdir -p "${du_home}";
	chown -R "${DU_UID}:${DU_GID}" "${du_home}";

	# Configure SSH
	info "Configuring ssh for user ${DEFAULT_USER}";
	mkdir -p "${du_home}"/.ssh;

	# Configure sudo
	info "Configuring sudo for user ${DEFAULT_USER}";
	echo "${DEFAULT_USER} ALL=(ALL) NOPASSWD: ALL" >> "${ROOTDIR}"/etc/sudoers

	# Add local scripts running at boot
	# Equivalent to 'rc-update add local boot'
	info "Adding local scripts at boot"
	ln -s '/etc/init.d/local' "${ROOTDIR}/etc/runlevels/boot"

	# Configure networking
	info "Configuring Networking"
	cat > "${ROOTDIR}"/etc/network/interfaces <<-EOF
		# Setup Loopback interface
		auto lo
		iface lo inet loopback

		# Interface plugged to a DHCP server
		auto ${DHCP_IFACE}
		iface ${DHCP_IFACE} inet dhcp
		    hostname ${HOSTNAME}

		# Interface plugged to the spoofed client
		auto ${CLIENT_IFACE}
		iface ${CLIENT_IFACE} inet static
		    address ${first_netaddr}
		    netmask ${netmask}
	EOF

	# Configure DNSmasq
	info "Configuring DNSmasq"
	sed -i "${ROOTDIR}"/etc/dnsmasq.conf \
		-e "s/\s*#\s*interface\s*=/interface=${CLIENT_IFACE}/g" \
		-e "0,/\s*#dhcp-range\s*=/ s/\s*#\s*dhcp-range\s*=.*/dhcp-range=${second_netaddr},${last_netaddr},${lifted_netmask},1h/" \
		-e "0,/\s*#dhcp-option\s*=/ s/\s*#\s*dhcp-option\s*=.*/#Default Gateway\ndhcp-option=3,${first_netaddr}\n#DNS Server\ndhcp-option=6,${first_netaddr}/";
	ln -s '/etc/init.d/dnsmasq' "${ROOTDIR}"/etc/runlevels/boot/

	# Enable IP Forwarding
	info "Enabling IP Forwarding"
	echo "net.ipv4.ip_forward=1" > "${ROOTDIR}"/etc/sysctl.d/01-turtlebox.conf

	# Configure NAT
	info "Configure NAT"
	cat > "${ROOTDIR}/etc/local.d/nat.start" <<-EOF
		#!/bin/sh

		IPTABLES='/sbin/iptables'

		\${IPTABLES} -t nat -A POSTROUTING -o ${DHCP_IFACE} -j MASQUERADE
		\${IPTABLES} -A FORWARD -i ${DHCP_IFACE} -o ${CLIENT_IFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT
		\${IPTABLES} -A FORWARD -i ${CLIENT_IFACE} -o ${DHCP_IFACE} -j ACCEPT
	EOF
	chmod +x "${ROOTDIR}/etc/local.d/nat.start";

	set +e;
}




################################################################################
#                                                                              #
#                               Actions functions                              #
#                                                                              #
################################################################################

# Build Alpine
function build() {
	build_checks;
	prepare_workdir;
	install_alpine;
	configure_alpine;
	configure_turtlebox;
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




################################################################################
#                                                                              #
#                                 Main functions                               #
#                                                                              #
################################################################################

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
