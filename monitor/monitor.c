#include <asm/csr.h>
#include <asm/csr_bits/status.h>
#include <asm/mcall.h>
#include <asm/pmp.h>
#include <asm/ptrace.h>
#include <asm/sbi.h>
#include <asm/tlbflush.h>
#include <uapi/monitor/syscalls.h>


unsigned long current_user;

long dictionary[MAXUSER];

void init_dict(void)
{
    current_user = 0;
    for (int i = 0; i < MAXUSER; i++) {
        dictionary[i] = 0;
    }
}

long sys_dict_get(void)
{
    if (current_user < MAXUSER)
        return dictionary[current_user];

    return -1;
}

long sys_dict_set(long value)
{
    if (current_user < MAXUSER) {
        dictionary[current_user] = value;
        return 0;
    }

    return -1;
}

long sys_change_user(long newuser)
{
    current_user = newuser;
    return 0;
}
