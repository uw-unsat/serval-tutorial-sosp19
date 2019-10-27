#include <io/kbuild.h>
#include <sys/errno.h>
#include <uapi/monitor/syscalls.h>
#include <asm/csr_bits/edeleg.h>
#include <asm/csr_bits/pmpcfg.h>

void asm_offsets(void)
{
        DEFINE(CONFIG_BOOT_CPU, CONFIG_BOOT_CPU);

        DEFINE(__NR_dict_get, __NR_dict_get);
        DEFINE(__NR_dict_set, __NR_dict_set);
        DEFINE(__NR_change_user, __NR_change_user);

        DEFINE(MAXUSER, MAXUSER);

        DEFINE(EXC_ECALL_S, EXC_ECALL_S);
}
