#ifndef __SYSCALL
#define __SYSCALL(x, y)
#endif

/* Max number */
#define MAXUSER 4

/* Start syscalls from 10, reserve 0-9 for SBI */

#define __NR_dict_get 10
__SYSCALL(__NR_dict_get, sys_dict_get)

#define __NR_dict_set 11
__SYSCALL(__NR_dict_set, sys_dict_set)

#define __NR_change_user 12
__SYSCALL(__NR_change_user, sys_change_user)
