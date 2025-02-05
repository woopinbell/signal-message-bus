#ifndef MINITALK_H
# define MINITALK_H

# include <stddef.h>
# include <sys/types.h>

void	mt_putstr_fd(const char *text, int fd);
void	mt_putnbr_fd(pid_t number, int fd);
size_t	mt_strlen(const char *text);

#endif
