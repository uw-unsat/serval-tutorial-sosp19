#lang rosette

(require
  "../lib/core.rkt"
  "../lib/unittest.rkt"
)

(provide (all-defined-out))

(define (handle-lowlevel-ce counterexample assertion)
  (when assertion
    (define bug (first (bug-ref assertion)))
    (displayln "Low-level bug:")
    (printf " Location: ~v\n" (cdr (assoc 'location bug)))
    (printf " Message: ~v\n" ((cdr (assoc 'message bug ))))))

(define
  (verify-refinement
    #:implstate impl-state
    #:impl impl-func
    #:specstate spec-state
    #:spec spec-func
    #:abs abs-function
    #:ri rep-invariant
    [args null]
    [ce-handler (lambda args (void))])

  (define ri0 (rep-invariant impl-state))

  (define pre (check-asserts (equal? spec-state (abs-function impl-state))))

  (check-sat? (solve (assert ri0)))
  (check-sat? (solve (assert pre)))

  ; spec state transition
  (apply spec-func spec-state args)
  ; make sure spec-func doesn't generate assertions
  (check-equal? (asserts) null)

  ; impl state transition
  (define impl-asserted
    (with-spectre-asserts-only (apply impl-func impl-state args)))

  (for ([as impl-asserted])
    (define cex (verify (assert (=> ri0 as))))
    (when (sat? cex) (handle-lowlevel-ce cex as))
    (check-unsat? cex))

  (define-values (ri1 ri1-asserted)
    (with-asserts (rep-invariant impl-state)))
  (check-unsat? (verify (assert (=> ri0 (apply && ri1-asserted)))))

  (define-values (post post-asserted)
    (with-asserts (equal? spec-state (abs-function impl-state))))

  (check-unsat? (verify (assert (=> ri0 (apply && post-asserted)))))

  (let ([sol (verify (assert (=> (&& pre ri0) post)))])
    (when (sat? sol) (ce-handler spec-state (abs-function impl-state) sol))
    (check-unsat? sol))

  (check-unsat? (verify (assert (=> (&& pre ri0) ri1))))

(void))
