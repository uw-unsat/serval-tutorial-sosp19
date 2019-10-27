MONITOR_ELF      := $(O)/monitor.elf

MONITOR_OBJS     := $(call object,$(wildcard monitor/*.c monitor/*.S))
MONITOR_OBJS     += $(O)/monitor/kernel.bin.o

include monitor/kernel/kernel.mk
include monitor/verif/verif.mk

$(MONITOR_ELF): $(BIOS_LDS) $(BIOS_BOOT_OBJS) $(BIOS_OBJS) $(KERNEL_OBJS) $(MONITOR_OBJS)
	$(QUIET_LD)$(LD) -o $@ $(LDFLAGS) -T $^

qemu-monitor: $(MONITOR_ELF)
	$(QEMU) $(QEMU_OPTS) -kernel $<

spike-toymon: $(MONITOR_ELF)
	$(SPIKE) $(SPIKE_OPTS) $<

ALL             += $(MONITOR_ELF)

PHONY           += qemu-monitor spike-toymon
