TEST_KERNEL_ELF       := $(O)/monitor/kernel.elf

TEST_KERNEL_OBJS      := $(call object,$(wildcard monitor/kernel/*.c monitor/kernel/*.S))

$(TEST_KERNEL_ELF): $(KERNEL_LDS) $(KERNEL_BOOT_OBJS) $(KERNEL_OBJS) $(TEST_KERNEL_OBJS)
	$(QUIET_LD)$(LD) -o $@ $(LDFLAGS) -T $^
	$(Q)$(OBJDUMP) -S $@ > $(basename $@).asm
