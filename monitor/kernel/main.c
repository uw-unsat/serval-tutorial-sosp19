#include <sys/of.h>
#include <asm/sbi.h>
#include <asm/processor.h>
#include <asm/page.h>
#include <asm/csr.h>
#include <sys/console.h>
#include <sys/init.h>
#include <sys/sections.h>
#include <sys/string.h>

#define CHECK(e) BUG_ON((e) != 0)

extern long sys_dict_get(void);
extern long sys_dict_set(long);
extern long sys_change_user(long);

noreturn void main(unsigned int hartid, phys_addr_t dtb)
{
        sbi_console_init(BRIGHT_MAGENTA);
        pr_info("Hello from kernel!\n");

        pr_info("change_user(0)\n");
        CHECK(sys_change_user(0));
        pr_info("dict_set(5)\n");
        CHECK(sys_dict_set(5));
        pr_info("dict_get() -> %ld\n", sys_dict_get());

        pr_info("change_user(3)\n");
        CHECK(sys_change_user(3));
        pr_info("dict_set(2)\n");
        CHECK(sys_dict_set(2));
        pr_info("dict_get -> %ld\n", sys_dict_get());

        pr_info("change_user(0)\n");
        CHECK(sys_change_user(0));
        pr_info("dict_get -> %ld\n", sys_dict_get());

        sbi_shutdown();
        for (;;)
                wait_for_interrupt();
}
