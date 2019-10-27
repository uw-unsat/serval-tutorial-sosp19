include config.mk
include scripts/Makefile.lib

# no built-in rules and variables
MAKEFLAGS       += --no-builtin-rules --no-builtin-variables

BASE_CFLAGS     += -ffreestanding
BASE_CFLAGS     += -fno-stack-protector
BASE_CFLAGS     += -fno-strict-aliasing
# make it simpler for symbolic execution to track PC
BASE_CFLAGS     += -fno-jump-tables
# no unaligned memory accesses
BASE_CFLAGS     += -mstrict-align
BASE_CFLAGS     += -g -O$(OLEVEL)
BASE_CFLAGS     += -Wall -MD -MP

CONFIG_CFLAGS   += -DCONFIG_NR_CPUS=$(CONFIG_NR_CPUS)
CONFIG_CFLAGS   += -DCONFIG_BOOT_CPU=$(CONFIG_BOOT_CPU)
CONFIG_CFLAGS   += -DCONFIG_DRAM_START=$(CONFIG_DRAM_START)
CONFIG_CFLAGS   += -DCONFIG_VERIFICATION=$(CONFIG_VERIFICATION)

CFLAGS          += $(BASE_CFLAGS) $(CONFIG_CFLAGS)
CFLAGS          += -mcmodel=medany
# no floating point
CFLAGS          += -mabi=lp64
CFLAGS          += -ffunction-sections -fdata-sections
CFLAGS          += -fno-PIE
CFLAGS          += -I include
CFLAGS          += -march=rv64ima

USER_CFLAGS     += $(BASE_CFLAGS)
USER_CFLAGS     += -I include/uapi

LDFLAGS         += -nostdlib
LDFLAGS         += --gc-sections

UBSAN_CFLAGS    += -fsanitize=integer-divide-by-zero
UBSAN_CFLAGS    += -fsanitize=shift
UBSAN_CFLAGS    += -fsanitize=signed-integer-overflow

include bios/bios.mk
include kernel/kernel.mk
include monitor/monitor.mk

all: $(ALL)

.DEFAULT_GOAL = all

LLVM_ROSETTE            := $(O)/racket/llvm-rosette/llvm-rosette

