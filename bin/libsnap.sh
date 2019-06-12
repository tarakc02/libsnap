#!/bin/bash

#     libsnap.sh is a library used by snap aka snapshot, snapback, & snapcrypt
#
#     Copyright (C) 2018-2019, Human Rights Data Analysis Group (HRDAG)
#     https://hrdag.org
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

#############################################################################
#############################################################################
### This file sets up a standard environment and defines basic functions.
###
### Source this file at the beginning of all bash scripts.
### Can _run_ this file from a shell to create secure $tmp_dir (see below).
#############################################################################
#############################################################################

# -----------------------------------------------------------------------------

##############################################################################
## There are three kinds of syntax (not always followed) for routines:
##    function func()	# returns status, takes arguments
##    function func	# returns status, doesn't take arguments
##    procedure()	# doesn't return status (exits on fatal error)
##
## There are four kinds of naming for routines that set global variables:
##    set_foo		# sets variable foo
##    set_foo___from_xx	# sets variable foo ... using method xx on args
##    set__foo__bar	# sets variable foo and also sets variable bar
##    setup_foo_vars	# sets numerous variables
##
## An array (indexed or associative) that maps a_key to a_value is named:
##    a_key2a_value
##
## A foo_regex var holds an extended regular expression for bash or egrep.
##
## A global variable/function that's only used by the following
##   variable/function has a name prefixed by '_' (e.g. _chr, defined above).
## A global variable/function that replaces an external version
##   has a name that ends in '_' (e.g. cd_, defined below).
##############################################################################

# -----------------------------------------------------------------------------

##############################################################################
# As setup the environment, errors are problems with libsnap.sh,
# not the calling script.
##############################################################################

# to announce errors in this script
 _warn() { echo -e "\n$0: source libsnap.sh: $*\n" >&2; return 1; }
_abort() {
	_warn "$*"
	[[ $is_sourced_by_interactive_shell ]] && return 1
	exit 1
}

# ----------------------------------------------------------------------------
# setup global variables for calling script
# ----------------------------------------------------------------------------

our_path=${0#-}
[[ $our_path == */* ]] || our_path=$(type -p $our_path)
[[ $our_path == ./* ]] && our_path=${0#./}
[[ $our_path ==  /* ]] || our_path=$PWD/$our_path	; readonly our_path

# we might have been run as a script to create $tmp_dir (see above)
[[ $our_path == */libsnap.sh ]] && exit 0

[[ $our_path == */libsnap    ]] && set -u # for unit tests

# basename of calling script; if already non-blank, we don't change it
our_name=${our_name:-${0##*/}}		# user can change

# put $IfRun in front of key commands, so -d means: debug only, simulate
: ${IfRun=}

readonly true=t True=t
readonly false= False=

case ${0#-} in
    ( bash | csh | ksh | scsh | sh | tcsh | zsh )
	  is_sourced_by_interactive_shell=$true  ;;
    ( * ) is_sourced_by_interactive_shell=$false ;;
esac

readonly lockpid_busy_exit_status=125

_chr='[a-zA-Z0-9]'
rsync_temp_file_suffix="$_chr$_chr$_chr$_chr$_chr$_chr"; unset _chr
					  readonly rsync_temp_file_suffix

#############################################################################
#############################################################################
### First, create PATH that provides priority access to full GNU utilities.
#############################################################################
#############################################################################

# ----------------------------------------------------------------------------
# routines to augment path-style variables
# ----------------------------------------------------------------------------

# return non-0 if any of the passed variable names have not been set
function is_set() {

	local variable_name
	for variable_name
	    do	[[ ${!variable_name+x} ]] || return 1
	done
}

_foo=
is_set _foo || _abort "is_set _foo"
is_set _bar && _abort "is_set _bar"
is_set _foo _bar && _abort "is_set _foo _bar"
unset _foo

# -----------------------------------------------------------------------------

# $1 is path variable name, other args are dirs; append dirs one by one
append_to_PATH_var() {
	local do_reverse_dirs=
	[[ $1 == -r ]] && { do_reverse_dirs=1; shift; }
	local   pathname=$1; shift
	is_set $pathname || abort "$FUNCNAME $1 ... : '$1' is not set"
	local path=${!pathname}

	local dirs=$* dir
	[[ $do_reverse_dirs ]] &&
	for dir
	    do	dirs="$dir $dirs"
	done
	for dir in $dirs
	    do  case $pathname in
		    MANPATH ) [[ -L $dir ]] && continue ;;
		esac
		case :$path: in
		   *:$dir:* ) ;;
		   * ) [[ -d $dir ]] || continue
		       [[ -n $path ]] && path=$path:$dir || path=$dir
		       ;;
		esac
	done

	eval "$pathname=\$path"
}

# ----------------------------------------------------------------------------

# $1 is path variable name, other args are dirs; prepend dirs one by one
prepend_to_PATH_var() {
	local do_reverse_dirs=
	[[ $1 == -r ]] && { do_reverse_dirs=1; shift; }
	local   pathname=$1; shift
	is_set $pathname || abort "$FUNCNAME $1 ... : '$1' is not set"
	local path=${!pathname}

	local dirs=$* dir
	[[ $do_reverse_dirs ]] &&
	for dir
	    do	dirs="$dir $dirs"
	done
	for dir in $dirs
	    do  case $pathname in
		    MANPATH ) [[ -L $dir ]] && continue ;;
		esac
		case :$path: in
		   *:$dir:* ) ;;
		   * ) [[ -d $dir ]] || continue
		       [[ -n $path ]] && path=$dir:$path || path=$dir
		       ;;
		esac
	done

	eval "$pathname=\$path"
}

