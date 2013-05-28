#lang typed/racket/base

(require racket/match)
(require "types.rkt")
(require "roles.rkt")
(require "vm.rkt")
(require "log-typed.rkt")
(require "process.rkt")
(require (rename-in "tr-struct-copy.rkt" [tr-struct-copy struct-copy])) ;; PR13149 workaround

(provide do-spawn)

(: do-spawn : (All (OldState)
		   process-spec
		   (Option (PID -> (InterruptK OldState)))
		   (process OldState)
		   Any
		   vm
		   -> (Values (Option (process OldState)) vm)))
(define (do-spawn spec parent-k p debug-name state)
  (define new-pid (vm-next-process-id state))
  (matrix-log 'info "PID ~v (~a) starting" new-pid debug-name)
  (: new-cotransition : CoTransition)
  (define new-cotransition
    (send-to-user* debug-name new-pid (e) (co-quit e)
      ((process-spec-boot spec) new-pid)))
  (: co-quit : Reason -> CoTransition)
  (define ((co-quit e) k)
    ((inst k False) (transition #f (quit #f e))))
  (: transition-accepter : (All (NewState) (Transition NewState) -> Process))
  (define (transition-accepter t)
    (match-define (transition initial-state initial-actions) t)
    (mkProcess ((inst process NewState)
		debug-name
		new-pid
		initial-state
		'()
		#hash()
		#hash()
		(action-tree->quasiqueue initial-actions))))
  (let ((new-process
	 (send-to-user* debug-name new-pid (e) (transition-accepter (transition #f (quit #f e)))
	   ((inst new-cotransition Process) transition-accepter))))
    (values (if parent-k
		(run-ready p (send-to-user p (e) (quit-interruptk e)
			       (parent-k new-pid)))
		p)
	    (inject-process (struct-copy vm state [next-process-id (+ new-pid 1)])
			    new-process))))