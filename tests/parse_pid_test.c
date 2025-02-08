#include "minitalk.h"

#include <limits.h>

static int	expect_valid(const char *text, pid_t expected)
{
	pid_t	value;

	value = 0;
	if (!mt_parse_pid(text, &value))
		return (0);
	return (value == expected);
}

static int	expect_invalid(const char *text)
{
	pid_t	value;

	value = 42;
	return (!mt_parse_pid(text, &value));
}

int	main(void)
{
	if (!expect_valid("2", (pid_t)2)
		|| !expect_valid("0002", (pid_t)2)
		|| !expect_valid("1000000", (pid_t)1000000)
		|| !expect_valid("2147483647", (pid_t)INT_MAX)
		|| !expect_invalid(NULL)
		|| !expect_invalid("")
		|| !expect_invalid("0")
		|| !expect_invalid("1")
		|| !expect_invalid("-2")
		|| !expect_invalid("2x")
		|| !expect_invalid("2147483648")
		|| mt_parse_pid("2", NULL))
		return (1);
	return (0);
}