# ----------------------------------------------------------------------------
# functions to make sure needed utilities are in the PATH
# ----------------------------------------------------------------------------

# return true if have any of the passed commands, else silently return false
function have_cmd() {
	local _cmd

	for _cmd
	   do	type -t $_cmd && return 0
	done &> /dev/null
	return 1
}

# --------------------------------------------

# exit noisily if missing (e.g. not in PATH) any of the $* commands
need_cmds() {

	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=

	local _cmd is_cmd_missing=
	for _cmd
	    do	have_cmd $_cmd && continue

		echo "$our_name: command '$_cmd' is not in current path."
		is_cmd_missing=1
	done

	[[ $is_cmd_missing ]] && exit 2
	$xtrace
}

# -----------------------------------------------------------------------------

# used to precede a command/function that is not yet ready to run
not_yet() { warn "'$*' not yet available, ignoring"; }

# ----------------------------------------------------------------------------
# let sysadmin install newer versions of (GNU) commands in /usr/local/*bin
# ----------------------------------------------------------------------------

prepend_to_PATH_var PATH /usr/local/bin /usr/local/sbin

# ----------------------------------------------------------------------------
# Customization for Darwin (MacOS) + Homebrew, precedence over /usr/local/*bin
# ----------------------------------------------------------------------------

[[ $(uname) == Darwin ]] && readonly is_darwin=$true || readonly is_darwin=

