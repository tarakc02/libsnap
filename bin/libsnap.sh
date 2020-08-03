#! /usr/bin/env bash

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

# ----------------------------------------------------------------------------

##############################################################################
## There are three kinds of syntax (not always followed) for functions:
##    function func()	# returns status, takes arguments
##    function func	# returns status, doesn't take arguments
##    procedure()	# doesn't return status (exits on fatal error)
## Function names are words separated by '-' (not '_'), to facilitate ...
## There are four kinds of naming for functions that set global variables:
##    set-foo		# sets foo; 30x faster than foo=$(func), & side-effects
##    set-foo-foo_bar	# sets variable foo and also sets variable foo_bar
##    set-foo--from-xxx	# sets variable foo ... using method/variable xxx
##    setup-foo-vars	# sets numerous variables related to foo
## if "set-" is replaced by "update-" or "append-to-" or "prepend-to-",
##    the (initialized) variable(s) are updated rather than set.
##
## An array (indexed or associative) that maps a_key to a_value is named:
##    a_key2a_value
##
## A foo_regex var holds an extended regular expression for =~ or egrep.
##
## Boolean variables, or boolean functions [that return true (0) or false (1)],
##   have names that start with an action verb like 'is' or 'do' or 'did';
##   vars are set by $true (t) or $false (null string), test with: [[ $is_OK ]]
##
## A variable/function that's only used by nearby (or limited scope)
##   variable/functions has a name prefixed by '_' (e.g. _chr, defined below);
## an exception is _set-foo, which can be a lightweight version of set-foo
##   (typically with fewer side-effects).
## A global variable/function that replaces an external version
##   has a name that ends in '_' (e.g. cd_, defined below).
##############################################################################

# ----------------------------------------------------------------------------

##############################################################################
# As setup the environment, errors are problems with libsnap.sh,
# not the calling script.
##############################################################################

_libsnap_exit() {

	if [[ $(type -t exit_normally) == function ]]
	   then exit_normally "$@"
	   else        exit "$@"
	fi
}

