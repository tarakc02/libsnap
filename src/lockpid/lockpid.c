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
#include <stdlib.h>
#include <errno.h>		/* <asm-generic/errno-base.h> on Linux */
#include <getopt.h>
#include <unistd.h>
#include <ctype.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <signal.h>
#include <string.h>

// ===========================================================================
// miscellaneous typedefs/constants/defines/etc
// ===========================================================================

char *lock_dir = "/var/lock";

// exit status is one byte wide; bash exit is >= 128 when died from signal
static const int   unknown_exit_status = 127;
static const int     usage_exit_status = 126;
static const int lock_busy_exit_status = 125; /* copied into libsnap.sh */

typedef int bool;
enum bool { False = 0, True = 1 };

// ===========================================================================
// globals that are set once at startup
// ===========================================================================

const char *argv0;		/* our command name with path stripped */
const char *lock_file = NULL;
const char *lock_pid  = NULL;
const char *lock_pid_new = NULL;

int wait_millisecs = 50;

// ===========================================================================
// our user interface
// ===========================================================================

void
show_usage_and_exit(void)
{
    fprintf(stderr, "\n\
Usage: %s [-d dir] [-p pid] [-P npid] [-w] [-r]  [-q] [-v] file\n\
   cd dir (default '%s'), put 'pid' (default npid else caller PID)\n\
	 into 'file', then exit with 0; but,\n\
      if 'file' already holds PID of another active process, exit with %d;\n\
      if there's any (other) kind of error, exit with errno (typically).\n\
   To change the PID in a lock, use -P (--new-pid).\n\
   To wait for the lock to become available, use -w (--wait).\n\
   To --release the lock, use the -r option (or just delete 'file').\n\
   To not announce when the lock is busy, use the -q (--quiet) option.\n\
   To announce when acquire the lock, use the -v (--verbose) option.\n\
\n\
   NOTE: This command is only suitable for local locks, not networked locks.\n\
\n\
   'file' is locked with flock before checking/writing 'pid', to avoid races.\n\
   To avoid security risks, this command will bomb if 'file' is a symlink.\n\
\n\
", argv0, lock_dir, lock_busy_exit_status);

    exit(usage_exit_status);
}

// ===========================================================================

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
	fprintf(stderr, "\n%s %s: %s: %s\n\n",
		argv0, lock_file, system_call, errno_msg);

    if (errno <= 1)		/* 1 means "lock is busy" */
	errno  = unknown_exit_status;

    exit(errno);
}

// ---------------------------------------------------------------------------

static const struct option
Long_opts[] =
{
    { "directory",	1, NULL, 'd' },
    { "pid",		1, NULL, 'p' },
    { "new-pid",	1, NULL, 'P' },
    { "wait",		0, NULL, 'w' },
    { "quiet",		0, NULL, 'q' },
    { "verbose",	0, NULL, 'v' },
    { "release",	0, NULL, 'r' },
    { NULL,		0, NULL,  0  },
};

bool do_wait	= False;
bool is_quiet	= False;
bool is_verbose = False;
bool do_release = False;
char **lock_fileV;

void
parse_argv_setup_globals(int argc, char * const argv[])
{
    static char *cp;

    cp = strrchr(argv[0], '/');
    if (cp)
	argv0 = ++cp;
    else
	argv0 = argv[0];

    // see getopt(3) for semantics of getopt_long and its arguments
    static const char Opt_string[] = "d:p:P:wqvr";
    while (True)
    {
	int option = getopt_long(argc, argv, Opt_string, Long_opts, NULL);

	if (option < 0)
	    break;

	switch (option)
	{
	case 'd': lock_dir	= optarg; break;
	case 'p': lock_pid	= optarg; break;
	case 'P': lock_pid_new	= optarg; break;
	case 'w': do_wait	= True;   break;
	case 'q': is_quiet	= True;   break;
	case 'v': is_verbose	= True;   break;
	case 'r': do_release	= True;   break;
	case 'h': // fall through to default
	default : show_usage_and_exit();
	}
    }

    lock_fileV = (char **)argv;
    lock_fileV += optind;

    if ( ! lock_fileV[0] || ( lock_fileV[1] && isdigit(lock_fileV[1][0]) ) )
	show_usage_and_exit();

    if (lock_fileV[1]) {
	fprintf(stderr, "%s: multiple locks aren't supported yet\n", argv0);
	exit(usage_exit_status);
    }

    return;

    printf("dir = %s\n", lock_dir);
    printf("pid = %s\n", lock_pid);
    int i;
    for (i = 0; lock_fileV[i];  i++)
	printf("lock_fileV[%d] = %s\n", i, lock_fileV[i]);
}

// ---------------------------------------------------------------------------

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
create_file_for_lock(void)
{
    int fd;

    // let umask control who can reclaim a stale lock
    fd = open(lock_file, O_RDWR | O_CREAT | O_NOFOLLOW, 0666);

    if (fd < 0)
	show_errno_and_exit("open");

    return(fd);
}

// ---------------------------------------------------------------------------

bool
did_lock_file(const int fd)
{
    if (flock(fd, LOCK_EX | LOCK_NB) == 0)
	return(True);
	    
    if (errno == EWOULDBLOCK) {
	if (! is_quiet && ! do_wait)
	    printf("lock '%s' is busy\n", lock_file);
	return(False);
    }

    show_errno_and_exit("flock");
    exit(1);				// make gcc happy
}

// ---------------------------------------------------------------------------

bool
does_file_hold_active_pid(const int fd)
{
    char line[16];
    pid_t lock_pid;

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

    if (getppid() == lock_pid) {
	if (lock_pid_new)		// want to replace PID?
	    return(False);
	// don't send this to stderr, so easy to ignore
	printf("%s %s: already hold lock\n", argv0, lock_file);
	exit(0);
    } 

    if (! is_quiet && ! do_wait)
	printf("process %d holds lock '%s'\n", lock_pid, lock_file);

    return(True);
}

// ---------------------------------------------------------------------------

void
write_pid_to_file(const int fd)
{
    char line[16];
    pid_t pid = (lock_pid) ? atoi(lock_pid) : getppid();
    pid  =  (lock_pid_new) ? atoi(lock_pid_new) : pid;

    if (lseek(fd, 0, SEEK_SET) < 0)
	show_errno_and_exit("lseek");

    if (ftruncate(fd, 0) < 0)
	show_errno_and_exit("ftruncate");
    
    // format per http://www.pathname.com/fhs/2.2/fhs-5.9.html
    sprintf(line, "%10d\n", pid);

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

    if (chdir(lock_dir) < 0)
	show_errno_and_exit("chdir");

    lock_file = lock_fileV[0];

    if (do_release)
	release_file_and_exit();

    while (True) {
	fd = create_file_for_lock();

	if ( ! did_lock_file(fd) || does_file_hold_active_pid(fd) ) {
	    if (do_wait) {
		close_file(fd);
		usleep(wait_millisecs * 1024);
		continue;
	    } else
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
