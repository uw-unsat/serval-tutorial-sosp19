#lang rosette

(require
  (prefix-in constants: "generated/monitor/verif/asm-offsets.rkt"))

(provide (all-defined-out))

(struct state (retval current-user dict)
  #:transparent
  #:mutable
  #:methods gen:equal+hash
  [(define (equal-proc s t equal?-recur) (state-equal? s t))
   (define (hash-proc s hash-recur) 1)
   (define (hash2-proc s hash2-recur) 2)])

; Debuging function to print specification state
(define (print-state cex s)
  (printf " retval: ~v\n" (bitvector->natural (evaluate (state-retval s) cex)))
  (printf " current-user: ~v\n" (bitvector->natural (evaluate (state-current-user s) cex)))
  (printf  " dict: ~v\n"
    (for/list ([i (range constants:MAXUSER)])
      (bitvector->natural (evaluate ((state-dict s) (bv i 64)) cex)))))

(define (state-equal? s t)
  (define-symbolic* idx (bitvector 64))
  (&&
    (equal? (state-retval s) (state-retval t))
    (equal? (state-current-user s) (state-current-user t))
    (forall (list idx)
      (=> (bvult idx (bv constants:MAXUSER 64))
          (equal? ((state-dict s) idx) ((state-dict t) idx))))))

(define (update-dict! st key value)
  (define old-dict (state-dict st))
  (set-state-dict! st (lambda (idx) (if (equal? key idx) value (old-dict idx)))))

(define (fresh-state)
  (define-symbolic* retval (bitvector 64))
  (define-symbolic* current-user (bitvector 64))
  (define-symbolic* dictionary (~> (bitvector 64) (bitvector 64)))
  (state retval current-user dictionary))

(define (sys-dict-get st)
  (define current-user (state-current-user st))
  (define dict (state-dict st))

  (if (bvult current-user (bv constants:MAXUSER 64))
    (set-state-retval! st (dict current-user))
    (set-state-retval! st (bv -1 64))))


(define (sys-dict-set st value)
  (define current-user (state-current-user st))

  (if (bvult current-user (bv constants:MAXUSER 64))
    (begin
      (update-dict! st current-user value)
      (set-state-retval! st (bv 0 64)))
    (set-state-retval! st (bv -1 64))))

(define (sys-change-user st newuser)
  (set-state-current-user! st newuser)
  (set-state-retval! st (bv 0 64)))