# to announce errors in this script
function _warn() { echo -e "\n$0: source libsnap.sh: $*\n" >&2; return 1; }
_abort() {
	_warn "$*"
	[[ $is_sourced_by_interactive_shell ]] && return 1
	_libsnap_exit 1
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

# basename of calling script, we won't change caller's value
: ${our_name:=${0##*/}}		# user can change before or after source us
: ${our_name:=${our_name%.~*~}}

readonly true=t True=t
readonly false= False=

case $our_name in
    ( bash | csh | ksh | scsh | sh | tcsh | zsh )
	  is_sourced_by_interactive_shell=$true  ;;
    ( * ) is_sourced_by_interactive_shell=$false ;;
esac

[[ ! $is_sourced_by_interactive_shell ]] &&
[[     $BASH_VERSION <  4.4 ]] &&
_abort "bash version >= 4.4 must appear earlier in the PATH than an older bash"
# 4.3: [[ -v array[i] ]] ; globasciiranges; negative subscripts count backwards
# 4.4: executing RHS of && or || won't cause shell to fork (lose side-effects)

shopt -s globasciiranges		# so weird locales don't mess us up

# set -x: if command in /home/, precede by ~ (yourself) else ~other-user .
# this logic for the first-half of PS4 is duplicated in print-call-stack
PS4='+ $(echo ${BASH_SOURCE-} | sed "s@^$HOME/@~/@; s@^/home/@~@; s@/.*/@ @")'
PS4+=' line ${LINENO-}, in ${FUNCNAME-}(): '
export PS4

# put $IfRun in front of cmds w/side-effects, so -d means: debug only, simulate
: ${IfRun=}

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
# functions to augment path-style variables
# ----------------------------------------------------------------------------

# return 0 if the passed variable name has been set
function is-set() {
	[[ -v $1 ]] && return 0
	eval "local keys=\${!$1[*]}"
	[[ $keys ]]
}

_foo=
_arr[1]=one
declare -A _map=([A]=1)
is-set _foo || _abort "is-set _foo"
is-set _arr || _abort "is-set _arr"
is-set _map || _abort "is-set _map"

declare -a _Arr
declare -A _Map
is-set _bar && _abort "is-set _bar"
is-set _Arr && _abort "is-set _Arr"
is-set _Map && _abort "is-set _Map"

unset _foo _arr _map _Arr _Map

# ---------------------------------

function is-var() { declare -p $1 &> /dev/null ; }

function is-variable() { is-var "$@"; }

is-var our_path || _abort "have our_path"
is-var NoTeXiSt && _abort "don't have NoTeXiSt"

# ----------------------------------------------------------------------------

# $1 is path variable name, other args are dirs; append dirs one by one
append-to-PATH-var() {
	local do_reverse_dirs=
	[[ $1 == -r ]] && { do_reverse_dirs=1; shift; }
	local  pathname=$1; shift
	[[ -v $pathname ]] ||
	    abort-function "$pathname $1 ... : '$pathname' is not set"
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
prepend-to-PATH-var() {
	local do_reverse_dirs=
	[[ $1 == -r ]] && { do_reverse_dirs=1; shift; }
	local  pathname=$1; shift
	[[ -v $pathname ]] ||
	    abort-function "$pathname $1 ... : '$pathname' is not set"
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
function have-cmd() {

	local _cmd
	for _cmd
	   do	type -t $_cmd > /dev/null && return 0
	done
	return 1
}

function have-command() { have-cmd "$@"; }

have-cmd is-set   || _abort "have is-set"
have-cmd our_path && _abort "don't have func our_path"

# --------------------------------------------

xtrace=				  # in case comment-out first line of function

# exit noisily if missing (e.g. not in PATH) any of the $* commands
need-cmds() {

	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=

	local _cmd is_cmd_missing=
	for _cmd
	    do	have-cmd $_cmd && continue

		echo "$our_name: command '$_cmd' is not in current path."
		is_cmd_missing=1
	done

	[[ $is_cmd_missing ]] && _libsnap_exit 2
	$xtrace
}

need-commands() { need-cmds "$@"; }

# ----------------------------------------------------------------------------

# used to precede a command/function that is not yet ready to run
function not-yet() { warn "'$*' not yet available, ignoring"; }

# ----------------------------------------------------------------------------
# let sysadmin install newer versions of (GNU) commands in /usr/local/*bin
# ----------------------------------------------------------------------------

prepend-to-PATH-var PATH /usr/local/bin /usr/local/sbin

# ----------------------------------------------------------------------------
# Customization for Darwin (MacOS) + Homebrew, precedence over /usr/local/*bin
# ----------------------------------------------------------------------------

[[ $OSTYPE == darwin* ]] && readonly is_darwin=$true || readonly is_darwin=

[[ $OSTYPE == *bsd ]] && readonly is_BSD=$true || readonly is_BSD=$is_darwin

[[ $is_darwin ]] && {

readonly homebrew_install_dir=/usr/local/opt
readonly homebrew_coreutils_bin=$homebrew_install_dir/coreutils/libexec/gnubin

[[ -d $homebrew_coreutils_bin ]] ||
   _abort "you need to install a fairly complete set of GNU utilities with Homebrew; if they're already installed, symlink your Homebrew install directory to $homebrew_install_dir"

prepend-to-PATH-var PATH /usr/local/Cellar/util-linux/*/bin # to grab 'setsid'
prepend-to-PATH-var PATH $homebrew_install_dir/*/libexec/*bin

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
TMPDIR=$tmp_dir				# used by bash

# the root filesystem is read-only while booting, don't get into infinite loop!
# GNU mkdir will fail if $tmp_dir is a symlink
until [[ ! -w /tmp || -d $tmp_dir ]] || mkdir -m 0700 -p $tmp_dir
   do	_warn "deleting $(ls -ld $tmp_dir)"
	rm -f $tmp_dir
done

export TMP=$tmp_dir TMP_DIR=$tmp_dir	# caller can change these

export LC_COLLATE=C			# so [A-Z] doesn't include a-z
export LC_ALL=C				# server needs nothing special

export RSYNC_RSH=ssh

umask 022				# caller can change it

###########################################################################
# define functions that abstract OS/kernel-specific operations or queries #
###########################################################################

# -----------------------------------------------------------------------
# Linux functions for querying hardware; email ${coder-Scott} if fix.   #
# snapback or snapcrypt users can write a replacement in configure.sh . #
# -----------------------------------------------------------------------

function set-FS_type--from-path() {
	local  path=$1
	[[ -e $path ]] || abort "path='$path' doesn't exist"

	if [[ $(df --no-sync | fgrep -w $path) ]]
	   then set -- $(df --output=fstype --no-sync $path)
		FS_type=${!#}
	   else have-cmd lsblk ||
		   abort "fix $FUNCNAME for '$path', email to ${coder-Scott}"
		[[ ! -b $path ]] && local FS_device &&
		    set-FS_device--from-path $path && path=$FS_device
		[[ ! -b $path ]] &&
		    abort-function "$path is not accessible"
		local cmd="lsblk --noheadings --nodeps --output=fstype $path"
		FS_type=$($cmd)		; [[ $FS_type ]] ||
		FS_type=$(sudo $cmd)
	fi

	[[ $FS_type ]] || warn "$FUNCNAME: $path has no discernible filesystem"
}

# ----------------------------------------------------------------------------

function set-inode_size-data_block_size-dir_block_size--from-path() {
	local  path=$1
	[[ -e $path ]] || abort-function "$path: path doesn't exist"

	local FS_type
	set-FS_type--from-path $path || return $?

	local var_name
	for var_name in inode_size data_block_size dir_block_size
	    do	is-var $var_name ||
		declare -g -i $var_name
	done

	case $FS_type in
	   ( ext? )
		local FS_device
		set-FS_device--from-path $path || return 1
		set -- $(sudo tune2fs -l $FS_device |&
				sed -n  -e 's/^Block size://p' \
					-e 's/^Inode size://p'
				_libsnap_exit ${PIPESTATUS[0]})
		local status=$?
		inode_size=${2-} data_block_size=${1-} dir_block_size=${1-}
		[[ $status == 0 ]]
		;;
	   ( xfs  )
		set -- $(xfs_growfs -n $path |
			 sed -n -r -e 's/.* isize=([0-9]+) .*/\1/p'	    \
				   -e '  s/^data .* bsize=([0-9]+) .*/\1/p' \
				   -e 's/^naming .* bsize=([0-9]+) .*/\1/p'
				_libsnap_exit ${PIPESTATUS[0]})
		local status=$?
		inode_size=${1-} data_block_size=${2-} dir_block_size=${3-}
		[[ $status == 0 ]]
		;;
	   (  *   )
		abort "fix $FUNCNAME for '$FS_type', email ${coder-}"
		;;
	esac || abort-function "$path (FS_type=$FS_type) returned $status"
	return $?
}

# ----------------------------------------------------------------------------

declare -i device_KB=0

# snapback users can write a replacement in configure.sh
function set-device_KB--from-block-device() {
	local  dev=$1
	[[ -b $dev ]] || abort "$dev is not a device"

	device_KB=0
	have-cmd lsblk || return 1

	set -- $(lsblk --noheadings --bytes --output=SIZE $dev)
	[[ $# == 1 ]] || abort-function ": specify a partition not whole drive"
	is-var device_KB ||
	declare -g -i device_KB
	device_KB=$(( $1/1024 ))
}

# ----------------------------------------------------------------------------

# snapback or snapcrypt users can write a replacement in configure.sh
set-FS_label--from-FS-device() {
	local  dev=$1
	[[ -b $dev ]] || abort "$dev is not a device"

	[[ set-mount_dir--from-FS-device != ${FUNCNAME[1]} ]] && {
	   set-mount_dir--from-FS-device $dev
	set -- $(grep "[[:space:]]$mount_dir[[:space:]]" /etc/fstab)
	[[ ${1-} == LABEL=* ]] && FS_label=${1#*=} || FS_label=	; }

	# don't use lsblk, it sometimes returns very old labels
	if [[ ! ${FS_label-} ]] && have-cmd blkid
	   then local cmd="blkid $dev |
			   sed -n -r 's@.* LABEL=\"?([^ \"]*)\"? .*@\1@p'"
		eval "FS_label=\$($cmd)"	; [[ $FS_label ]] ||
		eval "FS_label=\$(sudo $cmd)"
	fi

	[[ $FS_label ]] ||
	   abort "you need to fix $FUNCNAME and email it to ${coder-Scott}"
}

# ----------------------------------------------------------------------------

label-drive() {
	local  device=$1 mount_dir=$2
	[[ -b $device ]] || abort "$device is not a device"

	local FS_type FS_label
	set-FS_type--from-path $device

	set-FS_label--from-mount_dir $mount_dir

	case $FS_type in
	   ( ext? ) $IfRun sudo e2label $device $FS_label ;;
	   ( xfs  ) $IfRun sudo xfs_admin -L $FS_label $device ;;
	   (  *   ) abort "fix $FUNCNAME for '$FS_type', email ${coder-}" ;;
	esac || abort-function "$device $mount_dir: returned $? ($FS_type)"
}

# ----------------------------------------------------------------------------

set-FS_device--from-FS-label() {
	local label=$1

	if [[ -d /Volumes ]]		# Darwin?
	   then set-FS_device--from-path /Volumes/$label
		return
	fi

	have-cmd blkid ||
	  abort "you need to fix $FUNCNAME and email it to ${coder-Scott}"

	# -L has a different meaning in older versions, so use old method
	local cmd="blkid -l -o device -t LABEL=$label"
	FS_device=$($cmd)		; [[ $FS_device ]] ||
	FS_device=$(sudo $cmd)

	set-FS_label--from-FS-device $FS_device
	[[ $FS_label == $label ]] ||
	  abort "'blkid' lies: pass device to '$our_name' by-hand"

	[[ $FS_device ]] || abort "couldn't find device for $label"
}

# ----------------------------------------------------------------------------

set-OS_release_file-OS_release() {

	set -- /usr/lib/*-release /etc/*-release
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

set-FS_device--from-path() {
	local  path=$1
	[[ -e $path ]] || { warn "path=$path doesn't exist"; return 1; }

	set -- $(df --output=source --no-sync $path 2> /dev/null)
	[[ $# != 0 ]] || abort-function "couldn't find device for path=$path"
	FS_device=${!#}
	return 0
}

# ----------------------------

function set-mount_dir--from-FS-device() {
	[[ $1 == -q ]] && { local is_quiet=$true; shift; } || local is_quiet=
	local  dev=$1
	[[ -b $dev ]] || abort "$dev is not a device"

	set -- $(df --output=target --no-sync $dev 2> /dev/null)
	[[ $# == 0 ]] && mount_dir= || mount_dir=${!#}
	[[ ! $mount_dir || $mount_dir == / || $mount_dir == /dev ]] ||
	   return 0

	set -- $(grep "^[[:space:]]*$dev[[:space:]]" /etc/fstab)
	mount_dir=${2-}
	[[ $mount_dir ]] && return 0

	local FS_label
	set-FS_label--from-FS-device $dev
	set -- $(grep "^[[:space:]]*LABEL=$FS_label[[:space:]]" /etc/fstab)
	mount_dir=${2-}

	[[ $mount_dir ]] && return 0

	[[ ! $is_quiet ]] && abort "couldn't find mount dir for dev=$dev"
}

# ----------------------------

function set-mount_dir--from-FS-label() {
	local label=$1

	mount_dir=/${label//_/\/}
	[[ -d $mount_dir ]]
}

# -------------------------------

set-FS_label--from-mount_dir() {
	local mount_dir=$1

	FS_label=${mount_dir#/}
	FS_label=${FS_label//\//_}
}


# ----------------------------------------------------------------------------
# miscellaneous function(s) needed by next section
# ----------------------------------------------------------------------------

# does 1st argument match any of the whitespace-separated words in rest of args
function is-arg1-in-arg2() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	local arg1=$1; shift
	local arg2=$*
	[[ $arg1 && $arg2 ]] || { $xtrace; return 1; }

	[[ " $arg2 " == *" $arg1 "* ]]
	local status=$?
	$xtrace
	return $status
}

is-arg1-in-arg2 foo "" && _abort "null arg2 means false"
is-arg1-in-arg2 foo    && _abort   "no arg2 means false"

# ----------------------------------------------------------------------------
# simple error and warning and trace functions.
# don't assign these until all the environment setup is finished, otherwise
#   a login shell might source it and be terminated by abort's exit. 
# ----------------------------------------------------------------------------

declare -i max_call_stack_args=6

# if interactive, want to avoid these extdebug warnings:
#    bash: /usr/share/bashdb/bashdb-main.inc: No such file or directory
#    bash: warning: cannot start debugger; debugging mode disabled
[[ $is_sourced_by_interactive_shell ]] ||
shopt -s extdebug			# enable BASH_ARGV and BASH_ARGC

print-call-stack() {
	set +x
	declare -i stack_skip=1
	[[ ${1-} ==   -s  ]] && { stack_skip=$2+1; shift 2; }
	[[ ${1-} == [0-9] ]] && { (( Trace_level >= $1 )) || return; shift; }

	local  _date_time=$(date "$log_date_format")
	_date_time=${_date_time#* }
	header -E "$_date_time call stack $*"	# include optional message
	# declare -p BASH_ARGV BASH_ARGC	# uncomment to debug
	local -i depth arg_i argv_i=0 max_args=$max_call_stack_args
	for depth in ${!FUNCNAME[*]}
	   do	(( depth < stack_skip )) && 
		    { argv_i+=${BASH_ARGC[depth]}; continue; } # skip ourself
		# this logic is duplicated in PS4
		local src=$(echo ${BASH_SOURCE[depth]} |
				sed "s@^$HOME/@~/@; s@^/home/@~@; s@/.*/@ @")
		local args=
		local -i argc=${BASH_ARGC[depth]} number_args=0
		for (( arg_i=argv_i+argc-1; arg_i >= argv_i; arg_i-- ))
		    do	local arg=${BASH_ARGV[arg_i]}
			[[ $arg == *[\	\ ]* ]] && arg="'$arg'"
			args+="$arg "
			(( argc > max_args+1 )) || continue
			# we never want to say "<1 more args>"
			(( ++number_args == max_args-2 )) &&
			   arg_i=argv_i+2 &&
			   args+="<$((argc-max_args)) more args> "
		done
		let argv_i+=argc
		echo -n "$src line ${BASH_LINENO[depth-1]}: "
		echo    "${FUNCNAME[depth]} ${args% }"
	done
	echo
}

# --------------------------------------------

function warn() {
	local msg="$our_name: $*"

	if [[ ${FUNCNAME[1]-} == abort ]]
	   then local level=error
	   else local level=warning
	fi
	[[ -t 2 ]] && set-warning_string $level "$msg" && msg=$warning_string
	echo -e "\n$msg\n" >&2
	return 1
}

# ---------------------------------

: ${master_PID=$BASHPID}

abort() {
	set +x
	[[ ${1-} == -r ]] && { shift; is_recursion=$true; } || is_recursion=
	declare -i stack_skip=1
	[[ ${1-} =~ ^-[0-9]+$ ]] && { stack_skip=${1#-}+1; shift; }

	if [[ $is_recursion ]]
	   then echo "$@" ; let stack_skip+=1
	elif [[ ${Usage-} && "$*" == "$Usage" ]]
	   then echo "$@" >&2 ; _libsnap_exit 1
	   else	warn "$@"
	fi

	print-call-stack -s $stack_skip >&2

	[[ ! $is_recursion ]] &&
	   log "$(master_PID=$BASHPID abort -r $* 2>&1)" > /dev/null

	if [[ $master_PID != $BASHPID ]] # are we in a sub-shell?
	   then trap '' TERM		 # don't kill ourself when ...
		kill -$master_PID	 # kill our parent and its children
		sleep 1
		kill -9 -$master_PID
	fi
	_libsnap_exit 1
}

# ---------------------------------

abort-function() {
	set +x
	declare -i stack_skip=1
	[[ ${1-} =~ ^-[0-9]+$ ]] && { stack_skip=${1#-}+1; shift; }
	local opts= ; while [[ ${1-} == -* ]] ; do opts+=" $1"; shift; done

	[[ $1 == ':'* ]] && local msg=$* || local msg=" $*"
	abort -$stack_skip $opts "${FUNCNAME[$stack_skip]}$msg"
}
readonly -f abort-function

# --------------------------------------------

assert-not-option() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	[[ ${1-} == -o ]] && { local order_opt=$1; shift; } || local order_opt=
	[[ ${1-} != -? ]] && { $xtrace; return; }

	[[ $order_opt ]] && msg=" (order matters)" || msg=
	abort -1 "${FUNCNAME[1]}: unknown option $1$msg"
}

# ----------------------------------------------------------------------------

# echo to stdError, include the line and function from which we're called
echoE () {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	[[ $1 == -n ]] && { local show_name=$true; shift; } || local show_name=
	declare -i stack_frame_to_show=1 # default to our caller's stack frame
	[[ $1 =~ ^-[0-9]+$ ]] && { stack_frame_to_show=${1#-}+1; shift; }
	assert-not-option -o "${1-}"

	local   line_no=${BASH_LINENO[stack_frame_to_show-1]}
	local func_name=${FUNCNAME[stack_frame_to_show]}
	[[   $func_name ]] && func_name="line $line_no, in $func_name():"

	[[ $show_name ]] && local name="$our_name:" || local name=
	echo -e $name $func_name "$@" >&2
	$xtrace
}

# ----------------------

function is-readonly-var() {
	is-var $1 && [[ $(declare -p $1) =~ ' '-[a-zA-Z]*r ]]
}

function is-readonly-variable() { is-readonly-var "$@"; }

# ----------------------

function is-writable-var() {
	is-var $1 && ! is-readonly-var $1
}

function is-writable-variable() { is-writable-var "$@"; }

# ----------------------

function is-integer-var() {
	is-var $1 && [[ $(declare -p $1) =~ ' '-[a-zA-Z]*i ]]
}

function is-integer-variable() { is-integer-var "$@"; }

is-writable-var our_path && _abort "our_path is a readonly var"

declare -i _int_var
declare    _str_var
is-writable-var _int_var &&
 is-integer-var _int_var || _abort "_int_var is writable int var"
 is-integer-var _str_var && _abort "_str_var is not an int var"
is-readonly-var _str_var && _abort "_str_var is not readonly var"
unset _int_var _str_var

# --------------------------------

is-integer() { [[ $1 =~ ^-?[0-9]+$ ]] ; }

is-integer -123 || _abort "-123 is an integer"
is-integer  123 || _abort  "123 is an integer"
is-integer  1.3 && _abort  "1.3 is not an integer"

# ----------------------

set-var_value--from-var_name() {
	local var_name=$1

	if is-set $var_name
	   then var_value=${!var_name}
	   else var_value='<unset>'
	fi

	[[ $var_value == *[\ \	]* ]] && var_value="'$var_value'"

	is-integer-variable $var_name &&
	var_value="$var_value	# integer variable"
}

# ----------------------

# like echoE, but also show the values of the variable names passed to us
echoEV() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	declare -i stack_frame_to_show=1 # default to our caller's stack frame
	[[ $1 =~ ^-[0-9]+$ ]] && { stack_frame_to_show=${1#-}+1; shift; }
	assert-not-option "${1-}"

	local var_name var_value
	for var_name
	   do	set-var_value--from-var_name $var_name

		echoE -$stack_frame_to_show "$var_name=$var_value"
	done >&2
	$xtrace
}

# ----------------------

declare -i Trace_level=0		# default to none (probably)

_isnum() { [[ $1 =~ ^[0-9]+$ ]] ||abort -2 "Trace* first arg is (min) level"; }
Trace () { _isnum $1; (($1 <= Trace_level)) ||return 1;shift; echoE  -1 "$@"; }
TraceV() { _isnum $1; (($1 <= Trace_level)) ||return 1;shift; echoEV -1 "$@"; }

# ----------------------------------------------------------------------------

declare -A funcname2was_tracing		# global for next three functions

function remember-tracing {

	local status=$?			# status from caller's previous command
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=

	funcname2was_tracing[ ${FUNCNAME[1]} ]=$xtrace

	$xtrace
	return $status
}

# ----------------------

function suspend-tracing {

	local status=$?			# status from caller's previous command
	if [[ -o xtrace ]]
	   then set +x
		local was_tracing=$true
	   else local was_tracing=$false
	fi
	funcname2was_tracing[ ${FUNCNAME[1]} ]=$was_tracing
	return $status
}

# ----------------------

# show the values of the variable names passed to us, then restore traing state
function restore-tracing {

	local status=$?			# status from caller's previous command
	is-arg1-in-arg2 ${FUNCNAME[1]} ${!funcname2was_tracing[*]} ||
	   abort-function "was called without a suspend-tracing"
	[[ ${funcname2was_tracing[ ${FUNCNAME[1]} ]} ]] || return $status

	local variable
	for variable
	    do	if [[ -v $variable ]]
		   then echo "+ $variable=${!variable}"
		   else echo "+ $variable is not set"
		fi
	done

	set -x
	return $status
}

wont-trace() {         foo=2
	       suspend-tracing; echo untraced; restore-tracing foo; }
will-trace() { set -x; foo=1
	       suspend-tracing; echo untraced; restore-tracing foo
	       wont-trace; echo traced; set +x; }
[[ $(will-trace 2>&1) == *' echo untrac'* ]] && _abort "suspend-tracing failed"
[[ $(will-trace 2>&1) == *' echo traced'* ]] || _abort "restore-tracing failed"
unset -f wont-trace will-trace

# ----------------------------------------------------------------------------

print-or-egrep-Usage-then-exit() {
	[[ ${1-} == -[hHk] ]] && shift	# strip help or keyword-search option
	[[ $# == 0 ]] && echo -e "$Usage" && _libsnap_exit 0

	echo "$Usage" | egrep -i "$@"
	_libsnap_exit 0
}

# ---------------------------------

abort-with-action-Usage() {
	local _action=${*:-$action}

	echo -e "\nBad arguments; here's the usage for this action:"
	echo "$Usage" | grep "^ *$_action" >&2; echo
	_libsnap_exit 1
}

# ---------------------------------

# RunCmd's args are a command (plus args) that _should_ return 0, else we abort
RunCmd() {
	[[ $1 == -d ]] && { local IfAbort=$IfRun; shift; } || local IfAbort=
	[[ $1 == -m ]] && { local msg="; $2"; shift 2; } || local msg=
	assert-not-option -o "${1-}"

	$IfRun "$@" || $IfAbort abort -1 "'$*' returned $?$msg"
}

RunCmd true &&
[[ $(master_PID=$BASHPID \
     RunCmd -d -m "expected (non fatal)" false 2>&1) == *'(non fatal)'* ]] ||
   _abort "RunCmd error"

# ----------------------------------------------------------------------------
# Generic logging function, with customization globals that caller can set.
# ----------------------------------------------------------------------------

: ${log_date_format:="+%a %m/%d %H:%M:%S"} # caller or environment can change

file_for_logging=/dev/null		# append to it; caller can change

declare -i log_level=0			# set by getopts or configure.sh

log_msg_prefix=				# can hold variables, it's eval'ed

function log() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	[[ $1 == [0-9] ]] && { local level=$1; shift; } || local level=0
	local _msg="$*"

	(( $level <= $log_level )) || { $xtrace; return 1; }

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
	assert-not-option -o "${1-}"

	echo -e "==> $* <==$nl"
	$xtrace
}

# ----------------------------------------------------------------------------
# funcs to highlight strings & workaround printf's lack of terminfo knowledge
# ----------------------------------------------------------------------------

# http://www.tldp.org/HOWTO/Bash-Prompt-HOWTO/x405.html
print-string-colors() {

	header "Coloring from arguments passed to 'tput' command, see man page"
	local n
	for n in {1..8}
	    do	local line=
		local capname
		for capname in setab setb setaf setf
		    do	line+="$(tput $capname $n)$capname $n$(tput sgr0)   "
		done
		echo "$line"
	done
}

# ---------------------------------

# main script can over-ride the following global variables after source us

# the setb coloring stands out more, but fails under 'watch' on some OSs
declare -A warning_level2tput_b_args=(
         [ok]="setb 2"
    [warning]="setb 6"
      [error]="setb 4"
      [stale]="setb 1"
)
declare -A warning_level2tput_args=(
         [ok]="setf 2"
    [warning]="setf 5"
      [error]="setf 4"
      [stale]="setf 3"
)
declare -A warning_level2tput_args=(
         [ok]="setaf 2"
    [warning]="setaf 5"
      [error]="setab 1"			# setaf is less "striking"
      [stale]="setaf 3"
)
clear_tput_args="sgr0"

declare -A warning_level2escape_sequence

set-warning_string() {
	local level=$1; shift; local string=$*
	is-arg1-in-arg2 $level ${!warning_level2tput_args[*]} ||
	   abort-function "$level is unknown level"

	[[ -t 1 || ${do_tput-} ]] || { warning_string=$string; return; }

	local esc=${warning_level2escape_sequence[$level]=$(
		tput ${warning_level2tput_args[$level]})}
	: ${clear_escape_seq=$(tput $clear_tput_args |
		sed 's/\x1B(B//')}	# need to toss leading ESC ( B
	[[ ${terminfo_color_bytes-} ]] ||
	   declare -g -r -i \
		   terminfo_color_bytes=$(( ${#esc} + ${#clear_escape_seq} ))

	warning_string=$esc$string$clear_escape_seq
}

# ----------------------------------------------------------------------------

# "printf %7s" doesn't handle terminfo escape sequence
# printf strips trailing SPACES; so pad with '_', and replace them later
set-padded_colorized_string--for-printf() {
	[[ $# == [23] ]] || abort-function "need 2-3 args"
	local string=$1 colorized_string=$2
	declare -i field_width=${3-4} # default: dashboard strings <= 4B wide

	[[ -t 1 || ${do_tput-} ]] || { padded_colorized_string=$string; return; }

	padded_colorized_string=$colorized_string
	declare -i pad_count=$terminfo_color_bytes
	(( ${#string} + $pad_count <= $field_width )) ||
	    pad_count=field_width-${#string}
	declare -i n
	for (( n=1; n <= pad_count; n+=1 ))
	    do	padded_colorized_string+='_'
	done
}

# -------------------

fix-padded-colorized-string-vars() {

	local var_name
	for var_name
	    do	local value=${!var_name}
		value=${value//_/ }	# rewrite padding
		eval "$var_name=\$value"
	done
}

# ----------------------------------------------------------------------------
# miscellaneous functions
# ----------------------------------------------------------------------------

is-older() { [[ -e $1 && -e $2 && $1 -ot $2 ]] ; }
is-newer() { [[ -e $1 && -e $2 && $1 -nt $2 ]] ; }

# ----------------------------------------------------------------------------

is-an-FS-device-mounted() {
	local mount_dir=$1

	set -- $(df --output=target --no-sync $mount_dir 2> /dev/null)
	[[ ${!#} == $mount_dir ]]
}

is-an-FS-device-mounted / || _abort "can't find mounted root device"

# ----------------------------------------------------------------------------

function set-absolute_dir() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	[[ $# == 1 ]] || abort "Usage: $FUNCNAME filename" ||
	    { $xtrace; return 1; }
	local name=$1

	[[ -d "$name" ]] || name=$(dirname "$name")
	absolute_dir=$(cd "$name" && /bin/pwd) # simpler than readlink(s)
	$xtrace
	[[ $absolute_dir && -d $absolute_dir ]]
}

# -------------------------------------------------------

function set-absolute_path() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	[[ $# == 1 ]] || abort "Usage: $FUNCNAME filename" ||
	    { $xtrace; return 1; }
	local name=$1

	local absolute_dir
	set-absolute_dir "$name"
	  if [[ -d "$name" ]]
	   then absolute_path=$absolute_dir
	elif [[ -L "$name" ]]
	   then set-absolute_path $absolute_dir/$(readlink "$name")
	   else     absolute_path=$absolute_dir/$(basename "$name")
	fi
	$xtrace
	[[ -e $absolute_path ]]
}

# ----------------------------------------------------------------------------

cd_() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	(( $# <= 1 )) || abort-function "$*: wrong number args"
	local _dir=${1-$HOME}

	cd "$_dir" || abort "cd $_dir"
	# -n and -z needed here for buggy 2.04 version of bash (in RHL 7.1)
	if [[ ( -n $IfRun || -n ${do_show_cd-} ) && -z ${Trace-} ]]
	   then local _msg="cd $PWD"
		[[ $_dir == */.* && $_dir != /* ]] && _msg="$_msg # $_dir"
		echo "$_msg"
	fi
	$xtrace
}

# ----------------------------------------------------------------------------

# for each field, assign that field's value to a variable named for that field
setup-df-data-from-fields() {
	local drive=$1; shift
	local fields=$*

	if ! [[ -b $drive || -d $drive ]]
	    then local ls_msg=$(ls -ld $drive 2>&1)
		 warn ": first arg must be device or directory:\n   $ls_msg"
		 return 1
	fi

	set -f; set -- ${fields//,/ }; set +f
	fields=$*
	local -i field_count=$#

	set -f; set -- $(df --output=${fields// /,} --no-sync $drive/.); set +f
	[[ $# != 0 ]] || abort-function "'df $drive' failed"
	while (( $# > $field_count )) ; do shift; done

	local name
	for name in $fields
	    do	local value=${1%\%}	# remove any trailing '%'
		if is-integer $value && ! is-var $name
		   then eval "declare -g -i $name=\$value"
		   else eval		   "$name=\$value"
		fi
		shift
	done
	return 0
}

# ----------------------------------------------------------------------------

function set-file_KB() {
	local _file=$1

	set -- $(ls -sd $_file)
	is-var file_KB ||
	declare -g -i file_KB
	file_KB=$1
	[[ $file_KB ]]
}

# ----------------------------------------------------------------------------

function have-proc { [[ -e /proc/mounts ]] ; }

# ---------------------------------

# return 0 if all processes alive, else 1; unlike 'kill -0', works without sudo
function is-process-alive() {
	local PIDs=$*

	local PID
	for PID in $PIDs
	    do	PID=${PID#-}		# in case passed PGID indicator
		if have-proc
		   then [[ -d /proc/$PID ]]  || return 1
		   else ps $PID &> /dev/null || return 1
		fi
	done
	return 0
}

is-process-alive $$ $BASHPID || _abort "is-process-alive failure"

# ----------------------------------------------------------------------------

set-reversed_words() {

	reversed_words=
	local word
	for word
	   do	reversed_words="$word $reversed_words"
	done
	reversed_words=${reversed_words% }
}

set-reversed_words     1 2 3
[[ $reversed_words == "3 2 1" ]] || _abort "reversed_words='$reversed_words'"
unset reversed_words

# ----------------------------------------------------------------------------

function set-is_FIFO() {
	local arg=${1-}

	[[ $arg == -[^fqls] ]] &&
	    abort-function -1 "only allows these options: -f -q -l -s"

	is_FIFO=$true			 # default, also called queue
	[[ $arg ==  -[fqls] ]] || return 1

	[[ $1 == -f ]] && is_FIFO=$true	 # FIFO  aka queue
	[[ $1 == -q ]] && is_FIFO=$true	 # Queue aka FIFO
	[[ $1 == -l ]] && is_FIFO=$false # LIFO  aka stack
	[[ $1 == -s ]] && is_FIFO=$false # Stack aka LIFO
	return 0
}

# ---------------------------------

# pop word off left side of named list; return non-0 if list was empty
function set-popped_word-is_last_word--from-list() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	set-is_FIFO ${1-} && shift
	[[ $# == 1 ]] || abort-function ": pass name of list"

	local  list_name=$1
	[[ -v $list_name ]] || abort-function "$1: '$1' is not set"
	set -f; set -- ${!list_name}; set +f # split words apart
	[[ $# == 1 ]] && is_last_word=$true || is_last_word=$false
	[[ $# == 0 ]] && popped_word= ||
	if [[ $is_FIFO ]]
	   then popped_word=${1-}; shift # pop left-most word
	   else popped_word=${!#}; set -f; set -- ${*%$popped_word}; set +f
	fi
	eval "$list_name=\$*"		# retain the rest of the words
	$xtrace
	[[ $popped_word ]]
}

_numbers="1 2 3"
  _input=$_numbers
  _words=
  _flags=
while set-popped_word-is_last_word--from-list _input
   do	_words+=" $popped_word"
	_flags+=" $is_last_word"
done
[[ $_flags == *" $true" ]] || _abort "is_last_word should be set last: $_flags"
_words=${_words# }
_flags=${_flags// /}
[[ ! $_input && $_words == "$_numbers" ]] ||
    _abort "set-popped_word-is_last_word--from-list failure: _input='$_input' _words='$_words'"
[[ $_flags == $true ]] || _abort "is_last_word should be set once: $_flags"

  _input=$_numbers
  _words=
while set-popped_word-is_last_word--from-list -l _input
   do	_words="$popped_word $_words"
done
 _words=${_words% }
[[ ! $_input && $_words == "$_numbers" ]] ||
    _abort "set-popped_word-is_last_word--from-list failure: _input='$_input' _words='$_words'"

unset _numbers _input _words popped_word is_last_word

# ----------------------------------------------------------------------------

set-division() {
	[[ $# == 3 && $1 =~ ^-?[1-9]$ && $2$3 =~ ^[-0-9]+$ ]] || # -0 is hard
	    abort-function \
		 decimal-digits=${1-}  numerator=${2-} denominator=${3-} ${4-}
	local -i decimal_digits=${1#-} numerator=$2    denominator=$3
	[[ $denominator =~ ^[1-9][0-9]*$ ]] ||
	    abort-function "denominator must be a counting number"

	local format="%s.%0${decimal_digits}d"

	local -i multiplier=10**decimal_digits
	local -i whole_number=$((numerator / denominator))
	local -i fraction=$(( ( multiplier*(numerator % denominator)
				+ (denominator / 2) ) / denominator ))
	if (( fraction >= multiplier ))	# fraction rounded up to whole number?
	   then let whole_number+=1
		fraction=0
	fi

	printf -v division "$format" $whole_number $fraction
}

# test minutes to hours
set-division -2 10 60 ; [[ $division == 0.17 ]] || _abort "10/60 != $division"
set-division -1 10 60 ; [[ $division == 0.2  ]] || _abort "10/60 != $division"
set-division -1 59 60 ; [[ $division == 1.0  ]] || _abort "59/60 != $division"
unset division

# ----------------------------------------------------------------------------

function confirm() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	[[ $1 == -n  ]] && { echo; shift; }
	assert-not-option "$1"
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

	[[ $status ]] || abort-function "$*: read failure"
	$xtrace
	return $status
}

# --------------------------------------------

assert-sha1sum() {
	local sha1sum=$1 file=${2-}

	set --  $(sha1sum $file)
	[[ $1 == $sha1sum ]] && return
	abort    "sha1sum($file) != $sha1sum"
}

# ----------------------------------------------------------------------------

# Test an internal function by passing its name + options + args to our script;
# to show values of global variables it alters, pass: -v "varname(s)"
function run-function() {
	local is_procedure=$false	# abort if function "fails"
	[[ $1 == -p ]] && { is_procedure=$true; shift; }
	[[ $1 == -v ]] && { local var_names=$2; shift 2; } || local var_names=
	assert-not-option -o "${1-}"

	have-cmd $1 || abort "function '$1' doesn't exist"

	"$@"
	local status=$?
	[[ $var_names ]] && echoEV -1 ${var_names//,/ }
	[[ $status == 0 || $is_procedure ]] || abort -1 "'$*' returned $status"
	return $status
}

# ----------------------------------------------------------------------------

function pegrep() { grep --perl-regexp "$@"; }

# ----------------------------------------------------------------------------
# create and rewrite files
# ----------------------------------------------------------------------------

copy-file-perms() {
	[[ $1 == -D ]] && local mkdir_opt=-p
	[[ $1 == -d ]] && local mkdir_opt=
	[[ $1 == -[dDf] ]] && { local opt=$1; shift; } || local opt=
	assert-not-option "$1"
	local reference=$1; shift

	local path sudo=
	for path
	    do	if [[ $opt == -f ]]
		   then if [[ -e "$path" ]]
			   then [[ -w "$path" ]] || sudo=sudo
				[[ -f "$path" ]] || abort "'$path' not a file"
			   else [[ -w "${path%/*}" ]] || sudo=sudo
				$IfRun $sudo touch "$path"
			fi
		elif [[ $opt == -[dD] ]]
		   then if [[ -e "$path" ]]
			   then [[ -w "$path" ]] || sudo=sudo
				[[ -d "$path" ]] || abort "'$path' not a dir"
			   else [[ -w "${path%/*}" ]] || sudo=sudo
				$IfRun $sudo mkdir $mkdir_opt "$path"
			fi
		elif [[ ! -e "$path" ]]
		   then abort-function ": '$path' doesn't exist, & no options"
		fi || abort-function ": couldn't create '$path'"

		local cmd
		for cmd in chown chmod
		    do	$IfRun $sudo $cmd --reference="$reference" "$path"
		done
	done
}

# ----------------------------------------------------------------------------

# return non-0 if din't find any emacs backup files
function set-backup_suffix--for-emacs() {
	[[ $# == 1  ]] || abort-function ": specify a single file"
	local  path=$1
	[[ -f $path ]] || abort-function ": '$path' not file, or doesn't exist"

	local -i max_num=0
	local backup
	for backup in $path.~[1-9]*~
	   do	[[ $backup =~ ~([1-9][0-9]*)~$ ]] || continue
		local -i num=${BASH_REMATCH[1]}
		(( max_num < num )) &&
		   max_num=$num
	done

	(( max_num == 0 )) && local status=1 || local status=0
	let max_num+=1
	backup_suffix=.~$max_num~

	return $status
}

# ---------------------------------

# this is for 'sed --in-place[=SUFFIX]' or 'perl -i[extension]'
set-backup_suffix() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=

	set-backup_suffix--for-emacs "$@" || backup_suffix='~'
	$xtrace
}

# ----------------------------------------------------------------------------

function does-file-end-in-newline() {

	local file
	for file
	    do	[[ -f $file && -s $file ]] || return 1
		[[ $(tail -c 1 $file) ]] && return 1
	done
	return 0
}

# ----------------------------------------------------------------------------

merged-continuation-lines() {

	# https://catonmat.net/sed-one-liners-explained-part-one
	sed -e :a -e '/\\$/N; s/\\\n//; ta' "$@"
}

# ----------------------------------------------------------------------------

set-cat_cmd() {
	local filename=$1

	case ${filename##*.} in
	    ( bz2 ) cat_cmd=bzcat ;;
	    ( gz  ) cat_cmd=zcat  ;;
	    ( xz  ) cat_cmd=xzcat ;;
	    ( *   ) cat_cmd=cat   ;;
	esac
}

# ----------------------------------------------------------------------------

# strip leading tabs (shell script's indent) from $1, and expand remaining tabs
set-python_script() {
	[[ $# == 1 ]] || abort-function "takes one arg, got $#" || return 1
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

# ----------------------------------------------------------------------------

true					# we must return 0