[[ $is_darwin ]] && {

readonly homebrew_install_dir=/usr/local/opt
readonly homebrew_coreutils_bin=$homebrew_install_dir/coreutils/libexec/gnubin

[[ -d $homebrew_coreutils_bin ]] ||
   _abort "you need to install a fairly complete set of GNU utilities with Homebrew; if they're already installed, symlink your Homebrew install directory to $homebrew_install_dir"

prepend_to_PATH_var PATH $homebrew_install_dir/*/libexec/*bin

}

#############################################################################
#############################################################################
### We now have a PATH that provides priority access to full GNU utilities.
#############################################################################
#############################################################################

# ----------------------------------------------------------------------------
# provide a directory for temporary files that's safe from symlink attacks
# ----------------------------------------------------------------------------

tmp_dir=${tmp_dir:-/tmp/$(id -nu)}	# caller is allowed to change tmp_dir
[[ -w ${TMP-}     ]] && tmp_dir=$TMP
[[ -w ${TMP_DIR-} ]] && tmp_dir=$TMP_DIR

# the root filesystem is read-only while booting, don't get into infinite loop!
# GNU mkdir will fail if $tmp_dir is a symlink
until [[ ! -w /tmp ]] || mkdir -m 0700 -p $tmp_dir
   do	_warn "deleting $(ls -ld $tmp_dir)"
	rm -f $tmp_dir
done

export TMP=$tmp_dir TMP_DIR=$tmp_dir	# caller can change these

export LC_COLLATE=C			# so [A-Z] doesn't include a-z
export LC_ALL=C				# server needs nothing special

export RSYNC_RSH=ssh

umask 022				# caller can change it

# ----------------------------------------------------------------------------
# make sure shell has needed features (need' GNU sed)
# ----------------------------------------------------------------------------

[[ ! $is_sourced_by_interactive_shell ]] &&
[[     $BASH_VERSION <  4.2 ]] &&
_abort "bash version >= 4.2 must appear earlier in the PATH than an older bash"

###########################################################################
# define functions that abstract OS/kernel-specific operations or queries #
###########################################################################

# -----------------------------------------------------------------------
# Linux functions for querying hardware; email ${coder-Scott} if fix.   #
# snapback or snapcrypt users can write a replacement in configure.sh . #
# -----------------------------------------------------------------------

FS_type=

set_FS_type___from_path() {
	local  path=$1
	[[ -e $path ]] || abort "$path doesn't exist"

	if [[ ! -b $path || $(df | fgrep -w  $path) ]]
	   then FS_type=$(df --output=fstype $path | tail -n1)
	   else have_cmd lsblk ||
		   abort "fix $FUNCNAME for $path, email to ${coder-Scott}"
		[[ ! -b $path ]] && local FS_device &&
		   set_FS_device___from_path $path  && path=$FS_device
		local cmd="lsblk --noheadings --nodeps --output=fstype $path"
		FS_type=$($cmd)		; [[ $FS_type ]] ||
		FS_type=$(sudo $cmd)
	fi

	[[ $FS_type ]] || warn "$FUNCNAME: $path has no discernible filesystem"
}

# ----------------------------------------------------------------------------

set__inode_size__data_block_size__dir_block_size___from_path() {
	local  path=$1
	[[ -e $path ]] || abort "$FUNCNAME: '$path' doesn't exist"

	local FS_type
	set_FS_type___from_path $path || return $?

	case $FS_type in
	   ( ext? )
		local FS_device
		set_FS_device___from_path $path
		set -- $(sudo tune2fs -l $FS_device |&
				sed -n  -e 's/^Block size://p' \
					-e 's/^Inode size://p'
				exit ${PIPESTATUS[0]})
		local status=$?
		inode_size=${2-} data_block_size=${1-} dir_block_size=${1-}
		[[ $status == 0 ]]
		;;
	   ( xfs  )
		set -- $(xfs_growfs -n $path |
			 sed -n -r -e 's/.* isize=([0-9]+) .*/\1/p'	    \
				   -e '  s/^data .* bsize=([0-9]+) .*/\1/p' \
				   -e 's/^naming .* bsize=([0-9]+) .*/\1/p'
				exit ${PIPESTATUS[0]})
		local status=$?
		inode_size=${1-} data_block_size=${2-} dir_block_size=${3-}
		[[ $status == 0 ]]
		;;
	   (  *   )
		abort "fix $FUNCNAME for $FS_type, email ${coder-}"
		;;
	esac || abort "$FUNCNAME $path (FS_type $FS_type) returned $status"
}

# ----------------------------------------------------------------------------

declare -i device_KB=0

