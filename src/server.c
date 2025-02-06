#define _POSIX_C_SOURCE 200809L

#include "minitalk.h"

#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

static volatile sig_atomic_t	g_current_byte;
static volatile sig_atomic_t	g_received_bits;
static volatile sig_atomic_t	g_client_pid;
static volatile sig_atomic_t	g_line_started;
static int						g_response_socket = -1;
static int						g_server_bound;
static char						g_server_path[MT_RESPONSE_PATH_SIZE];

static void	cleanup_server(void)
{
	if (g_response_socket != -1)
		close(g_response_socket);
	g_response_socket = -1;
	if (g_server_bound && g_server_path[0] != '\0')
		unlink(g_server_path);
	g_server_bound = 0;
	g_server_path[0] = '\0';
}

static void	reset_session(int close_partial_line)
{
	if (close_partial_line && g_line_started)
		write(STDOUT_FILENO, "\n", 1);
	g_current_byte = 0;
	g_received_bits = 0;
	g_client_pid = 0;
	g_line_started = 0;
}

static void	flush_byte(unsigned char output)
{
	if (output == '\0')
	{
		write(STDOUT_FILENO, "\n", 1);
		reset_session(0);
	}
	else
	{
		write(STDOUT_FILENO, &output, 1);
		g_line_started = 1;
	}
}

static void	handle_bit(int signal, siginfo_t *info, void *context)
{
	unsigned char	output;
	int				saved_errno;

	saved_errno = errno;
	(void)context;
	if (info == NULL || info->si_pid <= 0)
	{
		errno = saved_errno;
		return ;
	}
	if (g_client_pid != 0 && g_client_pid != info->si_pid)
	{
		if (kill((pid_t)g_client_pid, 0) == -1 && errno == ESRCH)
			reset_session(1);
		else
		{
			kill(info->si_pid, MT_NACK_SIGNAL);
			errno = saved_errno;
			return ;
		}
	}
	if (g_client_pid == 0)
		g_client_pid = info->si_pid;
	g_current_byte <<= 1;
	if (signal == MT_ONE_SIGNAL)
		g_current_byte |= 1;
	g_received_bits++;
	if (g_received_bits == 8)
	{
		output = (unsigned char)g_current_byte;
		flush_byte(output);
		g_current_byte = 0;
		g_received_bits = 0;
	}
	if (kill(info->si_pid, MT_ACK_SIGNAL) == -1 && errno == ESRCH)
		reset_session(1);
	errno = saved_errno;
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

static int	prepare_response_channel(void)
{
	struct sockaddr_un	address;

	if (mt_response_path(g_server_path, sizeof(g_server_path), "server",
			getpid()) == -1 || remove_stale_socket(g_server_path) == -1)
		return (-1);
	g_response_socket = socket(AF_UNIX, SOCK_DGRAM, 0);
	if (g_response_socket == -1
		|| set_nonblocking_close_on_exec(g_response_socket) == -1)
		return (-1);
	memset(&address, 0, sizeof(address));
	address.sun_family = AF_UNIX;
	if (mt_strlen(g_server_path) >= sizeof(address.sun_path))
	{
		errno = ENAMETOOLONG;
		return (-1);
	}
	memcpy(address.sun_path, g_server_path, mt_strlen(g_server_path) + 1);
	if (bind(g_response_socket, (struct sockaddr *)&address,
			sizeof(address)) == -1)
		return (-1);
	g_server_bound = 1;
	return (0);
}

static int	install_signal_handlers(void)
{
	struct sigaction	action;

	action.sa_sigaction = handle_bit;
	sigemptyset(&action.sa_mask);
	sigaddset(&action.sa_mask, MT_ZERO_SIGNAL);
	sigaddset(&action.sa_mask, MT_ONE_SIGNAL);
	action.sa_flags = SA_SIGINFO;
	if (sigaction(MT_ZERO_SIGNAL, &action, NULL) == -1)
		return (-1);
	if (sigaction(MT_ONE_SIGNAL, &action, NULL) == -1)
		return (-1);
	return (0);
}

int	main(void)
{
	if (prepare_response_channel() == -1 || atexit(cleanup_server) != 0)
	{
		cleanup_server();
		mt_putstr_fd("server: failed to create response channel\n",
			STDERR_FILENO);
		return (1);
	}
	if (install_signal_handlers() == -1)
	{
		mt_putstr_fd("server: failed to install signal handlers\n", STDERR_FILENO);
		return (1);
	}
	mt_putnbr_fd(getpid(), STDOUT_FILENO);
	write(STDOUT_FILENO, "\n", 1);
	while (1)
		pause();
	return (0);
}
