/**********************************************************************
 ** acquire a lock (which could have been stale) in race-free manner **
 **********************************************************************/

/*

The Martus(tm) free, social justice documentation and
monitoring software. Copyright (C) 2002,2003, Beneficent
Technology, Inc. (Benetech).

Martus is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later
version with the additions and exceptions described in the
accompanying Martus license file entitled "license.txt".

It is distributed WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, including warranties of fitness of purpose or
merchantability.  See the accompanying Martus License and
GPL license for more details on the required license terms
for this software.

You should have received a copy of the GNU General Public
License along with this program; if not, write to the Free
Software Foundation, Inc., 59 Temple Place - Suite 330,
Boston, MA 02111-1307, USA.

*/

#define _GNU_SOURCE		/* want O_NOFOLLOW option to open(2) */

#include <stdio.h>
#include <ctype.h>
#include <errno.h>		/* <asm-generic/errno-base.h> on Linux */
#include <getopt.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

// ===========================================================================
// miscellaneous typedefs/constants/defines/etc
// ===========================================================================

char *default_lock_dir = "/var/lock";
char *lock_dir;
pid_t pid, new_pid;

// exit status is one byte wide; bash exit is >= 128 when died from signal
static const int   unknown_exit_status = 127;
static const int     usage_exit_status = 126;
static const int lock_busy_exit_status = 125; /* copied into libsnap.sh */
static const int hold_lock_exit_status = 124;

typedef int bool;
enum bool { False = 0, True = 1 };

// ===========================================================================
// globals that are set once at startup
// ===========================================================================

const char *argv0;		/* our command name with path stripped */

bool do_release = False;
bool do_wait	= False;
bool is_quiet	= False;
bool is_verbose = False;
bool is_error_to_hold_lock = False;

char *default_sleep_ms_string = "20.0";
useconds_t sleep_microsecs;
time_t end_wait_time = 0;

// ===========================================================================
// support functions for option/argument parsing
// ===========================================================================

char * const *lock_fileV;
const  char  *lock_file = NULL;

void
show_errno_and_exit(const char *system_call)
{
    char *errno_msg;

    if (errno == ELOOP && strcmp(system_call, "open") == 0)
	errno_msg = "unsafe for lockfile to be a symlink";
    else
	errno_msg = strerror(errno);

    if (!lock_file)
	lock_file = "";

    if (system_call)
	fprintf(stderr, "\n%s%s %s: %s: %s\n\n",
		argv0, (do_release) ? " -r" : "", lock_file,
		system_call, errno_msg);

    if (errno <= 0)			// not sure this can happen
	errno  = unknown_exit_status;

    exit(errno);
}

// ---------------------------------------------------------------------------

bool
is_integer(const char *string) {
    if (! string)
	return False;

    char *endp;
    (void)strtod(string, &endp);
    return(endp[0] ? False : True);
}

// --------------------------------------------

float
string_to_float(const char *string) {
    char *endp;
    float number = strtof(string, &endp);
    if (endp[0]) {			// didn't parse whole string?
	fprintf(stderr, "%s: '%s' is an invalid floating point number\n",
		argv0, string);
	exit(usage_exit_status);
    }
    return number;
}

// --------------------------------------------

time_t
time_string_to_secs(const char *string) {
    char *endp;
    int num = strtod(string, &endp);
    int type = endp[0];
    while (True)
    {
	if (type == 's' || ! type) break; // seconds? (the default)
	num *= 60;
	if (type == 'm') break;		// minutes?
	num *= 60;
	if (type == 'h') break;		// hours?
	num *= 24;
	if (type == 'd') break;		// days?
	fprintf(stderr, "%s: invalid time modifier '%c'\n", argv0, num);
	exit(usage_exit_status);
    }
    return (time_t) num;
}

// ===========================================================================
// our user interface
// ===========================================================================

