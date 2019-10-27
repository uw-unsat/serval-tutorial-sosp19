TOYMON_TESTS := \
        monitor/verif/test.rkt \

verify-monitor: $(TOYMON_TESTS)
	$(RACO_TEST) $^

verify-monitor-%: monitor/verif/%.rkt $(TOYMON_TESTS)
	$(RACO_TEST) $<

$(TOYMON_TESTS): | \
        $(O)/monitor.c.asm \
        $(O)/monitor.asm.rkt \
        $(O)/monitor.map.rkt \
        $(O)/monitor.globals.rkt \
        $(O)/monitor/verif/asm-offsets.rkt \
#         $(O)/monitor.ll.rkt \

# $(O)/monitors/toymon.ll: $(O)/monitor/main.ll
# 	$(QUIET_GEN)$(LLVM_LINK) $^ | $(LLVM_OPT) -o $@~ $(LLVM_OPTFLAGS) -S
# 	$(Q)mv $@~ $@

PHONY           += verify-monitor
