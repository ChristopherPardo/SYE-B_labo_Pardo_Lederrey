#include <syscall.h>

#include <libc.h>
#include <unistd.h>

int renice(pid_t pid, uint32_t priority)
{
	return sys_renice(pid, priority);
}