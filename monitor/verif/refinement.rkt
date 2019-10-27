#lang rosette/safe

(require
  serval/lib/unittest
  serval/lib/core
  serval/spec/refinement
  serval/riscv/base
  serval/riscv/interp
  serval/riscv/objdump
  (only-in racket/base struct-copy for)
  (prefix-in specification: "spec.rkt")
  (prefix-in constants: "generated/monitor/verif/asm-offsets.rkt")
  (prefix-in implementation:
    (combine-in
      "generated/monitor.asm.rkt"
      "generated/monitor.globals.rkt"
      "generated/monitor.map.rkt")))

(provide refinement-tests)

; Helper function to find the start of a symbol in our monitor's image
(define (find-symbol-start name)
  (define sym (find-symbol-by-name implementation:symbols name))
  (bv (car sym) 64))

; Representation invariant that is assumed to hold
; before each system call, and is proven to hold after
(define (rep-invariant cpu)
  (&&
    (equal? (csr-ref cpu 'mtvec) (find-symbol-start 'machine_trap_vector))
    (equal? (csr-ref cpu 'mscratch) (bvadd (find-symbol-start 'cpu_stack)
                                          (bv #x7f00 64)))))

; Initialize the machine state with concrete values
; consistent with the representation invariant.
(define (init-rep-invariant cpu)
  (csr-set! cpu 'mtvec (find-symbol-start 'machine_trap_vector))
  (csr-set! cpu 'mscratch (bvadd (find-symbol-start 'cpu_stack)
                                 (bv #x7f00 64))))


; Check that init-rep-invariant is consistent with
; the representation invariant
(define (verify-rep-invariant)
  (define cpu1 (init-cpu implementation:symbols implementation:globals))
  (define cpu2 (init-cpu implementation:symbols implementation:globals))
  (define equal-before (cpu-equal? cpu1 cpu2))
  (init-rep-invariant cpu2)
  (define equal-after (cpu-equal? cpu1 cpu2))
  (check-unsat? (verify (assert (implies (&& equal-before (rep-invariant cpu1)) equal-after)))))


; Abstraction function that maps an implementation CPU
; state to the specification state
(define (abs-function cpu)

  ; Get list of implementation memory regions
  (define mr (cpu-mregions cpu))

  ; Find the block containing the global variable named "dictionary"
  (define dictionary-block (find-block-by-name mr 'dictionary))

  (define dictionary (lambda (idx) (mblock-iload dictionary-block (list idx))))

  (define current-user (mblock-iload (find-block-by-name mr 'current_user) null))

  ; Construct specification state
  (specification:state (gpr-ref cpu 'a0) current-user dictionary))

; Simulate an ecall from the kernel to the security monitor.
; It sets mcause to ECALL,
; the program counter to the value in the mtvec CSR,
; a7 to the monitor call number,
; and a0 through a6 to the monitor call arguments.
(define (cpu-ecall cpu callno args)
  (set-cpu-pc! cpu (csr-ref cpu 'mtvec))
  (csr-set! cpu 'mcause (bv constants:EXC_ECALL_S 64))
  (gpr-set! cpu 'a7 callno)
  (for ([reg '(a0 a1 a2 a3 a4 a5 a6)] [arg args])
    (gpr-set! cpu reg arg))
  (interpret-objdump-program cpu implementation:instructions))


; Check RISC-V refinement for a single system call using
; cpu-ecall and Serval's refinement definition
(define (verify-riscv-refinement spec-func callno [args null])
  (define cpu (init-cpu implementation:symbols implementation:globals))
  (init-rep-invariant cpu)

  (define (handle-ce s1 s2 cex)
    (printf "Args: ~v\n" (map bitvector->natural (evaluate args cex)))
    (displayln "\nspec state:")
    (specification:print-state cex s1)
    (displayln "\nabs(impl state):")
    (specification:print-state cex s2))

  (verify-refinement
    ; Implementation state
    #:implstate cpu
    ; Implementation transition function
    #:impl (lambda (c . args) (cpu-ecall c callno args))
    ; Specification state
    #:specstate (specification:fresh-state)
    ; Specification transition function
    #:spec spec-func
    ; Abstraction funtion from c -> s
    #:abs abs-function
    ; Representation invariant c -> bool
    #:ri rep-invariant
    ; Arguments to monitor call
    args
    handle-ce))


(define (verify-boot-invariants)
  (define cpu (init-cpu implementation:symbols implementation:globals))
  ; Set program counter to architecturally-defined reset vector
  (set-cpu-pc! cpu (bv #x0000000080000000 64))
  ; Set a0 to be hartid (boot cpu number)
  (gpr-set! cpu 'a0 (bv constants:CONFIG_BOOT_CPU 64))

  ; Interpret until first mret to user space
  (check-asserts (interpret-objdump-program cpu implementation:instructions))

  ; Prove that the representation invariant holds
  (check-unsat? (verify (assert (rep-invariant cpu)))))


(define (refinement-tests)
  (test-case+ "verify init-rep-invariant" (verify-rep-invariant))

  (test-case+ "verify boot invariants" (verify-boot-invariants))

  (test-case+ "sys_dict_get refinement"
    (verify-riscv-refinement
      specification:sys-dict-get
      (bv constants:__NR_dict_get 64)
      (list)))

  (test-case+ "sys_dict_set refinement"
    (verify-riscv-refinement
      specification:sys-dict-set
      (bv constants:__NR_dict_set 64)
      (list (make-bv64))))

  (test-case+ "sys_change_user refinement"
    (verify-riscv-refinement
      specification:sys-change-user
      (bv constants:__NR_change_user 64)
      (list (make-bv64))))
)

(module+ test
  (refinement-tests))