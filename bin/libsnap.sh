#!/bin/bash

#############################################################################
#############################################################################
### This file sets up a standard environment and defines basic functions.
###
### Source this file at the beginning of all bash scripts.
### Can _run_ this file from a shell to create secure $tmp_dir (see below).
#############################################################################
#############################################################################

##############################################################################
# As setup the environment, errors are problems with libsnap.sh,
# not the calling script.
##############################################################################

# to announce errors in this script (these functions will be replaced later)
 warn() { echo -e "\n$0: source libsnap.sh: $*\n" >&2; return 1; }
abort() {
	warn "$*"
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

# basename of calling script; if already non-blank, we don't change it
our_name=${our_name:-${0##*/}}		# user can change

# put $IfRun in front of key commands, so -d means: debug only, simulate
: ${IfRun=}

true=t True=t					; readonly true  True
false= False=					; readonly false False

case ${0#-} in
    ( bash | csh | ksh | scsh | sh | tcsh | zsh )
	  is_sourced_by_interactive_shell=$true  ;;
    ( * ) is_sourced_by_interactive_shell=$false ;;
esac

_chr_='[a-zA-Z0-9]'
rsync_temp_file_suffix="$_chr_$_chr_$_chr_$_chr_$_chr_$_chr_"; unset _chr_
					  readonly rsync_temp_file_suffix

#############################################################################
#############################################################################
### First, create PATH that provides priority access to full GNU utilities.
#############################################################################
#############################################################################

# ----------------------------------------------------------------------------
# routines to augment path-style variables
# ----------------------------------------------------------------------------

# $1 is path variable name, other args are dirs; append dirs one by one
append_to_PATH_var() {
	local do_reverse_dirs=
	[[ $1 == -r ]] && { do_reverse_dirs=1; shift; }
	local pathname=$1; shift
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
	local pathname=$1; shift
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
   abort "you need to install a fairly complete set of GNU utilities with Homebrew; if they're already installed, symlink your Homebrew install directory to $homebrew_install_dir"

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
   do	warn "deleting $(ls -ld $tmp_dir)"
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
[[    $BASH_VERSION <  4.2 ]] &&
abort "bash version >= 4.2 must appear earlier in the PATH than an older bash"

##############################################################################
## there are three kinds of syntax for routines (not always followed):
##    function func()	# returns status, takes arguments
##    function func	# returns status, doesn't take arguments
##    procedure()	# doesn't return status (exits on fatal error)
##
## there are two kinds of routines that set global variables:
##    set_foo		# set variable foo
##    set_foo___from_xx	# set variable foo ... using method xx on args
##    set__foo__bar	# set variable foo and variable bar
##############################################################################

###########################################################################
# define functions that abstract OS/kernel-specific operations or queries #
###########################################################################

# -------------------------------------------------------------------------
# Linux functions for querying hardware; email ${coder-Scott} if rewrite. #
# snapback or snapcrypt users can write a replacement in configure.sh .   #
# -------------------------------------------------------------------------

FS_type=

set_FS_type___from_path() {
	local  path=$1
	[[ -e $path ]] || abort "$path doesn't exist"

	if [[ ! -b $path || $(df | fgrep -w  $path) ]]
	   then FS_type=$(df --output=fstype $path | tail -n1)
	   else have_cmd lsblk ||
		   abort "rewrite $FUNCNAME and email it to ${coder-Scott}"
		[[ ! -b $path ]] && local FS_device &&
		   set_FS_device___from_path $path  && path=$FS_device
		local cmd="lsblk --noheadings --output=fstype $path"
		FS_type=$($cmd)		; [[ $FS_type ]] ||
		FS_type=$(sudo $cmd)
	fi

	[[ $FS_type ]] || abort "$FUNCNAME $path; email fix to ${coder-Scott}"
}

# ----------------------------------------------------------------------------

set_FS_block_size___from_path() {
	local  path=$1
	[[ -e $path ]] || abort "$path doesn't exist"

	local FS_type
	set_FS_type___from_path $path

	case $FS_type in
	   ( ext? )
		local FS_device
		set_FS_device___from_path $path
		FS_block_size=$(sudo tune2fs -l $FS_device |&
				sed -n 's/^Block size: *//p')
		;;
	   ( xfs  )
		FS_block_size=$(xfs_growfs -n $path |
				sed -n -r 's/^data .* bsize=([0-9]+) .*/\1/p')
		;;
	   (  *   )
		abort "rewrite $FUNCNAME for $FS_type, email ${coder-}"
		;;
	esac || abort "$FUNCNAME $device $mount_dir -> $? ($FS_type)"
}

# ----------------------------------------------------------------------------

FS_label=

# snapback or snapcrypt users can write a replacement in configure.sh
set_FS_label___from_FS_device() {
	local  dev=$1
	[[ -b $dev ]] || abort "$dev is not a device"

	have_cmd blkid ||
	  abort "you need to rewrite $FUNCNAME and email it to ${coder-Scott}"

	local cmd="blkid $dev | sed -n -r 's@.* LABEL=\"?([^ \"]*)\"? .*@\1@p'"
	eval "FS_label=\$($cmd)"	; [[ $FS_label ]] ||
	eval "FS_label=\$(sudo $cmd)"

	[[ $FS_label ]] || abort "$FUNCNAME $dev"
}

# ---

# lsblk often returns a very-old label
# snapback or snapcrypt users can write a replacement in configure.sh
set_FS_label___from_FS_device___unreliable_version() {
	local dev=$1

	have_cmd lsblk ||
	  abort "you need to rewrite $FUNCNAME and email it to ${coder-Scott}"

	local cmd="lsblk --noheadings --output=label $dev"
	FS_label=$($cmd)		; [[ $FS_label ]] ||
	FS_label=$(sudo $cmd)

	[[ $FS_label ]] || abort "$FUNCNAME $dev"
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
	   (  *   ) abort "rewrite $FUNCNAME for $FS_type, email ${coder-}" ;;
	esac || abort "$FUNCNAME $device $mount_dir -> $? ($FS_type)"
}

# ----------------------------------------------------------------------------

FS_device=

set_FS_device___from_FS_label() {
	local FS_label=$1

	if [[ -d /Volumes ]]		# Darwin, use FS_label for basename
	   then set_FS_device___from_path /Volumes/$FS_label
		return
	fi

	have_cmd blkid ||
	  abort "you need to rewrite $FUNCNAME and email it to ${coder-Scott}"

	# -L has a different meaning in older versions, so use old method
	local cmd="blkid -l -o device -t LABEL=$FS_label"
	FS_device=$($cmd)		; [[ $FS_device ]] ||
	FS_device=$(sudo $cmd)

	[[ $(e2label $FS_device) == $FS_label ]] ||
	  abort "'blkid' lies: pass device to '$our_name' by-hand"

	[[ $FS_device ]] || abort "$FUNCNAME $FS_label"
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
	local  path=$path
	[[ -e $path ]] || abort "$path doesn't exist"

	FS_device=$(set -- $(df $path | tail -n1); echo $1)

	[[ $FS_device ]] || abort "$FUNCNAME $path"
}

# ----------------------------

mount_dir=

set_mount_dir___from_FS_device() {
	local  dev=$1
	[[ -b $dev ]] || abort "$dev is not a device"

	mount_dir=$(set -- $(df $dev | tail -n1); echo ${!#})

	[[ $mount_dir ]] || abort "$FUNCNAME $dir"
}

# ----------------------------

set_mount_dir___from_FS_label() {
	local label=$1

	mount_dir=/${FS_label//_/\/}
}

# -------------------------------

set_FS_label___from_mount_dir() {
	local mount_dir=$1

	FS_label=${mount_dir#/}
	FS_label=${FS_label//\//_}
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

	if [[ $is_recursion ]]
	   then echo "$@" ; declare -i stack_skip=2
	elif [[ ${Usage-} && "$*" == "$Usage" ]]
	   then echo "$@" >&2 ; exit 1
	   else	warn "$@" ; declare -i stack_skip=1
	fi

	print_call_stack -s $stack_skip

	[[ ! $is_recursion ]] && log "$(abort -r $* 2>&1)" > /dev/null

	exit 1
}

# ----------------------------------------------------------------------------

echoE () {				 # echo to stdError
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	[[ $1 == -n ]] && { local show_name=$true; shift; } || local show_name=
	declare -i stack_frame_to_show=1 # default to our caller's stack frame
	[[ $1 == -[0-9]* ]] && { stack_frame_to_show=${1#-}+1; shift; }

	local   line_no=${BASH_LINENO[stack_frame_to_show-1]}
	local func_name=${FUNCNAME[stack_frame_to_show]}
	[[   $func_name ]] && func_name="line $line_no in $func_name():"

	[[ $show_name ]] && local name="$our_name:" || local name=
	echo -e $name $func_name "$@" >&2
	$xtrace
}

echoEV() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	declare -i stack_frame_to_show=1 # default to our caller's stack frame
	[[ $1 == -[0-9]* ]] && { stack_frame_to_show=${1#-}+1; shift; }

	local var
	for var
	   do	echoE -$stack_frame_to_show "$var=${!var-}"
	done >&2
	$xtrace
}

declare -i Trace_level=0		# default to none (probably)

Trace () { (( $1 <= Trace_level )) || return 1; shift; echoE  -1 "$@"; }
TraceV() { (( $1 <= Trace_level )) || return 1; shift; echoEV -1 "$@"; }

# ----------------------------------------------------------------------------

_was_tracing=				# global for next two functions

function suspend_tracing {

	if [[ -o xtrace ]]
	   then set +x
		_was_tracing=$true
	   else _was_tracing=$false
	fi
}

restore_tracing() {

	[[ $_was_tracing ]] || return 0

	for variable
	    do	echo "+ $variable=${!variable}"
	done

	set -x
}

# ----------------------------------------------------------------------------

print_or_egrep_Usage_then_exit() {
	[[ ${1-} == -[hHk] ]] && shift	# strip help or keyword-search option
	[[ $# == 0 ]] && echo -e "$Usage" && exit 0

	echo "$Usage" | grep -i "$@"
	exit 0
}

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

	[[ ! -e $file_for_logging || -w $file_for_logging ]] &&
	   local sudo= || local sudo=sudo
	local  _date_time=$(date "$log_date_format")
	local _log_msg_prefix=$log_msg_prefix
	eval "_log_msg_prefix=\"$_log_msg_prefix\""
	_log_msg_prefix=$(echo "$_log_msg_prefix" | sed 's/ *$//')
	echo "$_date_time$_log_msg_prefix: $_msg" |
	   $sudo tee -a $file_for_logging
	$xtrace
	return 0
}

# ----------------------------------------------------------------------------

# show head-style header
header() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	[[ $1 == -E ]] && shift || echo

	echo -e "==> $* <=="
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
	absolute_dir=$(cd "$name" && /bin/pwd)
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
	   else absolute_path=$absolute_dir/$(basename "$name")
	fi
	$xtrace
}

# ----------------------------------------------------------------------------

cd_() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	(( $# <= 1 )) || abort "wrong number args: cd_ $*"
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

# sometimes test reports false when process _is_ alive, so try a few times
function is_process_alive() {

	local PID
	for PID
	    do	local did_find_process=$false
		local try
		for try in 1 2 3 4 5
		    do	if kill -0 $PID
			   then did_find_process=$true
				break
			   else [[ $UID == 0 ]] || # 'kill' works if we're root
				case $(kill -0 $PID 2>&1) in
				   ( *"Operation not permitted"* )
					did_find_process=$true
					break ;;
				   ( *"No such process"* )
					;;
				   ( * )
					if [[ -d /proc/$PID ]]
					   then did_find_process=$true
						break
					fi ;;
				esac
			fi &> /dev/null
			[[ $is_xen_domU ]] && break # domU can't do usleep
			usleep 123123
		done
		[[ $did_find_process ]] || return 1
	done
	return 0
}

# ----------------------------------------------------------------------------

# in variable named $1, append the subsequent args (with white space)
function add_words() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	local variable_name=$1; shift

	[[ $# == 0 ]] && $xtrace && return 0 # maybe no words to add

	# it's too hard to detect "unbound variable" in this case
	local unbound_variable_msg="
	  $FUNCNAME $variable_name $*: $variable_name is unset"
	local value=${!variable_name?"$unbound_variable_msg"}

	if [[ $value ]]
	   then eval "$variable_name=\"\$value \$*\""
	   else eval "$variable_name=\$*"
	fi

	$xtrace
	return 0
}

# ----------------------------------------------------------------------------

function confirm() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	[[ $1 == -n  ]] && { echo; shift; }
	local _prompt=$1 default=${2-}

	local y_n status
	case $default in
	   [yY]* ) y_n="Y/n" status=0 ;;
	   [nN]* ) y_n="y/N" status=1 ;;
	   *     ) y_n="y/n" status=  ;;
	esac

	[[ -t 0 ]] || return $status

	add_words _prompt "($y_n)? "

	local key
	while read -n 1 -p "$_prompt" key
	   do	$xtrace
		case $key in
		   [yY]* ) status=0 && break ;;
		   [nN]* ) status=1 && break ;;
		   *     ) [[ $status ]] && return $status ;;
		esac
		set +x
		echo
	done
	echo

	[[ $status ]] || abort "confirm $*: read failure"
	$xtrace
	return $status
}

# ----------------------------------------------------------------------------

# does 1st argument match any of the space-separated words in rest of arguments
function is_arg1_in_arg2() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	local arg1=$1; shift; local arg2=$*
	[[ $arg1 && $arg2 ]] || return 1

	[[ " $arg2 " == *" $arg1 "* ]]
	local status=$?
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
	[[ $# -ge 2 ]] || abort "Usage: modify_file [-b[ext]] file command"
	local file=$1; shift

	local dir
	set_dir "$file"

	assert_writable_files "$file"
	assert_writable_dirs  "$dir"

	if [[ $backup_ext ]]
	   then backup_ext=${backup_ext#-b}
		local backup=$file${backup_ext:-'~'}
		ln -f "$file" "$backup" || abort "can't backup '$file'"
	fi

	# we use cp -p just to copy the file metadata (uid, gid, mode)
	cp -p "$file"   "$file+" &&
	 "$@" "$file" > "$file+" &&
	  mv  "$file+"  "$file"  ||
	   abort "modify_file $file $* => $?"
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

# to test (top-level) functions by passing names as _args_ to $our_name script
# TODO: add getopts, then support -a: Abort if any function returns non-0
run_functions()
{
	local is_procedure=$false	# assume 'warn' if function "fails"
	[[ $1 == -p ]] && { is_procedure=$true; shift; }
	local functions=$*

	local status=0

	local function
	for   function in $functions
	    do	have_cmd  $function ||
		    abort "function '$function' doesn't exist"
		$function && continue
		status=$?
		[[ $is_procedure ]] ||
		   warn "function '$function' returned $status"
	done

	return $status
}

# ----------------------

run_procedures() { run_functions -p "$@"; }

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
