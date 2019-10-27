#lang rosette

(require
  serval/lib/core
  serval/lib/unittest
  (prefix-in constants: "generated/monitor/verif/asm-offsets.rkt")
  "spec.rkt"
  "refinement.rkt")

(provide safety-tests)

; Helpful debugging utility
(define (debug-counterexample cex op args s1 s2)
  (printf "Confidentiality violation:\n")
  (printf "Operation: ~v\n" op)
  (printf "Arguments: ~v\n\n" (map bitvector->natural (evaluate args cex)))
  (printf "State 1:\n")
  (print-state cex s1)
  (printf "\nState 2:\n")
  (print-state cex s2))


; Defines when two states appear equivalent to a user
(define (equiv-user s t)
  (&&
    (equal? (state-current-user s) (state-current-user t))
    (equal? ((state-dict s) (state-current-user s)) ((state-dict t) (state-current-user s)))
    (equal? (state-retval s) (state-retval t))))


(define (verify-confidentiality op [args null])
  (define s1 (fresh-state))
  (define s2 (fresh-state))

  (define equiv-before (equiv-user s1 s2))

  (apply op s1 args)
  (apply op s2 args)

  (define equiv-after (equiv-user s1 s2))

  (define cex (verify (assert (implies equiv-before equiv-after))))
  (when (sat? cex)
    (debug-counterexample cex op args s1 s2))
  (check-unsat? cex))


(define (safety-tests)
  (test-case+ "confidentiality sys-dict-get"
    (verify-confidentiality sys-dict-get)))

(module+ test
  (safety-tests))