void
show_usage_and_exit(int option)
{
    fprintf(stderr, "\n\
Usage: %s [-d dir] [-p pid] [-P npid] [-w] [-r]  [-q] [-v] file\n\
   cd 'dir' (default %s), put 'pid' (default npid, else caller PID)\n\
	 into 'file', then exit with 0; but,\n\
      if 'file' already holds PID of another active process, exit with %d;\n\
      if there's any (other) kind of error, exit with errno (typically).\n\
   To over-ride the default lock directory, use -d (--directory).\n\
   To change the PID in a lock (i.e. borrow lock), use -P (--new-pid).\n\
   To wait for the lock to become available, use -w (--wait);\n\
      this checks every %s millisecs, change it with -s (--sleep-msecs);\n\
      if this waits longer than -W (--wait-expiration) seconds (optionally\n\
      followed by s, m, h, d [for secs, mins, hours, days]), exit with %d.\n\
   If -H (--not-hold) and we hold the lock, exit with %d.\n\
   To release a lock only if you own it, use -r (--release).\n\
   To not announce when the lock is busy, use the -q (--quiet) option.\n\
   To announce when acquire the lock, use the -v (--verbose) option.\n\
\n\
   If failed kernel call, exit with errno.\n\
\n\
   NOTE: This command is only suitable for local locks, not networked locks.\n\
\n\
   'file' is locked with flock before checking/writing 'pid', to avoid races.\n\
   To avoid security risks, this command will bomb if 'file' is a symlink.\n\
\n\
", argv0, lock_dir, lock_busy_exit_status,
   default_sleep_ms_string, lock_busy_exit_status, hold_lock_exit_status);

    exit( (option == 'h') ? 0 : usage_exit_status );
}

// ---------------------------------------------------------------------------

static const struct option
Long_opts[] =
{
    { "directory",	1, NULL, 'd' },
    { "pid",		1, NULL, 'p' },
    { "new-pid",	1, NULL, 'P' },
    { "sleep-msecs",	1, NULL, 's' },
    { "wait-expiration",1, NULL, 'W' },
    { "wait",		0, NULL, 'w' },
    { "quiet",		0, NULL, 'q' },
    { "verbose",	0, NULL, 'v' },
    { "not-hold",	0, NULL, 'H' },
    { "release",	0, NULL, 'r' },
    { NULL,		0, NULL,  0  },
};

// ===========================================================================

void
parse_argv_setup_globals(int argc, char * const argv[])
{
    static char *cp;

    cp = strrchr(argv[0], '/');
    if (cp)
	argv0 = ++cp;
    else
	argv0 = argv[0];

    const char *PID_string	= NULL;
    const char *PID_string_new	= NULL;
    const char *sleep_ms_string = NULL;
    const char *wait_expiration_string = NULL;
    // see getopt(3) for semantics of getopt_long and its arguments
    static const char Opt_string[] = "d:p:P:s:W:wqvHrh";
    lock_dir = default_lock_dir;
    while (True)
    {
	int option = getopt_long(argc, argv, Opt_string, Long_opts, NULL);

	if (option < 0)
	    break;

	switch (option)
	{
	case 'd': lock_dir		= optarg; break;
	case 'p': PID_string		= optarg; break;
	case 'P': PID_string_new	= optarg; break;
	case 's': sleep_ms_string	= optarg; break;
	case 'W': wait_expiration_string= optarg; break;
	case 'w': do_wait		= True;   break;
	case 'q': is_quiet		= True;   break;
	case 'v': is_verbose		= True;   break;
	case 'H': is_error_to_hold_lock	= True;   break;
	case 'r': do_release		= True;   break;
	case 'h': // fall through to default
	default : show_usage_and_exit(option);
	}
    }

    lock_fileV = (char **)argv;
    lock_fileV += optind;

    if (! lock_fileV[0])
	show_usage_and_exit(0);

    if ( is_integer(lock_fileV[0]) ) {
	fprintf(stderr, "%s: lock filename can't be an integer\n", argv0);
	exit(usage_exit_status);
    }

    if ( is_integer(lock_fileV[1]) )	// does 2nd arg look like a PID?
	show_usage_and_exit(0);		// that was the old syntax

    if (lock_fileV[1]) {
	fprintf(stderr, "%s: multiple locks aren't supported yet\n", argv0);
	exit(usage_exit_status);
    }

    pid = (PID_string) ? atoi(PID_string) : getppid();
    new_pid = (PID_string_new) ? atoi(PID_string_new) : 0;

    if (sleep_ms_string)
	do_wait = True;
    else
	sleep_ms_string = default_sleep_ms_string;
    if (wait_expiration_string) {
	do_wait  = True;
	int secs = time_string_to_secs(wait_expiration_string);
	end_wait_time = time(NULL) + secs;
    }
    if (do_wait)
	sleep_microsecs = (useconds_t) (string_to_float(sleep_ms_string)*1000);

    return;

    printf("dir = %s\n", lock_dir);
    printf("pid = %s\n", PID_string);
    int i;
    for (i = 0; lock_fileV[i];  i++)
	printf("lock_fileV[%d] = %s\n", i, lock_fileV[i]);
}

// ===========================================================================
// the functions to implement lock-file management
// ===========================================================================

void
release_file_and_exit(void)
{
    if (access(lock_file, W_OK) == 0 && unlink(lock_file) == 0)
	exit(0);
    else
	show_errno_and_exit("unlink");
}

