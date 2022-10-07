#! /usr/bin/env bash
# shellcheck disable=SC1007,SC2004,SC2015,SC2034,SC2128,SC2196,SC2197
# disable SC2004: emacs doesn't colorize variables not preceded by a '$'

readonly libsnap_version=1

#     libsnap.sh is a library used by snap aka snapshot, snapback, & snapcrypt
#
#     Copyright (C) 2018-2022, Human Rights Data Analysis Group (HRDAG)
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
##    set-foo-		# ... minus checks (already done); fewer side-effects?
##    set-foo-alias	# ...... alias, uses in-scope variables for its work
##    set-foo-a		# ......... alternative naming, to keep name short
##    set-foo-foo_bar	# sets variable foo and also sets variable foo_bar
##    set-foo--from-xxx	# sets variable foo ... using method/variable xxx
##    setup-foo-vars	# sets numerous variables related to foo
## If "set-*" is replaced by "update-" or "append-to-" or "prepend-to-",
##    the (initialized) variable(s) are updated rather than set;
##    the designator might be preceded by "did-" (returns 1 if already set).
## The function 'run-function' will display the variables in function nqames.
##
## A function named "func-" is a faster version of "func" w/out error checking.
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
## A global variable/function that replaces an external version
##   has a name that ends in '_' (e.g. cd_, defined below).
##############################################################################

# ----------------------------------------------------------------------------

##############################################################################
# As setup the environment, errors are problems with libsnap.sh,
# not the calling script.
##############################################################################

_libsnap-exit() {

	if type -t exit-normally > "$dev_null"
	   then exit-normally "$@"
	   else exit	      "$@"
	fi
}

