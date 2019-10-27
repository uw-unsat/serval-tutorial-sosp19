#include <asm/csr.h>
#include <asm/csr_bits/status.h>
#include <asm/mcall.h>
#include <asm/pmp.h>
#include <asm/ptrace.h>
#include <asm/sbi.h>
#include <asm/tlbflush.h>
#include <uapi/monitor/syscalls.h>

noreturn static void supervisor_init(unsigned int, phys_addr_t);
extern char _payload_start[], _payload_end[];

noreturn void main(unsigned int hartid, phys_addr_t dtb)
{
        extern void init_dict(void);

        init_dict();
        mcall_init(dtb);
        pr_info("Hello from ToyMon!\n");
        supervisor_init(hartid, dtb);
}


noreturn static void supervisor_init(unsigned int hartid, phys_addr_t dtb)
{
        struct pt_regs regs = {
                .a0 = hartid,
                .a1 = dtb,
        };

        /* mret to S-mode */
        csr_write(mstatus, SR_MPP_S);

        /* entry to supervisor_main */
        csr_write(mepc, (uintptr_t) _payload_start);

        /* PMP to allow S-mode access only to supervisor payload */
        csr_write(pmpcfg0, 0);
        csr_write(pmpcfg2, 0);
        /* NB: the -1 here is because of a bug in QEMU's PMP implementation
           when S-mode tries to execute the first instruction in a PMP region */
        pmpaddr_write(pmpaddr0, (uintptr_t) _payload_start - 1);
        pmpaddr_write(pmpaddr1, (uintptr_t) _payload_end);
        pmpcfg_write(pmp1cfg, PMPCFG_A_TOR | PMPCFG_R | PMPCFG_W | PMPCFG_X);
        local_flush_tlb_all();

        /* "return" to supervisor */
        mret_with_regs(&regs);
}

extern long sys_dict_get(void);
extern long sys_dict_set(long);
extern long sys_change_user(long);

void do_trap_ecall_s(struct pt_regs *regs)
{
        long nr = regs->a7, r = -ENOSYS;

        csr_write(mepc, csr_read(mepc) + 4);

        switch (nr) {
        case SBI_FIRST ... SBI_LAST:
                r = do_mcall(regs);
                break;
        case __NR_dict_get:
                r = sys_dict_get();
                break;
        case __NR_dict_set:
                r = sys_dict_set(regs->a0);
                break;
        case __NR_change_user:
                r = sys_change_user(regs->a0);
                break;
        }

        regs->a0 = r;
}