// ---------------------------------------------------------------------------

int
open_lock_file(void)
{
    int fd;
    bool did_retry = False;

    int flags = O_RDWR | O_NOFOLLOW;
    if (! do_release)
	flags |= O_CREAT;

retry:
    // let umask control who can reclaim a stale lock
    fd = open(lock_file, flags, 0666);
    if (fd < 0) {
	if (! did_retry && errno == EACCES && getuid() == 0) { // FUSE or NFS?
	    chown(lock_file, 0, 0);
	    did_retry = True;
	    goto retry;
	}
	show_errno_and_exit("open");
    }

    return(fd);
}

// ---------------------------------------------------------------------------

bool
did_lock_file(const int fd)
{
flock:
    if (flock(fd, LOCK_EX | LOCK_NB) == 0)
	return(True);
	    
    if (errno == EWOULDBLOCK) {
	if (do_release) {
	    usleep(sleep_microsecs);
	    goto flock;
	}
	if (! is_quiet && ! do_wait)
	    printf("lock '%s' is busy\n", lock_file);
	return(False);
    }

    show_errno_and_exit("flock");
    exit(1);				// make gcc happy
}

// ---------------------------------------------------------------------------

pid_t lock_pid = -1;

void
exit_for_busy_lock(void)
{
    if (! is_quiet)
	printf("process %d holds lock '%s'\n", lock_pid, lock_file);
    exit(lock_busy_exit_status);
}

// ---------------------------------------------------------------------------

bool
does_file_hold_active_pid(const int fd)
{
    char line[16];

    int n = read(fd, line, sizeof(line));
    if (n < 0)
	show_errno_and_exit("read");
    if (n == 0)
	return(False);

    if (sscanf(line, "%d", &lock_pid) != 1)
	return(False);

    if (kill(lock_pid, 0) < 0) {
	if (errno == ESRCH)
	    return(False);

	// if EPERM, process exists (but isn't owned by us) so fall through
	if (errno != EPERM)
	    show_errno_and_exit("kill");
    }

    if (pid == lock_pid) {
	if (do_release)
	    release_file_and_exit();
	if (new_pid)			// want to replace PID?
	    return(False);
	// don't send this to stderr, so easy to ignore
	printf("%s %s: already hold lock\n", argv0, lock_file);
	exit(is_error_to_hold_lock ? hold_lock_exit_status : 0);
    } 

    return(True);
}

// ---------------------------------------------------------------------------

void
write_pid_to_file(const int fd)
{
    char line[16];

    if (lseek(fd, 0, SEEK_SET) < 0)
	show_errno_and_exit("lseek");

    if (ftruncate(fd, 0) < 0)
	show_errno_and_exit("ftruncate");
    
    // format per http://www.pathname.com/fhs/2.2/fhs-5.9.html
    sprintf(line, "%10d\n", (new_pid) ? new_pid : pid);

    if ( write(fd, line, strlen(line)) != strlen(line) ) {
	int write_errno = errno;

	ftruncate(fd, 0);	/* delete possibly-partial PID */
	errno = write_errno;
	show_errno_and_exit("write");
    }
}

// ---------------------------------------------------------------------------

void
close_file(const int fd)
{
    if (close(fd) < 0) {
	int close_errno = errno;

	unlink(lock_file);	/* file contents might be mangled */
	errno = close_errno;
	show_errno_and_exit("close");
    }
}

// ---------------------------------------------------------------------------

int
main(int argc, char *argv[])
{
    int fd;

    parse_argv_setup_globals(argc, (char * const *)argv);

    lock_file = lock_fileV[0];

    // don't chdir if caller's lock_file contains a '/', unless --directory
    if ( ( !strchr(lock_file, '/') || strcmp(lock_dir, default_lock_dir) ) &&
	 chdir(lock_dir) < 0 )
	show_errno_and_exit("chdir");

    while (True) {
	fd = open_lock_file();

	if ( ! did_lock_file(fd) || does_file_hold_active_pid(fd) ) {
	    if (do_wait) {
		close_file(fd);
		usleep(sleep_microsecs);
		if (end_wait_time != 0 && time(NULL) > end_wait_time)
		    exit_for_busy_lock();
		continue;
	    } else
		exit_for_busy_lock();
	}

	if (do_release) {
	    fprintf(stderr, "%s -r %s: file contains pid %d, not ours\n", 
		    argv0, lock_file, lock_pid);
	    exit(lock_busy_exit_status);
	}

	write_pid_to_file(fd);
	close_file(fd);
	break;
    }

    if (is_verbose)
	printf("caller successfully acquired lock '%s'\n", lock_file);

    return(0);
}
