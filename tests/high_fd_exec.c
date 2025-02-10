#define _POSIX_C_SOURCE 200809L

#include <fcntl.h>
#include <sys/select.h>
#include <unistd.h>

int	main(int argc, char **argv)
{
	int	fd;

	if (argc < 2)
		return (2);
	fd = -1;
	while (fd < FD_SETSIZE - 1)
	{
		fd = open("/dev/null", O_RDONLY);
		if (fd == -1)
			return (1);
	}
	execv(argv[1], &argv[1]);
	return (127);
}
