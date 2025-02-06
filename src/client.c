#define _POSIX_C_SOURCE 200809L

#include "minitalk.h"

#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#define SEND_ERROR 1
#define SEND_TIMEOUT 2
#define SEND_REJECTED 3

static volatile sig_atomic_t	g_ack_received;
static volatile sig_atomic_t	g_timed_out;
static volatile sig_atomic_t	g_rejected;
static int						g_response_socket = -1;
static char						g_client_path[MT_RESPONSE_PATH_SIZE];

static void	cleanup_response_socket(void)
{
	if (g_response_socket != -1)
		close(g_response_socket);
	g_response_socket = -1;
	if (g_client_path[0] != '\0')
		unlink(g_client_path);
	g_client_path[0] = '\0';
}

static void	wait_signal_gap(void)
{
	struct timespec	remaining;

	remaining.tv_sec = 0;
	remaining.tv_nsec = MT_SIGNAL_GAP_US * 1000L;
	while (nanosleep(&remaining, &remaining) == -1 && errno == EINTR)
		;
}

static void	handle_client_signal(int signal)
{
	if (signal == MT_ACK_SIGNAL)
		g_ack_received = 1;
	else if (signal == MT_NACK_SIGNAL)
		g_rejected = 1;
	else if (signal == SIGALRM)
		g_timed_out = 1;
}

static int	install_client_handlers(void)
{
	struct sigaction	action;

	action.sa_handler = handle_client_signal;
	sigemptyset(&action.sa_mask);
	action.sa_flags = 0;
	if (sigaction(MT_ACK_SIGNAL, &action, NULL) == -1)
		return (-1);
	if (sigaction(SIGALRM, &action, NULL) == -1)
		return (-1);
	if (sigaction(MT_NACK_SIGNAL, &action, NULL) == -1)
		return (-1);
	return (0);
}

static int	set_nonblocking_close_on_exec(int fd)
{
	int	flags;

	flags = fcntl(fd, F_GETFL);
	if (flags == -1 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) == -1)
		return (-1);
	flags = fcntl(fd, F_GETFD);
	if (flags == -1 || fcntl(fd, F_SETFD, flags | FD_CLOEXEC) == -1)
		return (-1);
	return (0);
}

static int	remove_stale_socket(const char *path)
{
	struct stat	info;

	if (lstat(path, &info) == -1)
	{
		if (errno == ENOENT)
			return (0);
		return (-1);
	}
	if (!S_ISSOCK(info.st_mode) || info.st_uid != getuid())
	{
		errno = EACCES;
		return (-1);
	}
	return (unlink(path));
}

static int	bind_client_socket(void)
{
	struct sockaddr_un	address;

	if (mt_response_path(g_client_path, sizeof(g_client_path), "client",
			getpid()) == -1 || remove_stale_socket(g_client_path) == -1)
		return (-1);
	g_response_socket = socket(AF_UNIX, SOCK_DGRAM, 0);
	if (g_response_socket == -1
		|| set_nonblocking_close_on_exec(g_response_socket) == -1)
		return (-1);
	memset(&address, 0, sizeof(address));
	address.sun_family = AF_UNIX;
	if (mt_strlen(g_client_path) >= sizeof(address.sun_path))
	{
		errno = ENAMETOOLONG;
		return (-1);
	}
	memcpy(address.sun_path, g_client_path, mt_strlen(g_client_path) + 1);
	if (bind(g_response_socket, (struct sockaddr *)&address,
			sizeof(address)) == -1)
		return (-1);
	return (0);
}

static int	send_bit(pid_t server_pid, int bit, const sigset_t *old_mask)
{
	int	signal;

	signal = MT_ZERO_SIGNAL;
	if (bit != 0)
		signal = MT_ONE_SIGNAL;
	g_ack_received = 0;
	g_timed_out = 0;
	g_rejected = 0;
	if (kill(server_pid, signal) == -1)
		return (SEND_ERROR);
	alarm(MT_ACK_TIMEOUT_SECONDS);
	while (!g_ack_received && !g_timed_out && !g_rejected)
		sigsuspend(old_mask);
	alarm(0);
	if (g_rejected)
		return (SEND_REJECTED);
	if (g_timed_out)
		return (SEND_TIMEOUT);
	wait_signal_gap();
	return (0);
}

static int	send_byte(pid_t server_pid, unsigned char byte,
		const sigset_t *old_mask)
{
	int	status;
	int	shift;

	shift = 7;
	while (shift >= 0)
	{
		status = send_bit(server_pid, (byte >> shift) & 1, old_mask);
		if (status != 0)
			return (status);
		shift--;
	}
	return (0);
}

static int	report_send_status(int status)
{
	if (status == SEND_TIMEOUT)
		mt_putstr_fd("client: timed out waiting for acknowledgement\n",
			STDERR_FILENO);
	else if (status == SEND_REJECTED)
		mt_putstr_fd("client: server is busy with another sender\n",
			STDERR_FILENO);
	else
		mt_putstr_fd("client: failed to send signal\n", STDERR_FILENO);
	return (1);
}

int	main(int argc, char **argv)
{
	pid_t	server_pid;
	sigset_t	blocked;
	sigset_t	wait_mask;
	int		status;
	size_t	index;

	if (argc != 3)
	{
		mt_putstr_fd("usage: ./client <server_pid> <message>\n", STDERR_FILENO);
		return (1);
	}
	if (!mt_parse_pid(argv[1], &server_pid) || kill(server_pid, 0) == -1)
	{
		mt_putstr_fd("client: invalid server pid\n", STDERR_FILENO);
		return (1);
	}
	if (install_client_handlers() == -1)
	{
		mt_putstr_fd("client: failed to install signal handlers\n",
			STDERR_FILENO);
		return (1);
	}
	if (bind_client_socket() == -1 || atexit(cleanup_response_socket) != 0)
	{
		cleanup_response_socket();
		mt_putstr_fd("client: failed to create response channel\n",
			STDERR_FILENO);
		return (1);
	}
	sigemptyset(&blocked);
	sigaddset(&blocked, MT_ACK_SIGNAL);
	sigaddset(&blocked, MT_NACK_SIGNAL);
	sigaddset(&blocked, SIGALRM);
	if (sigprocmask(SIG_BLOCK, &blocked, &wait_mask) == -1)
	{
		mt_putstr_fd("client: failed to block acknowledgement signal\n",
			STDERR_FILENO);
		return (1);
	}
	sigdelset(&wait_mask, MT_ACK_SIGNAL);
	sigdelset(&wait_mask, MT_NACK_SIGNAL);
	sigdelset(&wait_mask, SIGALRM);
	index = 0;
	while (argv[2][index] != '\0')
	{
		status = send_byte(server_pid, (unsigned char)argv[2][index],
				&wait_mask);
		if (status != 0)
			return (report_send_status(status));
		index++;
	}
	status = send_byte(server_pid, '\0', &wait_mask);
	if (status != 0)
		return (report_send_status(status));
	return (0);
}
