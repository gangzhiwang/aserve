;; -*- mode: common-lisp; package: net.html.generator -*-
;;
;; htmlgen.cl
;;
;; copyright (c) 1986-2000 Franz Inc, Berkeley, CA  - All rights reserved.
;;
;; The software, data and information contained herein are proprietary
;; to, and comprise valuable trade secrets of, Franz, Inc.  They are
;; given in confidence by Franz, Inc. pursuant to a written license
;; agreement, and may be stored and used only in accordance with the terms
;; of such license.
;;
;; Restricted Rights Legend
;; ------------------------
;; Use, duplication, and disclosure of the software, data and information
;; contained herein by any agency, department or entity of the U.S.
;; Government are subject to restrictions of Restricted Rights for
;; Commercial Software developed at private expense as specified in
;; DOD FAR Supplement 52.227-7013 (c) (1) (ii), as applicable.
;;
;; $Id: htmlgen.cl,v 1.1.2.1 2000/02/28 21:50:00 jkf Exp $

;; Description:
;;   html generator

;;- This code in this file obeys the Lisp Coding Standard found in
;;- http://www.franz.com/~jkf/coding_standards.html
;;-



(defpackage :net.html.generator
  (:use :common-lisp :excl)
  (:export #:html #:html-stream #:*html-stream*
	   ;; should export with with-html-xxx things too I suppose
	   ))

(in-package :net.html.generator)

;; html generation

(defvar *html-stream*)	; all output sent here

(defstruct (html-process (:type list) (:constructor
				       make-html-process (key has-inverse
							      macro special)))
  key	; keyword naming this
  has-inverse	; t if the / form is used
  macro  ; the macro to define this
  special  ; if true then call this to process the keyword
  )


(defparameter *html-process-table* nil)
(defvar *html-stream* nil) ; where the output goes

(defmacro html (&rest forms)
  ;; just emit html to the curfent stream
  (process-html-forms forms))