# to announce errors in this script
function _warn() {
	[[ ${_do_run_unit_tests-} ]] && local file=${0##*/} || local file=$0
	[[ ${FUNCNAME[1]-} == _abort ]] && local -i i=1 || local -i i=0
	echo -e "\n$file line ~${BASH_LINENO[i]}: $*\n" >&2
	return 1
}
function _abort() {
	set +x
	_warn "$*"
	[[ ${is_sourced_by_interactive_shell-} ]] && return 1
	_libsnap-exit 1
}

# ----------------------------------------------------------------------------
# setup global variables for calling script
# ----------------------------------------------------------------------------

readonly true=t false=

our_path=${BASH_ARGV0-${0#-}}
[[ $our_path == */* ]] || our_path=$(type -p "$our_path")
[[ $our_path == ./* ]] && our_path=${0#./}
[[ $our_path ==  /* ]] || our_path=$PWD/$our_path

[[ -v dev_null ]] ||
readonly dev_null=/dev/null

# we might have been run as a script to create $tmp_dir (see above)
if [[ $our_path == */libsnap.sh ]]
   then [[ $# == 0 ]] && exit 0
	# shellcheck disable=SC2048
	[[ $* == -r ]]  || _abort "only -r (run regression tests) is supported"
	[[ $UID != 0 ]] || _abort "don't run as root with -r"

	! type -t shellcheck > $dev_null || shellcheck "$our_path" || exit 1
	set -u				# for unit tests
	_do_run_unit_tests=$true	# ~100 milliseconds
   else _do_run_unit_tests=$false	#  ~10 milliseconds
fi

# basename of calling script, we won't change caller's value
if [[ ! ${our_name-} ]]
   then our_name=${0##*/}
	our_name=${our_name%.~*~}
	our_name=${our_name%%\~}
fi				   # not marked readonly, caller can change it

case $our_name in
    ( bash | csh | dash | ksh | scsh | sh | tcsh | zsh )
	  is_sourced_by_interactive_shell=$true ;    unset our_path ;;
    ( * ) is_sourced_by_interactive_shell=$false; readonly our_path ;;
esac

# shellcheck disable=SC2072
[[ ! $is_sourced_by_interactive_shell ]] &&
[[     $BASH_VERSION <  4.4 ]] &&
_abort "bash version >= 4.4 must appear earlier in the PATH than an older bash"
# 4.3: [[ -v array[i] ]] ; globasciiranges; negative subscripts count backwards
# 4.4: executing RHS of && or || won't cause shell to fork (lose side-effects)

shopt -s expand_aliases			# x-return, alternate function names
shopt -s globasciiranges		# so weird locales don't mess us up
shopt -s lastpipe			# don't fork last cmd of pipeline

# set -x: if command in /home/, precede by ~ (yourself) else ~other-user .
# This logic for the first-half of PS4 is duplicated in print-call-stack .
PS4='+ $(sed "s@^$HOME/@~/@; s@^/home/@~@; s@/.*/@ @" <<<"${BASH_SOURCE-}")'
PS4+=' line ${LINENO-}, in ${FUNCNAME-main}: '
export PS4

# put $IfRun in front of cmds w/side-effects, so -d means: debug only, simulate
[[ -v IfRun ]] || IfRun=

readonly lockpid_busy_exit_status=123	# also in src/lockpid/lockpid.c

#############################################################################
#############################################################################
### Helper utilities to manipulate the PATH.
#############################################################################
#############################################################################

# return 0 if the passed variable name has been set
function is-set() {
	[[ $# == 1 ]] || abort-function "var-name"
	[[ -v $1 ]] && return 0
	eval "[[ \${!$1[*]} ]]"
}

[[ $_do_run_unit_tests ]] && {
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
}

# ---------------------------------

# [[ -v $1 ]] requires $1 to be set, is-var just requires a declaration
function is-var() {
	[[ $# == 1 ]] || abort-function "var-name"
	declare -p "$1" &> $dev_null
}

alias is-variable=is-var

[[ $_do_run_unit_tests ]] && {
declare -i _foobar_
is-var _foobar_ || _abort "have _foobar_"
is-var our_name || _abort "have our_name"
is-var NoTeXiSt && _abort "don't have NoTeXiSt"

is-variable _foobar_ || _abort "alias: have _foobar_"
is-variable our_name || _abort "alias: have our_name"
is-variable NoTeXiSt && _abort "alias: don't have NoTeXiSt"
}

# ----------------------------------------------------------------------------
# functions to augment path-style variables
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

#############################################################################
#############################################################################
### Create a PATH that provides priority access to full GNU utilities.
### While we're at it, provide some OS-specific routines.
#############################################################################
#############################################################################

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

readonly homebrew_install_dir=$(brew --prefix)/opt
readonly homebrew_coreutils_bin=$homebrew_install_dir/coreutils/libexec/gnubin

[[ -d $homebrew_coreutils_bin ]] ||
   _abort "you need to install a fairly complete set of GNU utilities with Homebrew; if they're already installed, symlink your Homebrew install directory to $homebrew_install_dir"

prepend-to-PATH-var PATH /usr/local/Cellar/util-linux/*/bin # to grab 'setsid'
prepend-to-PATH-var PATH $homebrew_install_dir/*/libexec/*bin

}

# ----------------------------------------------------------------------------

function set-mounts {

	local mounts_path=/proc/mounts
	if [[ -f $mounts_path ]]	# FreeBSD doesn't have this
	   then read -d '\0' -r mounts < "$mounts_path"
	   else mounts=$(mount)
	fi
}

# ----------------------------------------------------------------------------

# ps_opt_H: (h)ierarchy (forest)
# ps_opt_f: ASCII-art (f)orest
# ps_opt_h: no (h)eader
# ps_opt_g: all IDs are PGIDs, i.e. process (g)roup IDs
# shellcheck disable=SC2120 # we merely make sure we get no args
setup-ps-options() {
	[[ $# == 0 ]] || abort-function "takes no arguments"

	[[ -v ps_opt_g ]] && return

	# set variables that map Linux's 'ps' options to random OS's 'ps' opts
	case $OSTYPE,$is_BSD in
	    ( linux* ) ps_opt_H=-H  ps_opt_f=f   ps_opt_h=h  ps_opt_g=-g ;;
	    (*,$true ) ps_opt_H=-d  ps_opt_f=-d  ps_opt_h=   ps_opt_g=-G ;;
	    (   *    ) ps_opt_H=    ps_opt_f=    ps_opt_h=   ps_opt_g=-G ;;
	esac; readonly ps_opt_H     ps_opt_f	 ps_opt_h    ps_opt_g
}

#############################################################################
#############################################################################
### We now have a PATH that provides priority access to full GNU utilities.
### Setup the environment, define utility functions needed for next section.
#############################################################################
#############################################################################

# ----------------------------------------------------------------------------
# we want some loadable builtins (the ones that aren't buggy)
# ----------------------------------------------------------------------------

if [[ ! -v BASH_LOADABLES_PATH ]]
   then export BASH_LOADABLES_PATH=
	append-to-PATH-var BASH_LOADABLES_PATH \
			   /usr/local/lib/bash /usr/lib/bash
fi

# 'mkdir' buggy in bash-4.4.20: mkdir -p fails when exists & writable parent
# 'head' speed is proportional to value of -n
# You can read the code for each builtin, e.g. for realpath:
#    https://fossies.org/linux/bash/examples/loadables/realpath.c
bash_builtins="basename dirname id realpath rmdir rm sleep tee uname"

[[ $BASH_LOADABLES_PATH ]] &&
for _builtin in $bash_builtins
    do	enable -f "$_builtin" "$_builtin"
done 2> $dev_null			# rm is only in bash-5.0, ignore error

# ----------------------------------------------------------------------------
# provide a directory for temporary files that's safe from symlink attacks
# ----------------------------------------------------------------------------

tmp_dir=${tmp_dir:-/tmp/${USER-${LOGNAME-$(id -nu)}}} # caller can change
[[ -w ${TMP-}     ]] && tmp_dir=$TMP
[[ -w ${TMP_DIR-} ]] && tmp_dir=$TMP_DIR
TMPDIR=$tmp_dir				# used by bash

# the root filesystem is read-only while booting, don't get into infinite loop!
# GNU mkdir will fail if  $tmp_dir is a symlink
# shellcheck disable=SC2174 # yeah, I know
until [[ ! -w /tmp || -d "$tmp_dir" ]] || mkdir -m 0700 -p "$tmp_dir"
   do	_warn "deleting $(ls -ld "$tmp_dir")"; rm -f "$tmp_dir"
done

export TMP=$tmp_dir TMP_DIR=$tmp_dir	# caller can change these

export LC_COLLATE=C			# so [A-Z] doesn't include a-z
export LC_ALL=C				# server needs nothing special

export RSYNC_RSH=ssh

umask 022				# caller can change it

# ----------------------------------------------------------------------------
# functions to highlight and clean strings
# ----------------------------------------------------------------------------

# http://www.tldp.org/HOWTO/Bash-Prompt-HOWTO/x405.html
# shellcheck disable=SC2120 # we merely make sure we get no args
print-string-colors() {
	[[ $# == 0 ]] || abort-function "takes no arguments"

	header "Coloring from arguments passed to 'tput' command, see man page"
	local n
	for n in {1..8}
	    do	local line=
		local capname
		for capname in setab setb setaf setf
		    do	# shellcheck disable=SC2086
			line+="$(tput $capname $n)$capname $n$(tput sgr0)   "
		done
		echo "$line"
	done
}

# ---------------------------------

# main script can over-ride the following global variables after source us

# the setb coloring stands out more, but fails under 'watch' on some OSs
declare -g -A highlight_level2tput_b_args=(
         [ok]="setb 2"
     [notice]="setb 6"
    [warning]="setb 5"
      [error]="setb 4"
      [stale]="setb 1"
)
declare -g -A highlight_level2tput_args=(
         [ok]="setf 2"
     [notice]="setf 6"
    [warning]="setf 5"
      [error]="setf 4"
      [stale]="setf 3"
)
declare -g -A highlight_level2tput_args=(
         [ok]="setaf 2"
     [notice]="setaf 6"
    [warning]="setaf 5"
      [error]="setab 1"			# setaf is less "striking" than setab
      [stale]="setaf 3"
)
clear_tput_args="sgr0"

declare -g -A highlight_level2escape_sequence

set-highlighted_string() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	local level=$1; shift; local string=$*
	# see is-arg1-in-arg2 function for this logic
	[[ " ${!highlight_level2tput_args[*]} " == *" $level "* ]] ||
	   abort-function "$level is unknown level"

	[[ -t 1 || ${do_tput-} ]] ||
	    { highlighted_string=$string; $xtrace; return; }

	local esc=${highlight_level2escape_sequence[$level]=$(
		# shellcheck disable=SC2086 # variable contains multiple values
		tput ${highlight_level2tput_args[$level]})}
	[[ ${clear_escape_seq-} ]] ||
	     clear_escape_seq=$(tput $clear_tput_args |
				    sed 's/\x1B(B//') # toss leading ESC ( B
	[[ ${terminfo_color_bytes-} ]] ||
	   declare -g -r -i \
		   terminfo_color_bytes=$(( ${#esc} + ${#clear_escape_seq} ))

	highlighted_string=$esc$string$clear_escape_seq
	$xtrace
}

# ----------------------------------------------------------------------------

strip-trailing-whitespace() {

	local var_name
	for var_name
	    do	[[ -v $var_name ]] ||
		    abort-function ": '$var_name' is not a variable"
		local -n var=$var_name
		[[ $var =~ [\	\ ]*$ ]]
		local whitespace=${BASH_REMATCH[0]}
		var=${var%"$whitespace"}
	done
}

[[ $_do_run_unit_tests ]] && {
_var_1='1 2 3 '
_var_2='1 2 3	   		 '
[[ $_var_1 != '1 2 3' ]] || _abort _var_1_
strip-trailing-whitespace _var_1 _var_2
[[ $_var_1 == '1 2 3' ]] || _abort _var_1
[[ $_var_2 == '1 2 3' ]] || _abort _var_2
}

# ----------------------------------------------------------------------------
# Generic logging function, with customization globals that caller can set.
# ----------------------------------------------------------------------------

[[ ${log_date_time_format-} ]] ||
     log_date_time_format="%a %m/%d %H:%M:%S" # caller or env can over-ride

# shellcheck disable=SC2120 # we merely make sure we get no args
set-log_date_time() {
	[[ $# == 0 ]] || abort-function "takes no arguments"

	if [[ ${debug_opt-} ]]
	   then log_date_time="DoW Mo/Da Hr:Mn:Sc"
	   else log_date_time=$(date "+$log_date_time_format")
	fi
}

# ----------------------

file_for_logging=$dev_null		# append to it; caller can change

declare -g -i log_level=0		# set by getopts or configure.sh

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
	   then local _file_for_logging=$dev_null
	   else local _file_for_logging=$file_for_logging
	fi
	local log_date_time
	set-log_date_time
	local  _log_msg_prefix=$log_msg_prefix
	eval  "_log_msg_prefix=\"$_log_msg_prefix\"" # can hold variables
	strip-trailing-whitespace _log_msg_prefix
	echo "$log_date_time$_log_msg_prefix: $_msg" |
	   $sudo tee -a $_file_for_logging
	$xtrace
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

#############################################################################
#############################################################################
### simple error and warning and trace functions.
#############################################################################
#############################################################################

declare -g -i max_call_stack_args=6

# if interactive, want to avoid these extdebug warnings:
#    bash: /usr/share/bashdb/bashdb-main.inc: No such file or directory
#    bash: warning: cannot start debugger; debugging mode disabled
[[ $is_sourced_by_interactive_shell ]] ||
shopt -s extdebug			# enable BASH_ARGV and BASH_ARGC

print-call-stack() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	declare -i stack_skip=1
	[[ ${1-} ==   -s  ]] && { stack_skip=$2+1; shift 2; }
	[[ ${1-} == [0-9] ]] && 
	    { (( Trace_level >= $1 )) || { $xtrace; return; } ; shift; }
	assert-not-option -o "${1-}"

	local log_date_time
	set-log_date_time
	header -E "$log_date_time call stack $*" # include optional message
	# declare -p BASH_ARGV BASH_ARGC	 # uncomment to debug
	local -i depth arg_i argv_i=0 max_args=$max_call_stack_args
	for depth in ${!FUNCNAME[*]}
	   do	(( depth < stack_skip )) &&
		    { argv_i+=${BASH_ARGC[depth]}; continue; } # skip ourself
		# this logic is duplicated in PS4
		local src
		src=$(sed "s@^$HOME/@~/@; s@^/home/@~@; s@/.*/@ @" <<<"${BASH_SOURCE[depth]}") || abort src=
		local args=
		local -i argc=${BASH_ARGC[depth]-0} number_args=0
		for (( arg_i=argv_i+argc-1; arg_i >= argv_i; arg_i-- ))
		    do	local arg=${BASH_ARGV[arg_i]}
			args+="$arg "
			(( argc > max_args+1 )) || continue
			# we never want to say "<1 more args>"
			(( ++number_args == max_args-2 )) &&
			   arg_i=$(( argv_i + 2 )) &&
			   args+="<$(( argc - max_args )) more args> "
		done
		# shellcheck disable=SC2219
		let argv_i+=argc
		echo -n "$src line ${BASH_LINENO[depth-1]}: "
		echo    "${FUNCNAME[depth]} ${args% }"
	done
	echo
	$xtrace
}

# --------------------------------------------

function warn() {
	local msg="$our_name: $*"

	if [[ ${FUNCNAME[1]-} == abort ]]
	   then local level=error
	   else local level=warning
	fi
	[[ -t 2 ]] && set-highlighted_string $level "$msg" &&
	    msg=$highlighted_string
	echo -e "\n$msg\n" >&2
	return 1
}

# ---------------------------------

# clear master_PID to prevent child's abort's attempt to kill us
[[ -v master_PID ]] || master_PID=$BASHPID

abort() {
	set +x
	[[ ${1-} == -r ]] && { shift; is_recursion=$true; } || is_recursion=
	declare -i stack_skip=1
	[[ ${1-} =~ ^-[0-9]+$ ]] && { stack_skip=${1#-}+1; shift; }

	if [[ $is_recursion ]]
	   then # shellcheck disable=SC2219
		let stack_skip+=1
		echo "$@"
	elif [[ ${Usage-} && "$*" == "$Usage" ]]
	   then echo "$@" >&2 ; _libsnap-exit 1
	   else warn "$@"
	fi

	print-call-stack -s "$stack_skip" >&2

	if [[ ! $is_recursion ]]
	   then # shellcheck disable=SC2048,SC2086
		log "$(master_PID=$$ abort -r $* 2>&1)" > $dev_null
	fi

	if [[ ${master_PID-} && $master_PID != "$$" ]] # in a sub-shell?
	   then trap '' TERM		 # don't kill ourself when ...
		kill -TERM -$master_PID	 # kill our parent and its children
		sleep 1
		kill -KILL -$master_PID
	fi 2>&1 | fgrep -v 'No such process'
	_libsnap-exit 1
}

# ---------------------------------

abort-function() {
	set +x
	declare -i stack_skip=1
	[[ ${1-} =~ ^-[0-9]+$ ]] && { stack_skip=${1#-}+1; shift; }
	local opts= ; while [[ ${1-} == -* ]] ; do opts+=" $1"; shift; done

	[[ ${1-} == ':'* ]] && local msg=$* || local msg=" $*"
	# shellcheck disable=SC2086 # $opts may be null or multi
	abort -"$stack_skip" $opts "${FUNCNAME[$stack_skip]}$msg"
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

#############################################################################
#############################################################################
### functions to do tracing, and display variables values
#############################################################################
#############################################################################

has_echoE_been_called=$false

# echo to stdError, include the line and function from which we're called
echoE() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	[[ $1 == -n ]] && { local show_name=$true; shift; } || local show_name=
	declare -i stack_frame_to_show=1 # default to our caller's stack frame
	[[ $1 =~ ^-[0-9]+$ ]] && { stack_frame_to_show=${1#-}+1; shift; }
	assert-not-option -o "${1-}"

	local   line_no=${BASH_LINENO[stack_frame_to_show-1]}
	local func_name=${FUNCNAME[stack_frame_to_show]}
	[[   $func_name ]] && func_name="line $line_no, in $func_name():"

	[[ $show_name ]] && local name="$our_name:" || local name=
	if [[ ! $has_echoE_been_called ]]
	   then  has_echoE_been_called=$true
		[[ ${Trace_log-} && -s $Trace_log ]] && true > "$Trace_log"
	fi
	[[ ${Trace_log-} ]] &&
	echo -e "$name $func_name" "$@" >> "$Trace_log"
	echo -e "$name $func_name" "$@" >&2
	$xtrace
}

# ----------------------

function is-readonly-var() {
	[[ $# == 1 ]] || abort-function "var-name"
	is-var "$1" && [[ $(declare -p "$1") =~ ' '-[a-zA-Z]*r[a-zA-Z]*' ' ]]
}

alias is-readonly-variable=is-readonly-var

#

function is-writable-var() {
	[[ $# == 1 ]] || abort-function "var-name"
	is-var "$1" && ! is-readonly-var "$1"
}

alias is-writable-variable=is-writable-var

# ----------------------

function is-integer-var() {
	[[ $# == 1 ]] || abort-function "var-name"
	is-var "$1" && [[ $(declare -p "$1") =~ ' '-[a-zA-Z]*i[a-zA-Z]*' ' ]]
}

alias is-int-var=is-integer-var
alias is-integer-variable=is-integer-var

[[ $_do_run_unit_tests ]] && {
is-writable-var true && _abort "true is a readonly var"

declare -i _int_var
declare    _str_var
is-writable-var _int_var &&
 is-integer-var _int_var || _abort "_int_var is writable int var"
 is-integer-var _str_var && _abort "_str_var is not an int var"
is-readonly-var _str_var && _abort "_str_var is not readonly var"
unset _int_var _str_var
}

# --------------------------------

function is-integer() {
	[[ $# == 1 ]] || abort-function "arg"
	[[ $1 =~ ^-?[0-9]+$ ]]
}

[[ $_do_run_unit_tests ]] && {
is-integer -123 || _abort "-123 is an integer"
is-integer  123 || _abort  "123 is an integer"
is-integer  1.3 && _abort  "1.3 is not an integer"
}

# ----------------------

function set-var_value--for-debugger() {
	[[ $# == 1 ]] || abort-function "var-name"
	local _var_name_=$1 declare_output
	local -n var=$_var_name_

	while declare_output=$(declare -p "$_var_name_" 2>$dev_null)
	   do	[[ $declare_output = *" -n "* ]] || break
		_var_name_=${declare_output#*=}
		_var_name_=${_var_name_//\"/}
	done

	if [[ $declare_output != *=* ]]
	   then if declare -p "$_var_name_"  &> $dev_null
		   then var_value='<unset>'
		   else var_value='<non-existent>'
		fi
		return 1
	fi

	if [[  ${var@a} == *[aA]* ]]
	   then local is_array=$true
	   else local is_array=$false
	fi
	if [[  ${var@a} == *i* ]]
	   then local is_int=$true
	   else local is_int=$false
	fi
	if [[ $is_array ]]
	   then var_value=${declare_output#*=}
		[[ $is_int ]] && var_value=${var_value//\"/}
	elif [[ $is_int ]]
	     then var_value=${!_var_name_}
	     else var_value=${var@Q}
	fi

	return 0
}

[[ $_do_run_unit_tests ]] && {
declare -a  mapa=(1 two)		; mapa_val='([0]="1" [1]="two")'
declare -A  mapA=([one]=1 [two]=two)	; mapA_val='([two]="two" [one]="1" )'
declare -ai mpai=(1 2)			; mpai_val='([0]=1 [1]=2)'
declare -iA mpAi=([one]=1 [two]=2)	; mpAi_val='([two]=2 [one]=1 )'
declare -n  mapX=mapa			; mapX_val="$mapa_val"
declare -n  mapY=mapX			; mapY_val="$mapa_val"
declare -A  mapn			; mapn_val='<unset>'
declare     sets='set"set'		; sets_val="'set\"set'"
declare -i  seti=1			; seti_val='1'
declare     nots			; nots_val='<unset>'
declare -i  noti			; noti_val='<unset>'
declare					  Nope_val='<non-existent>'
tst_func() {
	local test=$1

	set-var_value--for-debugger "$test"
	local status=$?
	local -n correct_value=${1}_val
	[[ $var_value == "$correct_value" ]] ||
	    _abort "test $test: $var_value != $correct_value"
	return $status
}
tst_func sets || _abort "sets is set"
tst_func seti || _abort "seti is set"
tst_func mapa || _abort "mapa is set"
tst_func mapA || _abort "mapA is set"
tst_func mpai || _abort "mpai is set"
tst_func mpAi || _abort "mpAi is set"
tst_func mapX || _abort "mapX is set"
tst_func mapY || _abort "mapY is set"
tst_func mapn && _abort "mapn  unset"
tst_func nots && _abort "nots  unset"
tst_func noti && _abort "noti  unset"
tst_func Nope && _abort "Nope  isn't"
}

# ----------------------

# like echoE, but also show the values of the variable names passed to us
echoEV() {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	declare -i stack_frame_to_show=1 # default to our caller's stack frame
	[[ $1 =~ ^-[0-9]+$ ]] && { stack_frame_to_show=${1#-}+1; shift; }
	assert-not-option "${1-}"

	local _var_name_ var_value
	for _var_name_
	   do	set-var_value--for-debugger "$_var_name_"

		echoE -"$stack_frame_to_show" "$_var_name_=$var_value"
	done
	$xtrace
}

# ----------------------

[[ -v         Trace_level ]] && is-int-var Trace_level ||
declare -g -i Trace_level=0		# default to none (probably)

_isnum() { [[ $1 =~ ^[0-9]+$ ]] ||abort -1 "Trace* first arg is (min) level"; }
function _Trace () {
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	local echo_cmd=$1; shift
	_isnum "$1"
	(( $1 <= Trace_level )) || { $xtrace; return 1; }
	shift
	$echo_cmd -1 "$@"
	$xtrace
}
alias  Trace='_Trace echoE'
alias TraceV='_Trace echoEV'

# ----------------------------------------------------------------------------

declare -g -A funcname2was_tracing	# global for next three functions

# shellcheck disable=SC2120 # we merely make sure we get no args
function remember-tracing {

	local status=$?			# status from caller's previous command
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	[[ $# == 0 ]] || abort-function "takes no arguments"

	funcname2was_tracing[ ${FUNCNAME[1]} ]=$xtrace

	$xtrace
	return $status
}

# ----------------------

# pass -l if used in a loop, and the restore-tracing is outside the loop
# shellcheck disable=SC2120 # we merely make sure we get no args
function suspend-tracing() {
	local status=$?			# status from caller's previous command
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	[[ ${1-} == -l ]] && { shift; local in_loop=$true; } || local in_loop=
	[[ $# == 0 ]] || abort-function "[-l]"

	if [[ $xtrace ]]
	   then local was_tracing=$true
	   else local was_tracing=$false
		[[ $in_loop ]] && return $status
	fi
	funcname2was_tracing[ ${FUNCNAME[1]} ]=$was_tracing
	return $status
}

# ----------------------

# show the values of the variable names passed to us, then restore traing state
function restore-tracing {

	local status=$?			# status from caller's previous command
	# see is-arg1-in-arg2 function for this logic
	[[ " ${!funcname2was_tracing[*]} " == *" ${FUNCNAME[1]} "* ]] ||
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

[[ $_do_run_unit_tests ]] && {
wont-trace() {         foo=2
	       suspend-tracing; echo untraced; restore-tracing foo; }
will-trace() { set -x; foo=1
	       suspend-tracing; echo untraced; restore-tracing foo
	       wont-trace; echo traced; set +x; }
[[ $(will-trace 2>&1) == *' echo untrac'* ]] && _abort "suspend-tracing failed"
[[ $(will-trace 2>&1) == *' echo traced'* ]] || _abort "restore-tracing failed"
unset -f wont-trace will-trace
}

# ----------------------------------------------------------------------------

print-or-egrep-Usage-then-exit() {
	[[ ${1-} == -[hHk] ]] && shift	# strip help or keyword-search option
	[[ $# == 0 ]] && echo -e "$Usage" && _libsnap-exit 0

	echo "$Usage" | egrep -i "$@"
	_libsnap-exit 0
}

# ---------------------------------

abort-with-action-Usage() {
	local opts= ; while [[ ${1-} == -* ]] ; do opts+=" $1"; shift; done
	local _action=${*:-$action}

	echo -e "\nBad arguments; here's the usage for this action:"
	# shellcheck disable=SC2086 # $opts may be null or multi
	echo "$Usage" | grep $opts "^ *$_action" >&2; echo
	_libsnap-exit 1
}

# ---------------------------------

# RunCmd's args are a command (plus args) that _should_ return 0, else we abort
RunCmd() {
	[[ $1 == -d ]] && { local IfAbort=$IfRun; shift; } || local IfAbort=
	[[ $1 == -m ]] && { local msg="; $2"; shift 2; } || local msg=
	assert-not-option -o "${1-}"

	$IfRun "$@" || $IfAbort abort -1 "'$*' returned $?$msg"
}

[[ $_do_run_unit_tests ]] && {
RunCmd true &&
[[ $(master_PID=$BASHPID \
     RunCmd -d -m "expected (non fatal)" false 2>&1) == *'(non fatal)'* ]] ||
   _abort "RunCmd error"
}

#############################################################################
#############################################################################
### Profiling functions, primrily used by the aliases at the very end.
#############################################################################
#############################################################################

readonly null_cmd_string='[[ $? == 0 ]]' # retain success/failure of prev cmd
# shellcheck disable=SC2139 # we only want to expand once
alias null-cmd="$null_cmd_string"	# retains success/failure of prev cmd

[[ $_do_run_unit_tests ]] && {
 true; null-cmd || _abort "didn't pass-through sucess"
false; null-cmd && _abort "didn't pass-through failure"
}

# ----------------------------------------------------------------------------

if [[ ${EPOCHREALTIME-} ]]
   then # shellcheck disable=SC2154 # shellcheck doesn't grok aliases
	alias set-epoch_msecs='
		local _epoch_usecs_=${EPOCHREALTIME/./}
		epoch_msecs=${_epoch_usecs_%???}'
	alias set-epoch_usecs='epoch_usecs=${EPOCHREALTIME/./}'
   else alias set-epoch_usecs='epoch_msecs=$(date +%s%6N)'
	alias set-epoch_msecs='epoch_msecs=$(date +%s%3N)'
fi

# ----------------------------------------------------------------------------

declare -g -i -A profiled_function2epoch
declare -g -i -A profiled_function2count
declare -g -i -A profiled_function2usecs
declare -g    -A profiled_function2name	# need -g, else gets unset?!

[[ -v	   profile_overhead_passes ]] && is-int-var profile_overhead_passes ||
declare -g -i profile_overhead_passes=200 # up to 50 microseconds per pass

declare -g -i profile_overhead_usecs=0
function _set-profile_overhead_usecs {

	profile_overhead_usecs=1	# so don't recurse

	local -i i usecs min_usecs=1123123123

	# enough to get a sample without a (longish) context switch
	for ((i=1; i <= profile_overhead_passes; i++))
	    do	profile-on
		profile-off
		usecs=${profiled_function2usecs[$FUNCNAME]}
		profiled_function2usecs[$FUNCNAME]=0 # don't accumulate
		(( $min_usecs<$usecs )) ||
		    min_usecs=$usecs
	done
	(( $min_usecs > 0 )) || min_usecs=1
	profile_overhead_usecs=$min_usecs
	return 0
}

# ---------------------------------------

function profile-on() {
	local status=$?
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	[[ ${do_profile-} ]] || { $xtrace; return $status; }
	((   $profile_overhead_usecs > 0 )) ||
	 _set-profile_overhead_usecs
	local function=${FUNCNAME[1]-main}
	local name=${1:-$function}
	profiled_function2name[$function]=$name

	local -i epoch_usecs
	set-epoch_usecs
	profiled_function2epoch[$name]=$epoch_usecs
	$xtrace
	return $status
}

# ----------------------

function profile-off() {
	local status=$?
	[[ -o xtrace ]] && { set +x; local xtrace="set -x"; } || local xtrace=
	local -i epoch_usecs
	set-epoch_usecs
	[[ ${do_profile-} ]] || { $xtrace; return $status; }
	local function=${FUNCNAME[1]-main}
	local name=${1:-${profiled_function2name[$function]}}

	local -i epoch_start=${profiled_function2epoch[$name]-0}
	(( $epoch_start > 0 )) || { $xtrace; return $status; }

	local -i usecs_duration=$epoch_usecs-$epoch_start
	profiled_function2usecs[$name]+=$usecs_duration-$profile_overhead_usecs
	profiled_function2count[$name]+=1

	profiled_function2epoch[$name]=0 # in case profile-off without -on
	$xtrace
	return $status
}

# -------------------------------------------------

# shellcheck disable=SC2120
print-profile-data() {
	[[ ${1-} == -d ]] && { local opt="$1$2"; shift 2; } || local opt="-d 6"
	[[ ${1-} == -k ]] && { local arg="$1$2"; shift 2; } || local arg=-
	[[ $# == 0 ]] ||
	    abort-function "[-d decimal-digits] [-k sort-column-number]"
	local path=${1-profile}
	[[ $path == *.* ]] || path+=".csv"

	unset "profiled_function2usecs['_set-profile_overhead_usecs']"
	unset "profiled_function2count['_set-profile_overhead_usecs']"

	local name
	local format="%15s\t%7s\t%15s\t%s\n"
	local -i count usecs usecs_per_call
	local secs secs_per_call
	# shellcheck disable=SC2059 # why not??
	printf "$format" 'total-seconds' 'count' 'secs-per-call' 'function'
	for name in  ${!profiled_function2usecs[*]}
	    do	count=${profiled_function2count[$name]}
		usecs=${profiled_function2usecs[$name]}
		usecs_per_call=$usecs/$count
		# shellcheck disable=SC2086 # options are optional
		  set-division $opt "$usecs"          1000000
		secs=$division
		# shellcheck disable=SC2086 # options are optional
		  set-division $opt "$usecs_per_call" 1000000
		secs_per_call=$division
		# shellcheck disable=SC2059 # why not??
		printf "$format" "$secs" "$count" "$secs_per_call" "$name"
	done | sort -n -r "$arg"
}

# ---------------------------------

write-profile-data() {
	if [[ $# == 0 ]] || is-integer ${!#} # only print-profile-data args?
	   then local filename=profile	     # default filename
	   else local filename=${!#}
		set -- "${@: 1: $#-1}"
	fi
	[[ ${filename##*/} == *.* ]] || filename+=.csv

	print-profile-data "$@" | echo-to-file - $filename
}

[[ $_do_run_unit_tests ]] && {
(( profile_overhead_usecs )) && _abort "profiling should be disabled"

for do_profile in "$false" "$true"
    do	 true; profile-on  || _abort "profile-on  not null-cmd after true"
	 true; profile-off || _abort "profile-off not null-cmd after true"
	false; profile-on  && _abort "profile-on  not null-cmd after false"
	false; profile-off && _abort "profile-off not null-cmd after false"
done

for name in "" profile; do
profile-on "$name"; sleep 0.00001; profile-off || _abort "must return success"
[[ -v profile_overhead_usecs ]] || _abort "didn't set profile_overhead_usecs"
((    profile_overhead_usecs )) || _abort "profile_overhead_usecs is 0"
name=${name:-main}
[[ $name == main ]] && c=3 || c=1
((  ${profiled_function2count[$name]} == $c )) || _abort "profile error: $name"
((  ${profiled_function2usecs[$name]} >= 10 )) || _abort "profile fail: $name"
done

for name in main profile
    do	[[ ${profiled_function2usecs[$name]-} ]] || _abort "PF missing $name"
done
unset "profiled_function2count[main]" "profiled_function2usecs[main]"
}

do_profile=$true

# ----------------------------------------------------------------------------
# The above functions are mostly accessed with the following aliases.

# The common use case: after a (possible) global "set -x", you don't want to
# trace a particular function because it's known to work or contains loops, so
# you start the function with can-profile-not-trace, and restore tracing
# before leaving the function with either can-trace-final-test or x-return .
# As a bonus, if $do_profile is non-null, it profiles that function.
# ----------------------------------------------------------------------------

declare -g -A _FUNCNAME2xtrace_

alias can-profile-not-trace='
	if [[ -o xtrace${force_next_function_trace-} ]]
	   then set +x
		_FUNCNAME2xtrace_[$FUNCNAME]=$true
	   else _FUNCNAME2xtrace_[$FUNCNAME]=$false
		force_next_function_trace=
	fi
	[[ ${do_profile-} ]] && profile-on'

# shellcheck disable=SC2154 # shellcheck doesn't grok pervious alias
alias continue-tracing-function='
local _trc_=$?; [[ ${_FUNCNAME2xtrace_[$FUNCNAME]-} ]] && set -x
[[ $_trc_ == 0 ]]'

# Programmer can end function with a test on (possibly-null) computed value.
alias can-trace-final-test='
profile-off; [[ ${_FUNCNAME2xtrace_[$FUNCNAME]-} ]] && set -x'

# This replaces 'return', if function *might* have can-profile-not-trace ,
# If used after '||' or '&&' , you must enclose it in {}, aka: { x-return 1; }
# shellcheck disable=SC2154 # shellcheck doesn't grok pervious alias
alias x-return='
	local _x_return_default_status_=$?
	profile-off; [[ ${_FUNCNAME2xtrace_[$FUNCNAME]-} ]] && set -x
	[[ $_x_return_default_status_ == 0 ]]; return'

#############################################################################
#############################################################################
### Optimizing and verifying commands
#############################################################################
#############################################################################

# ----------------------------------------------------------------------------
# functions to make sure needed utilities are in the PATH
# ----------------------------------------------------------------------------

# return true if have any of the passed commands, else silently return false
function have-cmd() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	local _cmd
	for _cmd
	   do	type -t "$_cmd" > $dev_null && { x-return 0; }
	done
	x-return 1
}

alias have-command=have-cmd

[[ $_do_run_unit_tests ]] && {
have-cmd is-set   || _abort "have is-set"
have-cmd our_name && _abort "don't have func our_name"
}

# --------------------------------------------

# exit noisily if missing (e.g. not in PATH) any of the $* commands
need-cmds() {
	can-profile-not-trace # use x-return to leave function; can comment-out

	local _cmd is_cmd_missing=
	for _cmd
	    do	have-cmd "$_cmd" && continue

		echo "$our_name: command '$_cmd' is not in current path."
		is_cmd_missing=1
	done

	[[ $is_cmd_missing ]] && _libsnap-exit 2
	x-return
}

alias need-commands=need-cmds

# ----------------------------------------------------------------------------

# used to precede a command/function that is not yet ready to run
function not-yet() { warn "'$*' not yet available, ignoring"; }

#############################################################################
#############################################################################
### define functions that abstract OS/kernel-specific operations or queries
#############################################################################
#############################################################################

#############################################################################
# functions for querying hardware; email ${coder-Scott} if fix/port.
# snapback or snapcrypt users can write a replacement in configure.sh .
#############################################################################

# path can be either the mount directory or the device
function set-FS_type--from-path() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	[[ $# == 1 ]] || abort-function "path"
	local  path=$1
	[[ -e $path ]] || abort "mount-dir='$path' doesn't exist"

	local mounts
	set-mounts
	FS_type=$(sed -r -n "s~^[^ ]+ $path ([^ ]+) .*~\1~p" <<<"$mounts")

	if [[ ! $FS_type ]]
	   then have-cmd lsblk ||
		   abort "fix $FUNCNAME for '$path', email to ${coder-Scott}"
		[[ ! -b "$path" ]] && local FS_device &&
		    set-FS_device--from-mount-dir "$path" && path=$FS_device
		[[ ! -b "$path" ]] &&
		    abort-function "'$path' is not accessible"
		local cmd="lsblk --noheadings --nodeps --output=fstype $path"
		FS_type=$($cmd)
		if [[ ! $FS_type ]]
		   then # shellcheck disable=SC2086 # $cmd has its arguments
			FS_type=$(sudo $cmd)
		fi
	fi

	[[ $FS_type ]] || warn "$FUNCNAME: $path has no discernible filesystem"
	x-return
}

# ----------------------------------------------------------------------------

# path can be either the mount directory or the device
function set-inode_size-data_block_size-dir_block_size--from-path() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	[[ $# == 1  ]] || abort-function "path"
	local  path=$1
	[[ -e $path ]] || abort-function "mount-dir='$path' doesn't exist"

	local FS_type
	set-FS_type--from-path "$path" || { x-return 1; }

	case $FS_type in
	   ( ext? )
		local FS_device
		set-FS_device--from-mount-dir "$path" || { x-return 1; }
		# shellcheck disable=SC2046
		set -- $(sudo tune2fs -l "$FS_device" |&
				sed -n  -e 's/^Block size://p' \
					-e 's/^Inode size://p'
				_libsnap-exit "${PIPESTATUS[0]}")
		local status=$?
		inode_size=${2-} data_block_size=${1-} dir_block_size=${1-}
		[[ $status == 0 ]]
		;;
	   ( xfs  )
		# shellcheck disable=SC2046
		set -- $(xfs_growfs -n "$path" |
			 sed -n -r -e 's/.* isize=([0-9]+) .*/\1/p'	    \
				   -e '  s/^data .* bsize=([0-9]+) .*/\1/p' \
				   -e 's/^naming .* bsize=([0-9]+) .*/\1/p'
				_libsnap-exit "${PIPESTATUS[0]}")
		local status=$?
		inode_size=${1-} data_block_size=${2-} dir_block_size=${3-}
		[[ $status == 0 ]]
		;;
	   (  *   )
		abort "fix $FUNCNAME for '$FS_type', email ${coder-}"
		;;
	esac || abort-function "$path (FS_type=$FS_type) returned $status"
	x-return 0
}

# ----------------------------------------------------------------------------

declare -g -i device_KB=0

# snapback users can write a replacement in configure.sh
function set-device_KB--from-block-device() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	[[ $# == 1 ]] || abort-function "device"
	local  dev=$1
	[[ -b $dev ]] || abort "$dev is not a device"

	device_KB=0
	have-cmd lsblk || { x-return 1; } # x-return is multi-cmd alias, so {}

	# shellcheck disable=SC2046,SC2086
	set -- $(lsblk --noheadings --bytes --output=SIZE $dev)
	[[ $# == 1 ]] || abort-function ": specify a partition not whole drive"
	device_KB=$(( $1/1024 ))
	(( $device_KB > 0 ))
	x-return
}

# ----------------------------------------------------------------------------

# snapback or snapcrypt users can write a replacement in configure.sh
set-FS_label--from-FS-device() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	[[ $# == 1 ]] || abort-function "device"
	local  device=$1
	[[ -b $device ]] || abort "$device is not a device"

	local  label2disk_dir=/dev/disk/by-label dev
	[[ -d $label2disk_dir ]] && {
	[[ -L $device ]] && dev=$(readlink "$device") && dev=${dev#../} || 
		dev=$device
	if [[ $dev != */* || $dev != /*/*/* ]]
	   then local name=${dev##*/}
		# shellcheck disable=SC2012
		FS_label=$(ls -l "$label2disk_dir" |
			   sed -r -n "s~.* ([^ ]+) -> ../../$name$~\1~p")
		[[ $FS_label ]] && { x-return; }
	fi; }

	# shellcheck disable=SC1014,SC2053
	[[ set-mount_dir--from-FS-device != ${FUNCNAME[1]} ]] && {
	   set-mount_dir--from-FS-device "$device"
	# shellcheck disable=SC1087,SC2046
	set -- $(grep "^[^#]*[[:space:]]$mount_dir[[:space:]]" /etc/fstab)
	[[ ${1-} == LABEL=* ]] && FS_label=${1#*=} || FS_label=	; }

	# don't use lsblk, it sometimes returns very old labels
	if [[ ! ${FS_label-} ]] && have-cmd blkid
	   then local cmd="blkid $device |
			   sed -n -r 's@.* LABEL=\"?([^ \"]*)\"? .*@\1@p'"
		# have to eval because cmd contains a pipeline
		eval "FS_label=\$($cmd)"	; [[ $FS_label ]] ||
		eval "FS_label=\$(sudo $cmd)"
	fi

	[[ $FS_label ]] ||
	   abort "you need to fix $FUNCNAME and email it to ${coder-Scott}"
	x-return
}

# ----------------------------------------------------------------------------

label-drive() {
	[[ $# == 2 ]] || abort-function "device mount-dir"
	local  device=$1 mount_dir=$2
	[[ -b $device ]] || abort "$device is not a device"

	local FS_type FS_label
	set-FS_type--from-path "$device"

	set-FS_label--from-mount_dir "$mount_dir"

	case $FS_type in
	   ( ext? ) $IfRun sudo e2label "$device" "$FS_label" ;;
	   ( xfs  ) $IfRun sudo xfs_admin -L "$FS_label" "$device" ;;
	   (  *   ) abort "fix $FUNCNAME for '$FS_type', email ${coder-}" ;;
	esac || abort-function "$device $mount_dir: returned $? ($FS_type)"
}

# ----------------------------------------------------------------------------

set-FS_device--from-FS-label() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	[[ $# == 1 ]] || abort-function "FS-label"
	local label=$1

	if [[ -d /Volumes ]]		# Darwin?
	   then set-FS_device--from-mount-dir "/Volumes/$label"
		x-return
	fi

	have-cmd blkid ||
	  abort "you need to fix $FUNCNAME and email it to ${coder-Scott}"

	# -L has a different meaning in older versions, so use old method
	local cmd="blkid -l -o device -t LABEL=$label"
	FS_device=$($cmd)
	if [[ ! $FS_device ]]
	   then # shellcheck disable=SC2086 # $cmd contains its arguments
		FS_device=$(sudo $cmd)
	fi

	set-FS_label--from-FS-device "$FS_device"
	[[ $FS_label == "$label" ]] ||
	  abort "'blkid' lies: pass device to '$our_name' by-hand"

	[[ $FS_device ]] || abort "couldn't find device for $label"
	x-return
}

# ----------------------------------------------------------------------------

# you might try to use $OSTYPE instead of this function
# shellcheck disable=SC2120 # we merely make sure we get no args
function set-OS_release_file-OS_release {
	[[ $# == 0 ]] || abort-function "takes no arguments"

	set -- /usr/lib/*-release /etc/*-release
	while (( $# > 1 ))
	   do	[[ -s $1 ]] || { shift; continue; }
		case $(basename "$1") in
		   ( lsb-release ) [[ $# != 0 ]] && shift; continue ;;
		esac
		break
	done
	[[ -s $1 ]] || abort "fix $FUNCNAME and email it to ${coder-Scott}"
	OS_release_file=$1

	case $(basename "$OS_release_file") in
	   ( os-release ) OS_release=$(sed -n 's/^PRETTY_NAME=//p' "$1") ;;
	   ( * )  read -r OS_release < "$1" ;;
	esac
}

##############################################################################
##############################################################################
### Finally, define shell functions that only need GNU utilities.
##############################################################################
##############################################################################

# -----------------------------------------------------------------------
# Define FS-label naming conventions.					#
# snapback or snapcrypt users can write replacements in configure.sh .	#
# -----------------------------------------------------------------------

function set-FS_device--from-mount-dir() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	[[ $# == 1  ]] || abort-function "path"
	local  path=$1
	[[ -e $path ]] || { warn "path=$path doesn't exist"; x-return 1; }

	local mounts
	set-mounts
	FS_device=$(sed -r -n "s~^([^ ]+) $path .*~\1~p" <<<"$mounts")
	[[ $FS_device ]]
	x-return
}

# ----------------------------

function set-mount_dir--from-FS-device() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	[[ $1 == -q ]] && { local is_quiet=$true; shift; } || local is_quiet=
	[[ $# == 1  ]] || abort-function "[-q] device"
	local  dev=$1
	[[ -b $dev  ]] || abort-function "$dev is not a device"
	[[ $dev == /* ]] || dev=$PWD/$dev

	local mounts
	set-mounts
	mount_dir=$(sed -r -n "s~^$dev ([^ ]+) .*~\1~p" <<<"$mounts")
	[[ $mount_dir ]] && { x-return 0; }

	# shellcheck disable=SC1087,SC2046
	set -- $(grep "^[[:space:]]*$dev[[:space:]]" /etc/fstab)
	mount_dir=${2-}
	[[ $mount_dir ]] && { x-return 0; }

	local FS_label
	set-FS_label--from-FS-device "$dev"
	# shellcheck disable=SC1087,SC2046
	set -- $(grep "^[[:space:]]*LABEL=$FS_label[[:space:]]" /etc/fstab)
	mount_dir=${2-}

	[[ $mount_dir ]] && { x-return 0; }

	[[ ! $is_quiet ]] && abort "couldn't find mount dir for dev=$dev"
	x-return 1
}

# ----------------------------

function set-mount_dir--from-FS-label() {
	[[ $# == 1 ]] || abort-function "FS-label"
	local label=$1

	mount_dir=/${label//_/\/}
	[[ -d $mount_dir ]]
}

# -------------------------------

set-FS_label--from-mount_dir() {
	[[ $# == 1 ]] || abort-function "mount-dir"
	local mount_dir=$1

	FS_label=${mount_dir#/}
	FS_label=${FS_label//\//_}
}

#############################################################################
#############################################################################
### Functions to workaround printf's lack of terminfo knowledge.
#############################################################################
#############################################################################

default_padded_colorized_string_field_width=

# "printf %7s" doesn't handle terminfo escape sequence
# printf strips trailing SPACES; so pad with '_', and replace them later
set-padded_colorized_string--for-printf() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	[[ $# == [23] ]] || abort-function "need 2-3 args"
	local string=$1 colorized_string=$2
	local  default_width=$default_padded_colorized_string_field_width
	local -i field_width=${3:-$default_width}
	(( field_width > 0 )) || abort-function ": need \$3 as counting number"

	[[ -t 1 || ${do_tput-} ]] ||
	    { padded_colorized_string=$string; x-return; }

	padded_colorized_string=$colorized_string
	declare -i pad_count=$terminfo_color_bytes
	(( ${#string} + $pad_count <= $field_width )) ||
	    pad_count=field_width-${#string}
	declare -i n
	for (( n=1; n <= pad_count; n+=1 ))
	    do	padded_colorized_string+='_'
	done
	x-return
}

# -------------------

fix-padded-colorized-string-vars() {

	local var_name
	for var_name
	    do	[[ -v $var_name ]] ||
		    abort-function ": '$var_name' is not set"
		local -n var=$var_name
		local  value=$var
		var=${value//_/ }	# rewrite padding
	done
}

#############################################################################
#############################################################################
### Working with file/directory metadata.
#############################################################################
#############################################################################

# does 1st argument match any of the whitespace-separated words in rest of args
function is-arg1-in-arg2() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	(( $# >= 1 )) || abort-function "arg1 arg(s)"
	local arg1=$1; shift
	local arg2=$*
	[[ $arg1 && $arg2 ]] || { x-return 1; }

	# turn newlines and TABs into SPACEs before checking
	[[ " ${arg2//[
	]/ } "  ==  *" $arg1 "* ]]
	x-return
}

[[ $_do_run_unit_tests ]] && {
is-arg1-in-arg2 foo "" && _abort "null arg2 means false"
is-arg1-in-arg2 foo    && _abort   "no arg2 means false"
lines="1
2"
is-arg1-in-arg2 1  "$lines" || _abort "1 is not in lines"
is-arg1-in-arg2 2  "$lines" || _abort "2 is not in lines"
is-arg1-in-arg2 12 "$lines" && _abort "12   is  in lines"
fields="1	2"
is-arg1-in-arg2 1  "$fields" || _abort "1 is not in fields"
is-arg1-in-arg2 2  "$fields" || _abort "2 is not in fields"
is-arg1-in-arg2 12 "$fields" && _abort "12   is  in fields"
}

# ----------------------------------------------------------------------------

function is-an-FS-device-mounted() {
	[[ $# == 1 ]] || abort-function "{ device | mount-dir }"
	local path=$1
	[[ $path == /* ]] || path=$PWD/$path
	[[ $path != /dev/* && ! -d $path ]] && return 1
	[[ -b $path || -d $path ]] ||
	    abort-function ": can't find device or directory for '$1'"

	local mounts
	set-mounts
	is-arg1-in-arg2 "$path" "$mounts"
}

[[ ! $_do_run_unit_tests ]] ||
    is-an-FS-device-mounted / || _abort "can't find mounted root device"

# ----------------------------------------------------------------------------

function is-older() {
	[[ $# == 2 ]] || abort-function "path-1 path-2"
	[[ -e $1 && -e $2 && $1 -ot $2 ]]
}
function is-newer() {
	[[ $# == 2 ]] || abort-function "path-1 path-2"
	[[ -e $1 && -e $2 && $1 -nt $2 ]]
}

# ----------------------------------------------------------------------------

function set-absolute_dir() {
	[[ $# == 1 ]] || abort-function "path"
	absolute_dir=$(realpath "$1")
	[[ $absolute_dir && -d $absolute_dir ]]
}

# -------------------------------------------------------

function set-absolute_path() {
	[[ $# == 1 ]] || abort-function "path"
	absolute_path=$(realpath "$1")
	[[ -e $absolute_path ]]
}

# ----------------------------------------------------------------------------

_chdir() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	local cmd=$1; shift
	[[ ${1-} == -q ]] && { shift;local is_quiet=$true; } || local is_quiet=
	(( $# <= 1 )) || abort-function "$*: wrong number args"
	local _dir=${1-$HOME}

	if [[ $cmd == popd ]]
	   then popd	      || abort       "popd -> $?"	; cmd="popd to"
	   else $cmd "$_dir"  || abort "$cmd $_dir -> $?"
	fi > $dev_null	    # suppress output of 'dirs' when run pushd or popd

	if [[ ! $is_quiet && ( $IfRun || ${do_show_cd-} ) && ! ${Trace-} ]]
	   then local _msg="$cmd $PWD"
		[[ $_dir == */.* && $_dir != /* ]] && _msg="$_msg # $_dir"
		echo "$_msg"
	fi
	x-return
}

alias    cd_='_chdir    cd'
alias pushd_='_chdir pushd'
alias  popd_='_chdir  popd'

# ----------------------------------------------------------------------------

function df_() { df "$@"; }		# a killable function

# ----------------

# for each field, assign that field's value to a variable named for that field
function setup-df-data-from-fields() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	local df_opts=
	while [[ $1 == -* ]]; do df_opts+="$1 "; shift; done
	(( $# >= 2 )) || abort-function "[df-opts] drive df-column-name(s)"
	local drive=$1; shift
	local fields=$*

	if ! [[ -b $drive || -d $drive ]]
	   then # shellcheck disable=SC2155
		local ls_msg=$(ls -ld "$drive" 2>&1)
		 warn ": first arg must be device or directory:\n   $ls_msg"
		 x-return 1
	fi

	set -f
	# shellcheck disable=SC2086 # variable contains multiple values
	set -- ${fields//,/ }
	fields=$*
	local -i field_count=$#
	#
	# the caller can deine this run-until-timeout wrapper:
	local runner=run-with-timeout
	have-cmd "$runner" || runner=
	# shellcheck disable=SC2046,SC2086 # *_opts may be null or multi
	set -- $($runner df_ $df_opts --output="${fields// /,}" "$drive"/.)
	set +f
	[[ $# != 0 ]] || abort-function "'df $drive' failed"
	while (( $# > $field_count )) ; do shift; done

	local name
	for name in $fields
	    do	local -n field=$name
		field=${1%\%}		# remove any trailing '%'
		shift
	done
	x-return 0
}

# ----------------------------------------------------------------------------

function set-file_KB() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	[[ $# == 1 ]] || abort-function "path"
	local _file=$1

	# shellcheck disable=SC2046
	set -- $(ls -sd "$_file")
	file_KB=$1
	can-trace-final-test
	[[ $file_KB ]]
}

# ----------------------------------------------------------------------------

copy-file-perms() {
	[[ $1 == -D ]] && local mkdir_opt=-p
	[[ $1 == -d ]] && local mkdir_opt=
	[[ $1 == -[dDf] ]] && { local opt=$1; shift; } || local opt=
	assert-not-option "$1"
	(( $# >= 2 )) || abort-function "reference-path path(s)"
	local reference=$1; shift

	local path sudo=
	for path
	    do	[[ -f "$path" ]] &&
		    # we might not have GNU utils, or might need sudo
		    cp --attributes-only -p "$reference" "$path" 2>$dev_null &&
		    continue
		if [[ $opt == -f ]]
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
				# shellcheck disable=SC2086 # *_opt may be null
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

#############################################################################
#############################################################################
### Working with file contents
#############################################################################
#############################################################################

# replace a file's contents atomically (read from stdin if $1 == '-')
echo-to-file() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	[[ $1 == -p ]] && { shift; local do_perms=$true; } || local do_perms=
	local filename=${!#}

	if [[ $IfRun ]]
	   then local string=${*: 1: $#-1}
		[[ $string == *[\ \"\`$]* ]] && string="'$string'"
		echo "echo $string > $filename"; x-return
	fi

	local new_filename="$filename.$BASHPID"
	if is-arg1-in-arg2 '-' "$@"
	   then [[ $# == 2 ]] || abort-function ": can't mix stdin and strings"
		cat
	   else echo "${@: 1: $#-1}"
	fi > "$new_filename" || abort-function "$new_filename"
	[[ $do_perms ]] && copy-file-perms "$filename" "$new_filename"
	mv "$new_filename" "$filename" || abort-function "$filename"
	x-return
}

# ----------------------------------------------------------------------------

assert-sha1sum() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	[[ $# == 2 ]] || abort-function "sha1sum path"
	local sha1sum=$1 file=$2

	# shellcheck disable=SC2046,SC2086
	set --   $(sha1sum "$file")
	[[ $1 == "$sha1sum" ]] && { x-return; }
	abort     "sha1sum($file) != $sha1sum"
}

# ----------------------------------------------------------------------------

# return non-0 if din't find any emacs backup files
function set-backup_suffix--for-emacs() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	[[ $# == 1  ]] || abort-function ": specify a single file"
	local  path=$1
	[[ -f $path ]] || abort-function ": '$path' not file, or doesn't exist"

	local -i max_num=0
	local backup
	for backup in "$path".~[1-9]*~
	   do	[[ $backup =~ ~([1-9][0-9]*)~$ ]] || continue
		local -i num=${BASH_REMATCH[1]}
		(( max_num < num )) &&
		   max_num=$num
	done

	(( max_num == 0 )) && local status=1 || local status=0
	# shellcheck disable=SC2219
	let max_num+=1
	backup_suffix=.~$max_num~

	x-return $status
}

# ---------------------------------

# this is for 'sed --in-place[=SUFFIX]' or 'perl -i[extension]'
set-backup_suffix() {
	can-profile-not-trace # use x-return to leave function; can comment-out

	set-backup_suffix--for-emacs "$@" || backup_suffix='~'
	x-return
}

# ----------------------------------------------------------------------------

function does-file-end-in-newline() {
	can-profile-not-trace # use x-return to leave function; can comment-out

	local file
	for file
	    do	[[ -f $file && -s $file ]] || { x-return 1; }
		[[ $(tail -c 1 "$file") ]] && { x-return 1; }
	done
	x-return 0
}

# ----------------------------------------------------------------------------

merged-continuation-lines() {

	# https://catonmat.net/sed-one-liners-explained-part-one
	sed -e :a -e '/\\$/N; s/\\\n//; ta' "$@"
}

# ----------------------------------------------------------------------------

set-cat_cmd() {
	[[ $# == 1 ]] || abort-function "path"
	local filename=$1

	case ${filename##*.} in
	    ( bz2 ) cat_cmd="bzcat"	;;
	    ( gz  ) cat_cmd="zcat"	;;
	    ( lz4 ) cat_cmd="lz4cat"	;;
	    ( xz  ) cat_cmd="xzcat"	;;
	    ( zst ) cat_cmd="zstdcat"	;;
	    ( *   ) cat_cmd="cat"	;;
	esac
}

# ----------------------------------------------------------------------------

# this doesn't fork, so 20xfaster than $(< ).
# BUT, this function will silently discard leading and trailing blank lines,
# because that's how 'read' itself works in bash-5.0.
# returns non-0 if file is empty, or if -A and error.
function read-all() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	[[ $1 == -A ]] && { local no_abort=$true; shift; } || local no_abort=
	[[ $# ==  2 ]] || abort-function "var-name path"
	local var_name=$1 file_name=$2

	[[ $no_abort && ! -f "$file_name" ]] && { x-return 1; }
	unset "$var_name"		# in case 'read' fails
	read -d '\0' -r "$var_name" < "$file_name"
	if [[ -v $var_name ]]
	   then [[ ${!var_name} ]]
		x-return
	fi
	[[    $no_abort ]] && { x-return 1; }
	[[ -e $file_name ]] || abort-function "$file_name doesn't exist"
	[[ -f $file_name || -p $file_name ]] ||
	    abort-function "$file_name not a file"
	[[ -r $file_name ]] || abort-function "$file_name not readable file"
	abort-function "failed to read $file_name"
}

[[ $_do_run_unit_tests ]] && {
file=/etc/hostname
[[ -s $file ]] && {
cat   $file > $dev_null			# pull into page cache for profiling
read-all data $file && [[ $data ]] || _abort "should return success"
[[ $data == "$HOSTNAME" ]] || _abort "read-all got wrong data: $data"; }
( read-all data /etc/shadow 2>$dev_null ) && _abort "can't read /etc/shadow"
( read-all data /etc        2>$dev_null ) && _abort "can't read /etc/"
unset data
read-all -A data DoesNotExist || [[ -v data ]] && _abort "nothing to read"
read-all data $dev_null && _abort "should return nothing, but got '$data'"
}

#############################################################################
#############################################################################
### Working with processes.
#############################################################################
#############################################################################

function have-proc { [[ -e /proc/mounts ]] ; }

# ---------------------------------

# return 0 if all processes alive, else 1; unlike 'kill -0', works without sudo
function is-process-alive() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	local PIDs=$*

	local PID
	for PID in $PIDs
	    do	PID=${PID#-}		# in case passed PGID indicator
		if [[ -e /proc/mounts ]]
		   then [[ -d /proc/$PID ]]
		   else ps "$PID" &> $dev_null
		fi || { x-return 1; }	# x-return is multi-cmd alias, so {}
	done
	x-return 0
}

[[ ! $_do_run_unit_tests ]] ||
    is-process-alive $$ $BASHPID || _abort "is-process-alive failure"

#############################################################################
#############################################################################
### Working with lists.
#############################################################################
#############################################################################

function set-uniques() {

	local -A unique2true
	local value
	for value
	    do	unique2true[$value]=$true
	done
	uniques=${!unique2true[*]}
	[[ $uniques ]]
}

[[ $_do_run_unit_tests ]] && {
set-uniques 1 2 2 3 3 3
[[ $uniques == "1 2 3" ||
   $uniques == "3 2 1" ]] || _abort "(maybe order changed?): uniques=$uniques"
unset uniques
}

# ----------------------------------------------------------------------------

set-reversed_words() {
	can-profile-not-trace # use x-return to leave function; can comment-out

	reversed_words=
	local word
	for word
	   do	reversed_words="$word $reversed_words"
	done
	reversed_words=${reversed_words% }
	x-return
}

[[ $_do_run_unit_tests ]] && {
set-reversed_words     1 2 3
[[ $reversed_words == "3 2 1" ]] || _abort "reversed_words='$reversed_words'"
unset reversed_words
}

# ----------------------------------------------------------------------------

function set-is_FIFO() {
	[[ $# == [01] ]] || abort-function "[option]"
	local option=${1-}

	[[ $option == -[^fqls] ]] &&
	    abort-function -1 "only allows these options: -f -q -l -s"

	is_FIFO=$true			 # default, also called queue
	[[ $option == -[fqls] ]] || return 1

	[[ $option == -f ]] && is_FIFO=$true  # FIFO  aka queue
	[[ $option == -q ]] && is_FIFO=$true  # Queue aka FIFO
	[[ $option == -l ]] && is_FIFO=$false # LIFO  aka stack
	[[ $option == -s ]] && is_FIFO=$false # Stack aka LIFO
	return 0
}

# ---------------------------------

# pop word off left side of named list; return non-0 if list was empty
function set-popped_word-is_last_word--from-list() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	# shellcheck disable=SC2086 # variable may be null
	set-is_FIFO ${1-} && shift
	[[ $# == 1 ]] || abort-function ": pass name of list"

	local  list_name=$1
	[[ -v $list_name ]] || abort-function "$1: '$1' is not set"
	local -n list=$list_name
	set -f
	# shellcheck disable=SC2086 # variable contains multiple values
	set -- $list			# split words apart
	set +f
	[[ $# == 1 ]] && is_last_word=$true || is_last_word=$false
	[[ $# == 0 ]] && popped_word= ||
	if [[ $is_FIFO ]]
	   then popped_word=${1-}; shift # pop left-most word
	   else popped_word=${!#}
		set -f
		# shellcheck disable=SC2068,SC2086
		set -- ${@: 1: $#-1}
		set +f
	fi
	list=$*				# retain the rest of the words
	can-trace-final-test
	[[ $popped_word ]]
}

[[ $_do_run_unit_tests ]] && {
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
[[ $_flags == "$true" ]] || _abort "is_last_word should be set once: $_flags"

  _input=$_numbers
  _words=
while set-popped_word-is_last_word--from-list -l _input
   do	_words="$popped_word $_words"
done
 _words=${_words% }
[[ ! $_input && $_words == "$_numbers" ]] ||
    _abort "set-popped_word-is_last_word--from-list failure: _input='$_input' _words='$_words'"

unset _numbers _input _words popped_word is_last_word
}

#############################################################################
#############################################################################
### (Decimal) arithmetic functions.
#############################################################################
#############################################################################

set-average() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	if [[ $# == 1 && ! $1 =~ ^[0-9]+$ && ( -e $1 || $1 == */* ) ]]
	   then local numbers
		read -r -d '\0' numbers < "$1"
		# shellcheck disable=SC2046,SC2086
		set -- $numbers
	fi

	local values=$*
	local -i count=$#
	[[ $count != 0 ]] || abort-function ": no numbers to average"
	average=$(( ( ${values// /+} + ($count/2) ) / $count ))
	x-return
}

[[ $_do_run_unit_tests ]] && {
declare -i average
set-average 1 2 3; [[ $average == 2 ]] || _abort avg-2
set-average 1 2 9; [[ $average == 4 ]] || _abort avg-4
set-average 1 4 9; [[ $average == 5 ]] || _abort avg-5
unset average
}

# ----------------------------------------------------------------------------

# takes ~140 usec, 7x faster than: bc <<< "$num_1 * $num_2"
set-product() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	[[ $# == 2 && $1 && $2 &&	# catch null parameters
	       ( ($1 =~ ^-?[0-9]*(\.[0-9]*)*$ && $2 =~ ^-?[0-9]+$) ||
		 ($2 =~ ^-?[0-9]*(\.[0-9]*)*$ && $1 =~ ^-?[0-9]+$)    ) ]] ||
	    abort-function "decimal integer"
	if [[ $1 == *.* ]]
	   then local decimal=$1 integer=$2
	   else local decimal=$2 integer=$1
	fi

	declare -g -i product
	if [[ $decimal != *.?* ]]	# not a decimal??
	   then product=$(( ${decimal%.} * $integer ))
		x-return
	fi

	local signs=
	[[ $decimal == -* ]] && decimal=${decimal#-} signs+=-
	[[ $integer == -* ]] && integer=${integer#-} signs+=-

	local integral=${decimal%.*} fraction=${decimal#*.}
	  [[ $integral ]] || integral=0
	local -i scale_factor=$(( 10**${#fraction} ))
	local -i scaled_decimal=$(( $integral*$scale_factor + $fraction ))
	product=$(( ( $scaled_decimal*$integer + $scale_factor/2 ) /
		    $scale_factor ))
	[[ $signs == - ]] && product=-$product
	x-return
}

[[ $_do_run_unit_tests ]] && {
declare -i product
# test secs to msecs
set-product 1000  2.5 ; [[ $product == 2500 ]] || _abort 2.5
set-product 2.5  1000 ; [[ $product == 2500 ]] || _abort 2.5
set-product 2    1000 ; [[ $product == 2000 ]] || _abort 2
set-product 2.   1000 ; [[ $product == 2000 ]] || _abort 2.
set-product  .1  1000 ; [[ $product ==  100 ]] || _abort  .1
set-product -.1  1000 ; [[ $product == -100 ]] || _abort -.1
set-product -.1 -1000 ; [[ $product ==  100 ]] || _abort -.1 -
set-product 0.1 -1000 ; [[ $product == -100 ]] || _abort 0.1 -
set-product 0.01 1000 ; [[ $product ==   10 ]] || _abort 0.01
unset product
}

# ----------------------------------------------------------------------------

# takes ~140 usec, 7x faster than: bc <<< "$n / $d"
set-division() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	local -i width=0 decimal_digits
	[[ $1 == -w ]] && { width=$2; shift 2; }
	[[ $1 == -z ]] && { local zero_pad=$true; shift; } || local zero_pad=
	[[ $1 == -d ]] && { decimal_digits=$2; shift 2; }
	[[ $# == 2 && $1 && $2 &&	# catch null parameters
	   ${decimal_digits-} == [1-9]* && $1$2 =~ ^[-0-9]+$ ]] ||
	    abort-function "[-w # [-z]] -d # integer-numerator int-denominator"

	local -i numerator=$1 denominator=$2
	[[ $denominator =~ ^-?[1-9][0-9]*$ ]] || # can't divide-by-0
	    abort-function "denominator must be non-0 integer"

	local format="%s.%0${decimal_digits}d"

	local signs=
	[[   $numerator == -* ]] &&   numerator=${numerator#-}   signs+=-
	[[ $denominator == -* ]] && denominator=${denominator#-} signs+=-

	local -i multiplier=$(( 10**decimal_digits ))
	local -i whole_number=$((numerator / denominator))
	local -i fraction=$(( ( multiplier*(numerator % denominator)
				+ (denominator / 2) ) / denominator ))
	if (( fraction >= multiplier ))	# fraction rounded up to whole number?
	   then # shellcheck disable=SC2219
		let whole_number+=1
		fraction=0
	fi

	# shellcheck disable=SC2059
	printf -v division "$format" "$whole_number" "$fraction"
	[[ $signs == - ]] && division=-$division

	(( $width != 0 )) && {
	while (( ${#division} > $width ))
	   do	[[ $division == *.* ]] || break
		division=${division%?}
		[[ $division != *. ]] ||
		division=${division%?}
	done
	[[ $zero_pad && $division == *.* ]] && # only if fractional
	while (( ${#division} < $width ))
	   do	division=0$division
	done
	}
	x-return
}

[[ $_do_run_unit_tests ]] && {
sd() { set-division "$@"; }
sd -d 1 -6  3 ; [[ $division == -2.0 ]] || _abort "-6/3  != $division"
sd -d 1 -6 -3 ; [[ $division ==  2.0 ]] || _abort "-6/-3 != $division"
# test minutes to hours
sd -d 2 10 60 ; [[ $division == 0.17 ]] || _abort "10/60 != $division"
sd -d 1 10 60 ; [[ $division == 0.2  ]] || _abort "10/60 != $division"
sd -d 1 59 60 ; [[ $division == 1.0  ]] || _abort "59/60 != $division"
# test error handling
sd -d 1    1 0 |& fgrep -q libsnap.sh: || _abort "1/0 should fail"
sd -d 1  1.1 1 |& fgrep -q libsnap.sh: || _abort "didn't catch non-integer"
sd -d 1  1 1 1 |& fgrep -q libsnap.sh: || _abort "didn't catch too many args"
sd         1 1 |& fgrep -q libsnap.sh: || _abort "didn't catch missing -d#"
sd -d 1 -q 1 1 |& fgrep -q libsnap.sh: || _abort "didn't catch erroneous opt"
sd -d 1      1 |& fgrep -q libsnap.sh: || _abort "missing numerator"
# test -w and -z
sd-w() { set-division -w 5 -z -d 2 "$@"; }
sd-w    9 2; [[ $division == 04.50 ]] || _abort    "9/2 != $division"
sd-w  900 2; [[ $division == 450.0 ]] || _abort  "900/2 != $division"
sd-w 9000 2; [[ $division == 4500  ]] || _abort "9000/2 != $division"
unset division
}

#############################################################################
#############################################################################
### Miscellaneous functions.
#############################################################################
#############################################################################

# like usleep, but takes milliseconds as its argument
function msleep() {
	[[ $# == 1 ]] || abort-function "milliseconds"
	local -i msecs=$1

	local division
	set-division -d 3 "$msecs" 1000
	[[ $division != *-* ]] &&	# avoid negative values
	sleep "$division"		# sleep is a loadable, so fast
}

# ---------------------------------

function sleep-exe() {

	env sleep "$@"
}

# -------------------------------------------------------

function confirm() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	[[ $1 == -n ]] && { echo; shift; }
	assert-not-option "$1"
	local _prompt=$1 default=${2-}

	local y_n status
	case $default in
	   [yY]* ) y_n="Y/n" status=0 ;;
	   [nN]* ) y_n="y/N" status=1 ;;
	   *     ) y_n="y/n" status=  ;;
	esac

	[[ -t 0 ]] || { x-return "$status"; }

	_prompt+=" ($y_n)? "

	local key
	while read -r -n 1 -p "$_prompt" key
	   do	case $key in
		   [yY]* ) status=0 && break ;;
		   [nN]* ) status=1 && break ;;
		   *     ) [[ $status ]] && { x-return $status; } ;;
		esac
		set +x
		echo
	done
	echo

	[[ $status ]] || abort-function "$*: read failure"
	x-return $status
}

# ----------------------------------------------------------------------------

# Test an internal function by passing its name + options + args to our script;
# to show values of global variables it alters, pass: -v "varname(s)"
function run-function() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	local is_procedure=$false	# abort if function "fails"
	[[ $1 == -p ]] && { is_procedure=$true; shift; }
	[[ $1 == -v ]] && { local var_names=$2; shift 2; } || local var_names=
	assert-not-option -o "${1-}"

	local function=$1
	have-cmd "$function" || abort "function '$function' doesn't exist"

	local force_next_function_trace=${Trace:+_}
	$Trace
	"$@"
	local status=$?
	set +x
	echo -e "\nstatus=$status"
	# shellcheck disable=SC2086 # variable contains multiple values
	[[ $var_names ]] && echoEV -1 ${var_names//,/ }
	[[ $status == 0 || $is_procedure ]] || abort -1 "'$*' returned $status"

	[[ $function =~ ^_?(did-)?(set|update|(append|prepend)-to)- ]] ||
	    { x-return $status; }
	local function_prefix=${BASH_REMATCH[0]}

	header "variables set by: $*"
	var_names=${function#"$function_prefix"} ; var_names=${var_names%%--*}
	var_names=${var_names//-/ }
	declare -i max_name_width=0
	for var_name in $var_names
	    do	(( max_name_width <= ${#var_name} )) || continue
		   max_name_width=${#var_name}
	done
	for var_name in $var_names
	    do	set-var_value--for-debugger "$var_name"
		# shellcheck disable=SC2154
		printf "%${max_name_width}s=%s\n" "$var_name" "$var_value"
	done

	x-return $status
}

# ----------------------------------------------------------------------------

# On Ubuntu, install libpcre3-dev to get pcresyntax(3) and pcrepattern(3).
# This may not be reliable with option --null-data .
alias pegrep='grep --perl-regexp'

# ----------------------------------------------------------------------------
# ----------------------------------------------------------------------------
# run-until-timeout: let's you avoid hangs when there are I/O problems
# ----------------------------------------------------------------------------
# ----------------------------------------------------------------------------

killer() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	[[ $# == 3 && $1 == -s && $2 != *[!.0-9]* && $3 != *[!0-9]* ]] ||
	    abort-function "-s decimal-seconds PID"
	local seconds=$2 PID=$3 spec

	sleep "$seconds"
	for spec in HUP TERM INT KILL
	    do	kill -SIG$spec "$PID" || break
		msleep 1
	done &> $dev_null		# PID might already be dead
	x-return
}

# ---------------------------------

_run-echo-output() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	local type=$1

	local -n file=${type}_file
	local value
	[[ -s $file ]] && value=$(< "$file") || { x-return; }
	echo "$value"
	x-return
}

# ---------------------------------

# don't pass a binary, you can't kill a binary that's hung on I/O .
# race condition: the function succeeds, but it's killed as exits: status > 0
function run-until-timeout() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	[[ ${1-} == -s && ${2-} != *[!.0-9]* && ${3-} ]] ||
	    abort-function "-s decimal-seconds function [arg(s)]"
	local seconds=$2 && shift 2

	local stdout_file=$tmp_dir/run-stdout.$BASHPID
	local stderr_file=$tmp_dir/run-stderr.$BASHPID
	"$@" > "$stdout_file" 2> "$stderr_file" &
	local func_PID=$!

	killer -s "$seconds" $func_PID &
	local killer_PID=$!

	wait $func_PID &> $dev_null	# hide shell's error msg when killed
	local status=$?
	kill $killer_PID &> $dev_null	# might have run to completion

	_run-echo-output stdout
	_run-echo-output stderr >&2
	rm "$stdout_file" "$stderr_file" # comment-out to debug
	x-return $status
}

[[ $_do_run_unit_tests ]] && {
pass() { echo "$FUNCNAME"    ; true ; }
fail() { echo "$FUNCNAME" >&2; false; }
hang() { sleep 1000; echo badness; }
rut () { run-until-timeout "$@"; }
out=$(rut -s .001 pass     ) && [[ $out == pass ]] ||_abort "should pass: $out"
out=$(rut -s .001 fail 2>&1) || [[ $out != fail ]] &&_abort "should fail: $out"
out=$(rut -s .001 hang 2>&1) || [[ $out != ""   ]] &&_abort "should hang: $out"
}

# ----------------------------------------------------------------------------

# strip leading tabs (shell script's indent) from $1, and expand remaining tabs
function set-python_script() {
	can-profile-not-trace # use x-return to leave function; can comment-out
	[[ $# == 1 && $1 ]] ||
	    abort-function "takes one arg, got: '$*'" || { x-return 1; }
	python_script=$1

	local leading_tabs='						'
	# shellcheck disable=SC2155
	local line_count=$(grep -c '[a-z]' <<<"$python_script")
	while [[ ${#leading_tabs} != 0 ]]
	   do	# shellcheck disable=SC2155
		local count=$(grep '[a-z]' <<<"$python_script" |
				  grep -c "^$leading_tabs")
		[[ $count == "$line_count" ]] && break
		leading_tabs=${leading_tabs#?}
	done
	true || [[ ${#leading_tabs} != 0 ]] || # allow this
	   warn "$FUNCNAME: we expected python script would be tab-indented"

	python_script=$(echo "$python_script" |
			sed "s/^$leading_tabs//" | expand)
	x-return 0
}

# ----------------------------------------------------------------------------

[[  ${_do_run_unit_tests-} ]] && {
unset _do_run_unit_tests
write-profile-data -k 3
head -v profile.csv
}

true					# we must return 0