LLVM_ROSETTE_OBJS       := $(call object,$(wildcard racket/llvm-rosette/*.cc))

$(O)/racket/%.o: racket/%.cc
	$(Q)$(MKDIR_P) $(@D)
	$(QUIET_CXX)$(HOST_CXX) -o $@ -c -Wno-unknown-warning-option $(LLVM_CXXFLAGS) $<

$(LLVM_ROSETTE): $(LLVM_ROSETTE_OBJS)
	$(QUIET_LD)$(HOST_CXX) -o $@ $^ $(LLVM_LDFLAGS) $(LLVM_LIBS)

# keep LLVM_ROSETTE around for now
%.ll.rkt: %.ll
	$(QUIET_GEN)$(LLVM_ROSETTE) $< > $@~
	$(Q)mv $@~ $@

%.globals.rkt: %.elf
	$(Q)echo "#lang reader serval/lang/dwarf" > $@~
	$(QUIET_GEN)$(OBJDUMP) --dwarf=info $< >> $@~
	$(Q)mv $@~ $@

%.asm.rkt: %.asm
	$(QUIET_GEN)echo "#lang reader serval/riscv/objdump" > $@~ && \
		cat $< >> $@~
	$(Q)mv $@~ $@

%.map.rkt: %.map
	$(QUIET_GEN)echo "#lang reader serval/lang/nm" > $@~ && \
		cat $< >> $@~
	$(Q)mv "$@~" "$@"

%/asm-offsets.rkt: %/asm-offsets.S
	$(QUIET_GEN)$(call gen-offsets-rkt) < $< > $@~
	$(Q)mv $@~ $@

$(O)/%.ebpf.bin: %.ebpf
	$(Q)$(MKDIR_P) $(@D)
	$(QUIET_GEN)$(UBPF_ASSEMBLER) $^ $@

$(O)/%.ll: %.c
	$(Q)$(MKDIR_P) $(@D)
	$(QUIET_CC)$(LLVM_CC) -o $@ -mno-sse -S -emit-llvm -fno-discard-value-names $(UBSAN_CFLAGS) -Wno-unused-command-line-argument -I include $(filter-out -g,$(BASE_CFLAGS)) $(CONFIG_CFLAGS) -DCONFIG_VERIFICATION_LLVM -c $<

PRECIOUS        += %.ll.rkt %.S.rkt $(O)/%.ll $(O)/%.S

# for asm-offsets.S
$(O)/%.S: %.c
	$(Q)$(MKDIR_P) $(@D)
	$(QUIET_CC)$(CC) -o $@ $(filter-out -g,$(CFLAGS)) -S $<

# include zeros for bss in the binary
%.bin: %.elf
	$(QUIET_GEN)$(OBJCOPY) -O binary --set-section-flags .bss=alloc,load,contents $< $@

# --prefix-addresses prints the complete address on each line
%.asm: %.elf
	$(QUIET_GEN)$(OBJDUMP) -M no-aliases --prefix-addresses -w -f -d -z --show-raw-insn "$<" > "$@"

%.c.asm: %.elf
	$(QUIET_GEN)$(OBJDUMP) -S "$<" > "$@"

# sort addresses for *.map.rkt
%.map: %.elf
	$(QUIET_GEN)$(NM) --print-size --numeric-sort "$<" > "$@"

%.bin.o: %.bin bbl/payload.S
	$(QUIET_CC)$(CC) -o $@ -c -mabi=lp64 -DBBL_PAYLOAD='"$<"' bbl/payload.S

%.bbl: %.bin.o $(wildcard bbl/*.o) bbl/libmachine.a bbl/libsoftfloat.a bbl/libutil.a
	$(QUIET_LD)$(LD) -o $@ $(LDFLAGS) -T bbl/bbl.lds $^

$(O)/%.lds: %.lds.S
	$(Q)$(MKDIR_P) $(@D)
	$(QUIET_GEN)$(CPP) -o $@ -P $(CFLAGS) $<

$(O)/%.o: %.S
	$(Q)$(MKDIR_P) $(@D)
	$(QUIET_CC)$(CC) -o $@ -c $(CFLAGS) $<

$(O)/%.o: %.c
	$(Q)$(MKDIR_P) $(@D)
	$(QUIET_CC)$(CC) -o $@ -c $(CFLAGS) -D__MODULE__='"$(basename $(notdir $<))"' $<

raco-test: $(RACO_TESTS)
	$(RACO_TEST) $^

clean:
	-rm -rf $(O)

mrproper: clean
	-rm -f local.mk

distclean: mrproper
	-find . \
		\( -name '*.pyc' -o -name '.DS_Store' \
		-o -name '*.bak' -o -name '*~' \
		-o -name '*.orig' \) \
		-type f -print0 | xargs -0 rm -f
	-find . \
		\( -name '__pycache__' \) \
		-type d -print0 | xargs -0 rm -rf

# partitions type codes
BBL   = 2E54B353-1271-4842-806F-E436D6AF6985
LINUX = 0FC63DAF-8483-4772-8E79-3D69D8477DE4

format: $(DISK_BIN)
	@test -n "$(DISK_BIN)" || (echo "DISK_BIN not set"; exit 1)
	@test -f "$(DISK_BIN)" || (echo "$(DISK_BIN): not a regular file"; exit 1)
	@test -n "$(DISK)" || (echo "DISK not set"; exit 1)
	@test -b "$(DISK)" || (echo "$(DISK): not a block device"; exit 1)
	sgdisk --clear                                                               \
		--new=1:2048:67583  --change-name=1:bootloader --typecode=1:$(BBL)   \
		--new=2:264192:     --change-name=2:root       --typecode=2:$(LINUX) \
		$(DISK)
	@sleep 1
ifeq ($(DISK)p1,$(wildcard $(DISK)p1))
	@$(eval PART1 := $(DISK)p1)
	@$(eval PART2 := $(DISK)p2)
else ifeq ($(DISK)s1,$(wildcard $(DISK)s1))
	@$(eval PART1 := $(DISK)s1)
	@$(eval PART2 := $(DISK)s2)
else ifeq ($(DISK)1,$(wildcard $(DISK)1))
	@$(eval PART1 := $(DISK)1)
	@$(eval PART2 := $(DISK)2)
else
	@echo Error: Could not find bootloader partition for $(DISK)
	@exit 1
endif
	dd if=$< of=$(PART1) bs=4096
	sync

docker:
	docker run --privileged -it --rm -v $(TOP):/home $(DOCKER_IMAGE) /bin/sh -c 'cd /home; exec bash'

build-docker:
	docker build -f scripts/Dockerfile .

-include $(call rwildcard,./,*.d)

PHONY           += all clean mrproper distclean check raco-test format docker build-docker

PRECIOUS        += %.asm %.map %.bin %.bin.o $(O)/%.o

.PHONY: $(PHONY)

.PRECIOUS: $(PRECIOUS)