(defmacro html-stream (stream &rest forms)
  ;; set output stream and emit html
  `(let ((*html-stream* ,stream)) (html ,@forms)))

(defun process-html-forms (forms)
  (let (res)
    (flet ((do-ent (ent args argsp body)
	     ;; do the work of the ent.
	     ;; 
	     (let (spec)
	       (if* (setq spec (html-process-special ent))
		  then ; do something different
		       (push (funcall spec ent args argsp body) res)
		elseif (null argsp)
		  then (push `(,(html-process-macro ent) :set) res)
		       nil
		  else (if* (equal args '(:unset))
			  then (push `(,(html-process-macro ent) :unset) res)
			       nil
			  else ; some args
			       (push `(,(html-process-macro ent) ,args
								 ,(process-html-forms body))
				     res)
			       nil)))))
				 
		    

      (do* ((xforms forms (cdr xforms))
	    (form (car xforms) (car xforms)))
	  ((null xforms))
	
	(if* (atom form)
	   then (if* (keywordp form)
		   then (let ((ent (assoc form *html-process-table* :test #'eq)))
			  (if* (null ent)
			     then (error "unknown html keyword ~s"
					 form)
			     else (do-ent ent nil nil nil)))
		 elseif (stringp form)
		   then ; turn into a print of it
			(push `(write-string ,form *html-stream*) res)
		   else (push form res))
	   else (let ((first (car form)))
		  (if* (keywordp first)
		     then ; (:xxx . body) form
			  (let ((ent (assoc first
					    *html-process-table* :test #'eq)))
			    (if* (null ent)
			       then (error "unknown html keyword ~s"
					   form)
			       else (do-ent ent nil t (cdr form))))
		   elseif (and (consp first) (keywordp (car first)))
		     then ; ((:xxx args ) . body)
			  (let ((ent (assoc (car first)
					    *html-process-table* :test #'eq)))
			    (if* (null ent)
			       then (error "unknown html keyword ~s"
					   form)
			       else (do-ent ent (cdr first) t (cdr form))))
		     else (push form res))))))
    `(progn ,@(nreverse res))))


(defun html-atom-check (args open close body)
  (if* (and args (atom args))
     then (let ((ans (case args
		       (:set `(write-string  ,open *html-stream*))
		       (:unset `(write-string  ,close *html-stream*))
		       (t (error "illegal arg ~s to ~s" args open)))))
	    (if* (and ans body)
	       then (error "can't have a body form with this arg: ~s"
			   args)
	       else ans))))

(defun html-body-form (open close body)
  ;; used when args don't matter
  `(progn (write-string  ,open *html-stream*)
	  ,@body
	  (write-string  ,close *html-stream*)))


(defun html-body-key-form (string-code has-inv args body)
  ;; do what's needed to handle given keywords in the args
  ;; then do the body
  (if* (and args (atom args))
     then ; single arg 
	  (return-from html-body-key-form
	    (case args
	      (:set `(write-string  ,(format nil "<~a>" string-code)
				    *html-stream*))
	      (:unset (if* has-inv
			 then `(write-string  ,(format nil "</~a>" string-code)
					      *html-stream*)))
	      (t (error "illegal arg ~s to ~s" args string-code)))))
  
  (if* (not (evenp (length args)))
     then (warn "arg list ~s isn't even" args))
  
  
  (if* args
     then `(progn (write-string ,(format nil "<~a" string-code)
				*html-stream*)
		  ,@(do ((xx args (cddr xx))
			 (res))
			((null xx)
			 (nreverse res))
		      (if* (eq :if* (car xx))
			 then ; insert following conditionally
			      (push `(if* ,(cadr xx)
					then (write-string 
					      ,(format nil " ~a=" (caddr xx))
					      *html-stream*)
					     (prin1-safe-http-string ,(cadddr xx)))
				    res)
			      (pop xx) (pop xx)
			 else 
					     
			      (push `(write-string 
				      ,(format nil " ~a=" (car xx))
				      *html-stream*)
				    res)
			      (push `(prin1-safe-http-string ,(cadr xx)) res)))
						    
		      
		  (write-string ">" *html-stream*)
		  ,@body
		  ,(if* (and body has-inv)
		      then `(write-string ,(format nil "</~a>" string-code)
					  *html-stream*)))
     else `(progn (write-string ,(format nil "<~a>" string-code)
				*html-stream*)
		  ,@body
		  ,(if* (and body has-inv)
		      then `(write-string ,(format nil "</~a>" string-code)
					  *html-stream*)))))
			     
		 

(defun princ-http (val)
  ;; print the given value to the http stream using ~a
  (format *html-stream* "~a" val))

(defun prin1-http (val)
  ;; print the given value to the http stream using ~s
  (format *html-stream* "~s" val))


(defun princ-safe-http (val)
  (emit-safe *html-stream* (format nil "~a" val)))

(defun prin1-safe-http (val)
  (emit-safe *html-stream* (format nil "~s" val)))


(defun prin1-safe-http-string (val)
  ;; print the contents inside a string double quotes (which should
  ;; not be turned into &quot;'s
  (if* (stringp val)
     then (write-char #\" *html-stream*)
	  (emit-safe *html-stream* val)
	  (write-char #\" *html-stream*)
     else (prin1-safe-http val)))



(defun emit-safe (stream string)
  ;; send the string to the http response stream watching out for
  ;; special html characters and encoding them appropriately
  (do* ((i 0 (1+ i))
	(start i)
	(end (length string)))
      ((>= i end)
       (if* (< start i)
	  then  (write-sequence string
				stream
				:start start
				:end i)))
	 
      
    (let ((ch (schar string i))
	  (cvt ))
      (if* (eql ch #\<)
	 then (setq cvt "&lt;")
       elseif (eq ch #\>)
	 then (setq cvt "&gt;")
       elseif (eq ch #\&)
	 then (setq cvt "&amp;")
       elseif (eq ch #\")
	 then (setq cvt "&quot;"))
      (if* cvt
	 then ; must do a conversion, emit previous chars first
		
	      (if* (< start i)
		 then  (write-sequence string
				       stream
				       :start start
				       :end i))
	      (write-string cvt stream)
		
	      (setq start (1+ i))))))
	
		
			
					 
		      
      
  
  

(defmacro def-special-html (kwd fcn)
  `(push (make-html-process ,kwd nil nil ,fcn) *html-process-table*))


(def-special-html :newline #'(lambda (ent args argsp body)
			       (declare (ignore ent args argsp))
			       (if* body
				  then (error "can't have a body with :newline -- body is ~s" body))
			       
			       `(terpri *html-stream*)))
			       

(def-special-html :princ #'(lambda (ent args argsp body)
			     (declare (ignore ent args argsp))
			     `(progn ,@(mapcar #'(lambda (bod)
						   `(princ-http ,bod))
					       body))))

(def-special-html :princ-safe #'(lambda (ent args argsp body)
			     (declare (ignore ent args argsp))
			     `(progn ,@(mapcar #'(lambda (bod)
						   `(princ-safe-http ,bod))
					       body))))

(def-special-html :prin1 #'(lambda (ent args argsp body)
			     (declare (ignore ent args argsp))
			     `(progn ,@(mapcar #'(lambda (bod)
						   `(prin1-http ,bod))
					       body))))