# snapback users can write a replacement in configure.sh
set_device_KB___from_block_device() {
	local  dev=$1
	[[ -b $dev ]] || abort "$dev is not a device"

	device_KB=0
	have_cmd lsblk || return 1

	set -- $(lsblk --noheadings --bytes --output=SIZE $dev)
	[[ $# == 1 ]] || abort "$FUNCNAME: specify a partition not whole drive"
	device_KB=$(( $1/1024 ))
}

# ----------------------------------------------------------------------------

FS_label=

# snapback or snapcrypt users can write a replacement in configure.sh
set_FS_label___from_FS_device() {
	local  dev=$1
	[[ -b $dev ]] || abort "$dev is not a device"

	[[ set_mount_dir___from_FS_device != ${FUNCNAME[1]} ]] && {
	   set_mount_dir___from_FS_device $dev
	set -- $(grep "[[:space:]]$mount_dir[[:space:]]" /etc/fstab)
	[[ ${1-} == LABEL=* ]] && FS_label=${1#*=} || FS_label=	; }

	# don't use lsblk, it sometimes returns very old labels
	if [[ ! ${FS_label-} ]] && have_cmd blkid
	   then local cmd="blkid $dev |
			   sed -n -r 's@.* LABEL=\"?([^ \"]*)\"? .*@\1@p'"
		eval "FS_label=\$($cmd)"	; [[ $FS_label ]] ||
		eval "FS_label=\$(sudo $cmd)"
	fi

	[[ $FS_label ]] ||
	   abort "you need to fix $FUNCNAME and email it to ${coder-Scott}"
}

# ----------------------------------------------------------------------------

label_drive() {
	local  device=$1 mount_dir=$2
	[[ -b $device ]] || abort "$device is not a device"

	local FS_type FS_label
	set_FS_type___from_path $device

	set_FS_label___from_mount_dir $mount_dir

	case $FS_type in
	   ( ext? ) $IfRun sudo e2label $device $FS_label ;;
	   ( xfs  ) $IfRun sudo xfs_admin -L $FS_label $device ;;
	   (  *   ) abort "fix $FUNCNAME for $FS_type, email ${coder-}" ;;
	esac || abort "$FUNCNAME $device $mount_dir returned $? ($FS_type)"
}

# ----------------------------------------------------------------------------

FS_device=

set_FS_device___from_FS_label() {
	local label=$1

	if [[ -d /Volumes ]]		# Darwin?
	   then set_FS_device___from_path /Volumes/$label
		return
	fi

	have_cmd blkid ||
	  abort "you need to fix $FUNCNAME and email it to ${coder-Scott}"

	# -L has a different meaning in older versions, so use old method
	local cmd="blkid -l -o device -t LABEL=$label"
	FS_device=$($cmd)		; [[ $FS_device ]] ||
	FS_device=$(sudo $cmd)

	set_FS_label___from_FS_device $FS_device
	[[ $FS_label == $label ]] ||
	  abort "'blkid' lies: pass device to '$our_name' by-hand"

	[[ $FS_device ]] || abort "couldn't find device for $label"
}

# -----------------------------------------------------------------------------

set__OS_release_file__OS_release() {

	set -- /usr/lib/*-release /etc/*-release
	[[ -s $1 ]] || shift
	while (( $# > 1 ))
	   do	[[ -s $1 ]] || { shift; continue; }
		case $(basename $1) in
		   ( lsb-release ) [[ $# != 0 ]] && shift; continue ;;
		esac
		break
	done
	[[ -s $1 ]] || abort "fix $FUNCNAME and email it to ${coder-Scott}"
	OS_release_file=$1

	case $(basename  $OS_release_file) in
	   ( os-release ) OS_release=$(sed -n 's/^PRETTY_NAME=//p' $1) ;;
	   ( * )	  OS_release=$(< $1) ;;
	esac
}

##############################################################################
##############################################################################
# Finally, define shell functions that only need GNU utilities.
##############################################################################
##############################################################################

# -----------------------------------------------------------------------
# Define FS-label naming conventions.					#
# snapback or snapcrypt users can write replacements in configure.sh .	#
# -----------------------------------------------------------------------

set_FS_device___from_path() {
	local  path=$1
	[[ -e $path ]] || abort "$path doesn't exist"

	FS_device=$(set -- $(df $path | tail -n1); echo $1)

	[[ $FS_device ]] || abort "couldn't find device for $path"
}

# ----------------------------

mount_dir=

set_mount_dir___from_FS_device() {
	local  dev=$1
	[[ -b $dev ]] || abort "$dev is not a device"

	mount_dir=$(set -- $(df $dev | tail -n1); echo ${!#})
	[[ ! $mount_dir || $mount_dir == / || $mount_dir == /dev ]] ||
	   return 0

	set -- $(grep "^[[:space:]]*$dev[[:space:]]" /etc/fstab)
	mount_dir=${2-}
	[[ $mount_dir ]] && return 0

	local FS_label
	set_FS_label___from_FS_device $dev
	set -- $(grep "^[[:space:]]*LABEL=$FS_label[[:space:]]" /etc/fstab)
	mount_dir=${2-}

	[[ $mount_dir ]] || abort "couldn't find mount dir for $dev"
}

# ----------------------------

set_mount_dir___from_FS_label() {
	local label=$1

	mount_dir=/${label//_/\/}
	[[ -d $mount_dir ]]
}

# -------------------------------

set_FS_label___from_mount_dir() {
	local mount_dir=$1

	FS_label=${mount_dir#/}
	FS_label=${FS_label//\//_}
}


# ----------------------------------------------------------------------------
# miscellaneous function(s) needed by next section
# ----------------------------------------------------------------------------

# does 1st argument match any of the whitespace-separated words in rest of args
function is_arg1_in_arg2() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	local arg1=$1; shift
	set -- $*; local arg2=$*	# turn tabs into spaces
	[[ $arg1 && $arg2 ]] || { $xtrace; return 1; }

	[[ " $arg2 " == *" $arg1 "* ]]
	local status=$?
	$xtrace
	return $status
}

# ----------------------------------------------------------------------------
# simple error and warning and trace functions.
# don't assign these until all the environment setup is finished, otherwise
#   a login shell might source it and be terminated by abort's exit. 
# ----------------------------------------------------------------------------

print_call_stack() {
	declare -i stack_skip=1
	[[ ${1-} ==   -s  ]] && { stack_skip=$2+1; shift 2; }
	[[ ${1-} == [0-9] ]] && { (( Trace_level >= $1 )) || return; shift; }

	header -E "call stack"
	for i in ${!FUNCNAME[*]}
	   do	(( i < stack_skip )) && continue # skip ourself
		echo "line ${BASH_LINENO[i-1]} in ${FUNCNAME[i]}()"
	done
	echo >&2
}

# --------------------------------------------

 warn() { echo -e "\n$our_name: $*\n" >&2; return 1; }
abort() {
	set +x
	[[ $1 == -r ]] && { shift; is_recursion=$true; } || is_recursion=$false
	declare -i stack_skip=1
	[[ $1 =~ ^-[0-9]+$ ]] && { stack_skip=${1#-}+1; shift; }

	if [[ $is_recursion ]]
	   then echo "$@" ; stack_skip+=1
	elif [[ ${Usage-} && "$*" == "$Usage" ]]
	   then echo "$@" >&2 ; exit 1
	   else	warn "$@"
	fi

	print_call_stack -s $stack_skip >&2

	[[ ! $is_recursion ]] && log "$(abort -r $* 2>&1)" > /dev/null

	exit 1
}

# ----------------------------------------------------------------------------

# echo to stdError, include the line and function from which we're called
echoE () {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	[[ $1 == -n ]] && { local show_name=$true; shift; } || local show_name=
	declare -i stack_frame_to_show=1 # default to our caller's stack frame
	[[ $1 =~ ^-[0-9]+$ ]] && { stack_frame_to_show=${1#-}+1; shift; }
	[[ $1 != -*  ]] || abort "$FUNCNAME: unknown option $1 (order matters)"

	local   line_no=${BASH_LINENO[stack_frame_to_show-1]}
	local func_name=${FUNCNAME[stack_frame_to_show]}
	[[   $func_name ]] && func_name="line $line_no in $func_name():"

	[[ $show_name ]] && local name="$our_name:" || local name=
	echo -e $name $func_name "$@" >&2
	$xtrace
}

# ----------------------

# like echoE, but also show the values of the variable names passed to us
echoEV() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	declare -i stack_frame_to_show=1 # default to our caller's stack frame
	[[ $1 =~ ^-[0-9]+$ ]] && { stack_frame_to_show=${1#-}+1; shift; }
	[[ $1 != -*  ]] || abort "$FUNCNAME: unknown option $1"

	local var
	for var
	   do	echoE -$stack_frame_to_show "$var=${!var-}"
	done >&2
	$xtrace
}

# ----------------------

declare -i Trace_level=0		# default to none (probably)

is_num() { [[ $1 =~ ^[0-9]+$ ]] || abort -2 "Trace* first arg is a level"; }
Trace () { is_num $1; (($1 <= Trace_level)) ||return 1;shift; echoE  -1 "$@"; }
TraceV() { is_num $1; (($1 <= Trace_level)) ||return 1;shift; echoEV -1 "$@"; }

# ----------------------------------------------------------------------------

declare -A funcname2was_tracing		# global for next three functions

function remember_tracing {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=

	funcname2was_tracing[ ${FUNCNAME[1]} ]=$xtrace

	$xtrace
}

# ----------------------

function suspend_tracing {

	if [[ -o xtrace ]]
	   then set +x
		local was_tracing=$true
	   else local was_tracing=$false
	fi
	funcname2was_tracing[ ${FUNCNAME[1]} ]=$was_tracing
	[[ $was_tracing ]]
}

# ----------------------

# show the values of the variable names passed to us, then restore traing state
restore_tracing() {

	is_arg1_in_arg2 ${FUNCNAME[1]} ${!funcname2was_tracing[*]} ||
	   abort "$FUNCNAME was called without a suspend_tracing"
	[[ ${funcname2was_tracing[ ${FUNCNAME[1]} ]} ]] || return 0

	local variable
	for variable
	    do	if is_set $variable
		   then echo "+ $variable=${!variable}"
		   else echo "+ $variable is not set"
		fi
	done

	set -x
}

wont_trace() {         foo=2
	       suspend_tracing; echo untraced; restore_tracing foo; }
will_trace() { set -x; foo=1
	       suspend_tracing; echo untraced; restore_tracing foo
	       wont_trace; echo traced; set +x; }
will_trace |& fgrep    '+ echo untraced' && _abort "suspend_tracing failed"
will_trace |& fgrep -q '+ echo traced'   || _abort "restore_tracing failed"
unset -f wont_trace will_trace

# ----------------------------------------------------------------------------

print_or_egrep_Usage_then_exit() {
	[[ ${1-} == -[hHk] ]] && shift	# strip help or keyword-search option
	[[ $# == 0 ]] && echo -e "$Usage" && exit 0

	echo "$Usage" | grep -i "$@"
	exit 0
}

# ---------------------------------

abort_with_action_Usage() {
	local _action=${*:-$action}

	echo -e "\nBad arguments; here's the usage for this action:"
	echo "$Usage" | grep "^ *$_action" >&2; echo
	exit 1
}

# ---------------------------------

# RunCmd's args are a command (plus args) that _should_ return 0, else we abort
RunCmd() {
	[[ $1 == -d ]] && { local IfAbort=$IfRun; shift; } || local IfAbort=
	[[ $1 == -m ]] && { local msg="; $2"; shift 2; } || local msg=
	[[ $1 != -*  ]] || abort "$FUNCNAME: unknown option $1 (order matters)"

	$IfRun "$@" || $IfAbort abort -1 "'$*' returned $?$msg"
}

RunCmd true &&
RunCmd -d -m "expected (non fatal)" false |& fgrep -q 'non fatal' ||
   _abort "RunCmd error"

# ----------------------------------------------------------------------------
# Generic logging function, with customization globals that caller can set.
# ----------------------------------------------------------------------------

log_date_format="+%a %m/%d %H:%M:%S"	# caller can change

file_for_logging=/dev/null		# append to it; caller can change

declare -i log_level=0			# usually set by getopts

log_msg_prefix=				# can hold variables, it's eval'ed

log() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	[[ $1 == [0-9] ]] && { local level=$1; shift; } || local level=0
	local _msg="$*"

	(( $level <= $log_level )) || return 1

	[[ ( ! -e $file_for_logging && -w ${file_for_logging%/*} ) ||
	       -w $file_for_logging ]] && local sudo= || local sudo=sudo
	[[ -e $file_for_logging ]] || $sudo mkdir -p ${file_for_logging%/*}

	if [[ $IfRun ]]
	   then local _file_for_logging=/dev/null
	   else local _file_for_logging=$file_for_logging
	fi
	local  _date_time=$(date "$log_date_format")
	local _log_msg_prefix=$log_msg_prefix
	eval "_log_msg_prefix=\"$_log_msg_prefix\""
	_log_msg_prefix=$(echo "$_log_msg_prefix" | sed 's/ *$//')
	echo "$_date_time$_log_msg_prefix: $_msg" |
	   $sudo tee -a $_file_for_logging
	$xtrace
	return 0
}

# ----------------------------------------------------------------------------

# show head-style header
header() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	[[ $1 == -e ]] && { shift; local nl="\n"; } || local nl=
	[[ $1 == -E ]] &&   shift || echo
	[[ $1 != -*  ]] || abort "$FUNCNAME: unknown option $1 (order matters)"

	echo -e "==> $* <==$nl"
	$xtrace
}

# ----------------------------------------------------------------------------
# miscellaneous functions
# ----------------------------------------------------------------------------

set_absolute_dir() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	[[ $# == 1 ]] || abort "Usage: $FUNCNAME filename" || return 1
	local name=$1

	[[ -d "$name" ]] || name=$(dirname "$name")
	absolute_dir=$(cd "$name" && /bin/pwd) # simpler than readlink(s)
	$xtrace
}

# -------------------------------------------------------

set_absolute_path() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	[[ $# == 1 ]] || abort "Usage: $FUNCNAME filename" || return 1
	local name=$1

	local absolute_dir
	set_absolute_dir "$name"
	  if [[ -d "$name" ]]
	   then absolute_path=$absolute_dir
	elif [[ -L "$name" ]]
	   then set_absolute_path $absolute_dir/$(readlink "$name")
	   else     absolute_path=$absolute_dir/$(basename "$name")
	fi
	$xtrace
}

# ----------------------------------------------------------------------------

cd_() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	(( $# <= 1 )) || abort "wrong number args: $FUNCNAME $*"
	local _dir=${1-$HOME}

	cd "$_dir" || abort "cd $_dir"
	# -n and -z needed here for buggy 2.04 version of bash (in RHL 7.1)
	if [[ ( -n $IfRun || -n ${do_show_cd-} ) && -z ${Trace-} ]]
	   then local _msg="cd $PWD"
		[[ $_dir == */.* && $_dir != /* ]] && _msg="$_msg # $_dir"
		echo "$_msg"
	fi
	$xtrace
	return 0
}

# ----------------------------------------------------------------------------

set_FS_inodes_used_percent() {
	local _dir=$1

	# -A 1: multi-line records for long dev names (like Logical Volumes)
	set -- $(df --inodes --no-sync $_dir/. | grep -A 1 "^/")
	FS_inodes_used_percent=${5%\%}
}

# ----------------------------------------------------------------------------

set_FS_space_used_percent() {
	local _dir=$1

	# -A 1: multi-line records for long dev names (like Logical Volumes)
	set -- $(df -k --no-sync $_dir/. | grep -A 1 "^/")
	FS_space_used_percent=${5%\%}
}

# ----------------------------------------------------------------------------

set_file_KB() {
	local _file=$1

	set -- $(ls -sd $_file)
	file_KB=$1
	[[ $file_KB ]]
}

# ----------------------------------------------------------------------------

# return 0 if all processes alive, else 1; unlike 'kill -0', works without sudo
function is_process_alive() {

	local PID
	for PID
	    do	if [[ -d /proc ]]
		   then [[ -d /proc/$PID ]] || return 1
		   else case $(kill -0 $PID 2>&1) in
			   ( *"Operation not permitted"* )
				sudo kill -h > /dev/null ||
				   abort "$FUNCNAME: need 'sudo kill' perms"
				local sudo=sudo
				;;
			   ( * )
				local sudo=
				;;
			esac
			$sudo kill -0 $PID >& /dev/null || return 1
		fi
	done
	return 0
}

is_process_alive $$ $BASHPID || _abort "is_process_alive failure"

# -----------------------------------------------------------------------------

function is_readonly() {

	local variable_name
	for variable_name
	    do	eval "$variable_name+=" 2> /dev/null && return 1
	done
	return 0
}

_readonly_vars="our_path true false"
_writable_vars="our_name IfRun"
is_readonly $_readonly_vars || _abort "is_readonly $_readonly_vars"
is_readonly $_readonly_vars $_writable_vars && _abort "is_readonly all-vars"

# ---------------------------------

function is_writable() {

	local variable_name
	for variable_name
	    do	eval "$variable_name+=" 2> /dev/null || return 1
	done
	return 0
}

is_writable $_writable_vars || _abort "is_writable $_writable_vars"
is_writable $_writable_vars $_readonly_vars && _abort "is_readonly all-vars"
unset _readonly_vars _writable_vars

# ----------------------------------------------------------------------------

# pop word off left side of named list; return non-0 if list was empty
function set_popped_word___from_list() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	[[ $# == 1 ]] && is_set $1 || abort "$FUNCNAME: pass name of list"

	local   list_name=$1
	is_set $list_name || abort "$FUNCNAME $1: '$1' is not set"
	set -f; set -- ${!list_name}; set -- $*; set +f
	popped_word=${1-}; shift	# grab left-most word
	eval "$list_name=\$*"		# retain the rest of the words
	$xtrace
	[[ $popped_word ]]
}

_numbers="1 2 3"
  _input=$_numbers
 _output=
while set_popped_word___from_list _input
   do	_output+=" $popped_word"
done
_output=${_output# }
[[ ! $_input && $_output == "$_numbers" ]] ||
    _abort "set_popped_word___from_list failure: _input='$_input' _output='$_output'"
unset _numbers _input _output popped_word

# ----------------------------------------------------------------------------

function confirm() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	[[ $1 == -n  ]] && { echo; shift; }
	[[ $1 != -*  ]] || abort "$FUNCNAME: unknown option $1"
	local _prompt=$1 default=${2-}

	local y_n status
	case $default in
	   [yY]* ) y_n="Y/n" status=0 ;;
	   [nN]* ) y_n="y/N" status=1 ;;
	   *     ) y_n="y/n" status=  ;;
	esac

	[[ -t 0 ]] || { $xtrace; return $status; }

	_prompt+=" ($y_n)? "

	local key
	while read -n 1 -p "$_prompt" key
	   do	# $xtrace
		case $key in
		   [yY]* ) status=0 && break ;;
		   [nN]* ) status=1 && break ;;
		   *     ) [[ $status ]] && { $xtrace; return $status; } ;;
		esac
		set +x
		echo
	done
	echo

	[[ $status ]] || abort "$FUNCNAME $*: read failure"
	$xtrace
	return $status
}

# ----------------------------------------------------------------------------

assert_accessible() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	local tests=
	while [[ $1 == -* ]] ; do tests="$tests $1"; shift; done

	local file
	for file
	   do	[[ -e $file ]] || abort "'$file' doesn't exist"

		local test
		for test in $tests
		    do	eval "[[ $test '$file' ]]" ||
			   abort "'$file' fails test $test"
		done
	done
	$xtrace
}

# -------------------

function assert_readable()       { assert_accessible -r "$@"; }
function assert_writable()       { assert_accessible -w "$@"; }
function assert_executable()     { assert_accessible -x "$@"; }

function assert_writable_dirs()  { assert_writable -d -x "$@"; }
function assert_writable_files() { assert_writable -f    "$@"; }

# ----------------------------------------------------------------------------

# File $1 is modified in-place (with optional backup) by subsequent command.
# You don't need this in general, you can use: perl -i~ -e ...
modify_file() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	local backup_ext=
	[[ $1 == -b* ]] && { backup_ext=$1; shift; }
	[[ $1 != -*  ]] || abort "$FUNCNAME: unknown option $1"
	(( $# >= 2   )) || abort "Usage: $FUNCNAME [-b[ext]] file command"
	local file=$1; shift

	local dir
	set_dir "$file"

	assert_writable_files "$file"
	assert_writable_dirs  "$dir"

	if [[ $backup_ext ]]
	   then backup_ext=${backup_ext#-b}
		local backup=$file${backup_ext:-'~'}
		ln -f "$file" "$backup" ||
		    abort "$FUNCNAME can't backup '$file'"
	fi

	# we use cp -p just to copy the file metadata (uid, gid, mode)
	cp -p "$file"   "$file+" &&
	 "$@" "$file" > "$file+" &&
	  mv  "$file+"  "$file"  ||
	   abort "$FUNCNAME $file $* => $?"
	$xtrace
}

# --------------------------------------------

assert_sha1sum()
{
	local sha1sum=$1 file=${2-}

	set --  $(sha1sum $file)
	[[ $1 == $sha1sum ]] && return 0
	abort    "sha1sum($file) != $sha1sum"
}

# ----------------------------------------------------------------------------

# Test an internal function by passing its name + options + args to our script;
# to show values of global variables it alters, pass: -v "varname(s)"
run_function()
{
	local is_procedure=$false	# abort if function "fails"
	[[ $1 == -p ]] && { is_procedure=$true; shift; }
	[[ $1 == -v ]] && { local var_names=$2; shift 2; } || local var_names=
	[[ $1 != -*  ]] || abort "$FUNCNAME: unknown option $1 (order matters)"

	have_cmd $1 || abort "function '$1' doesn't exist"

	"$@"
	local status=$?
	[[ $var_names ]] && echoEV -1 $var_names
	[[ $status == 0 || $is_procedure ]] || abort -1 "'$*' returned $status"
	return $status
}

# ----------------------------------------------------------------------------

pegrep() { grep --perl-regexp "$@"; }

# ----------------------------------------------------------------------------

does_file_end_in_newline()
{
	local file
	for file
	    do	[[ -f $file && -s $file ]] || return 1
		[[ $(tail -c 1 $file) ]] && return 1
	done
	return 0
}

# ----------------------------------------------------------------------------

# strip leading tabs (shell script's indent) from $1, and expand remaining tabs
set_python_script() {
	[[ $# == 1 ]] || abort "$FUNCNAME takes one arg, got $#" || return 1
	python_script=$1

	local leading_tabs='						'
	local    line_count=$(echo "$python_script" | grep '[a-z]' | wc -l)
	while [[ ${#leading_tabs} != 0 ]]
	   do	local count=$(echo "$python_script" | grep '[a-z]' |
				 grep -c "^$leading_tabs")
		[[ $count == $line_count ]] && break
		leading_tabs=${leading_tabs#?}
	done
	true || [[ ${#leading_tabs} != 0 ]] || # allow this
	   warn "$FUNCNAME: we expected python script would be tab-indented"

	python_script=$(echo "$python_script" |
			sed "s/^$leading_tabs//" | expand)
}

true					# we must return 0