(def-special-html :prin1-safe #'(lambda (ent args argsp body)
			     (declare (ignore ent args argsp))
			     `(progn ,@(mapcar #'(lambda (bod)
						   `(prin1-safe-http ,bod))
					       body))))





(defmacro def-std-html (kwd has-inverse)
  (let ((mac-name (intern (format nil "~a-~a" :with-html kwd)))
	(string-code (string-downcase (string kwd))))
    `(progn (push (make-html-process ,kwd ,has-inverse
				     ',mac-name
				     nil)
		  *html-process-table*)
	    (defmacro ,mac-name (args &rest body)
	      (html-body-key-form ,string-code ,has-inverse args body)))))

    

(def-std-html :a        t)
(def-std-html :abbr     t)
(def-std-html :acronym  t)
(def-std-html :address  t)
(def-std-html :applet   t)
(def-std-html :area    nil)

(def-std-html :b        t)
(def-std-html :base     nil)
(def-std-html :basefont nil)
(def-std-html :bdo      t)
(def-std-html :bgsound  nil)
(def-std-html :big      t)
(def-std-html :blink    t)
(def-std-html :blockquote  t)
(def-std-html :body      t)
(def-std-html :br       nil)
(def-std-html :button   nil)

(def-std-html :center   t)
(def-std-html :cite     t)
(def-std-html :code     t)
(def-std-html :col      nil)
(def-std-html :colgroup nil)
(def-std-html :comment   t)

(def-std-html :dd        t)
(def-std-html :del       t)
(def-std-html :dfn       t)
(def-std-html :dir       t)
(def-std-html :div       t)
(def-std-html :dl        t)
(def-std-html :dt        t)

(def-std-html :em        t)
(def-std-html :embed     nil)

(def-std-html :fieldset        t)
(def-std-html :font        t)
(def-std-html :form        t)
(def-std-html :frame        t)
(def-std-html :frameset        t)

(def-std-html :h1        t)
(def-std-html :h2        t)
(def-std-html :h3        t)
(def-std-html :h4        t)
(def-std-html :h5        t)
(def-std-html :h6        t)
(def-std-html :head        t)
(def-std-html :hr        nil)
(def-std-html :html        t)

(def-std-html :i     t)
(def-std-html :iframe     t)
(def-std-html :ilayer     t)
(def-std-html :img     nil)
(def-std-html :input     nil)
(def-std-html :ins     t)
(def-std-html :isindex    nil)

(def-std-html :kbd  	t)
(def-std-html :keygen  	nil)

(def-std-html :label  	t)
(def-std-html :layer  	t)
(def-std-html :legend  	t)
(def-std-html :li  	t)
(def-std-html :link  	nil)
(def-std-html :listing  t)

(def-std-html :map  	t)
(def-std-html :marquee  t)
(def-std-html :menu  	t)
(def-std-html :meta  	nil)
(def-std-html :multicol t)

(def-std-html :nobr  	t)
(def-std-html :noembed  t)
(def-std-html :noframes t)
(def-std-html :noscript t)

(def-std-html :object  	nil)
(def-std-html :ol  	t)
(def-std-html :optgroup t)
(def-std-html :option  	t)

(def-std-html :p  	t)
(def-std-html :param  	t)
(def-std-html :plaintext  nil)
(def-std-html :pre  	t)

(def-std-html :q  	t)

(def-std-html :s  	t)
(def-std-html :samp  	t)
(def-std-html :script  	t)
(def-std-html :select  	t)
(def-std-html :server  	t)
(def-std-html :small  	t)
(def-std-html :spacer  	nil)
(def-std-html :span  	t)
(def-std-html :strike  	t)
(def-std-html :strong  	t)
(def-std-html :sub  	t)
(def-std-html :sup  	t)

(def-std-html :table  	t)
(def-std-html :tbody  	t)
(def-std-html :td  	t)
(def-std-html :textarea  t)
(def-std-html :tfoot  	t)
(def-std-html :th  	t)
(def-std-html :thead  	t)
(def-std-html :title  	t)
(def-std-html :tr  	t)
(def-std-html :tt  	t)

(def-std-html :u 	t)
(def-std-html :ul 	t)

(def-std-html :var 	t)

(def-std-html :wbr  	nil)

(def-std-html :xmp 	t)
