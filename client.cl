;; -*- mode: common-lisp; package: net.iserve.client -*-
;;
;; client.cl
;;
;; copyright (c) 1986-2000 Franz Inc, Berkeley, CA 
;;
;; This code is free software; you can redistribute it and/or
;; modify it under the terms of the version 2.1 of
;; the GNU Lesser General Public License as published by 
;; the Free Software Foundation; 
;;
;; This code is distributed in the hope that it will be useful,
;; but without any warranty; without even the implied warranty of
;; merchantability or fitness for a particular purpose.  See the GNU
;; Lesser General Public License for more details.
;;
;; Version 2.1 of the GNU Lesser General Public License is in the file 
;; license-lgpl.txt that was distributed with this file.
;; If it is not present, you can access it from
;; http://www.gnu.org/copyleft/lesser.txt (until superseded by a newer
;; version) or write to the Free Software Foundation, Inc., 59 Temple Place, 
;; Suite 330, Boston, MA  02111-1307  USA
;;
;;
;; $Id: client.cl,v 1.7 2000/03/21 05:55:55 jkf Exp $

;; Description:
;;   http client code.

;;- This code in this file obeys the Lisp Coding Standard found in
;;- http://www.franz.com/~jkf/coding_standards.html
;;-


;; this will evolve into the http client code but for now it's
;; just some simple stuff to allow us to test iserve
;;



(defpackage :net.iserve.client 
  (:use :net.iserve :excl :common-lisp)
  (:export 
   #:client-request  ; class
   #:client-request-close
   #:client-request-read-sequence
   #:client-response-header-value
   #:cookie-jar     ; class
   #:do-http-request
   #:make-http-client-request
   #:read-client-response-headers
   ))



(in-package :net.iserve.client)








(defclass client-request ()
  ((uri   	;; uri we're accessing
    :initarg :uri
    :accessor client-request-uri)
   
   (headers ; alist of  ("headername" . "value")
    :initform nil
    :initarg :headers
    :accessor client-request-headers)
   (response-code    ; response code (an integer)
    :initform nil
    :accessor client-request-response-code)
   (socket  ; the socket through which we'll talk to the server
    :initarg :socket
    :accessor client-request-socket)
   (protocol 
    ; the protocol value returned by the web server
    ; note, even if the request is for http/1.0, apache will return
    ; http/1.1.  I'm not sure this is kosher.
    :accessor client-request-protocol)
   (response-comment  ;; comment passed back with the response
    :accessor client-request-response-comment)
   ;
   (bytes-left  ;; indicates how many bytes in response left
    ; value is nil (no body)
    ;          integer (that many bytes left, not chunking)
    ;		:unknown - read until eof, not chunking
    ;		:chunking - read until chunking eof
    :accessor client-request-bytes-left
    :initform nil)
   
   (cookies  ;; optionally a cookie jar for hold received and sent cookies
    :accessor client-request-cookies
    :initarg :cookies
    :initform nil)
   ))


(defvar crlf (make-array 2 :element-type 'character
			 :initial-contents '(#\return #\newline)))

(defmacro with-better-scan-macros (&rest body)
  ;; define the macros for scanning characters in a string
  `(macrolet ((collect-to (ch buffer i max &optional downcasep)
		;; return a string containing up to the given char
		`(let ((start ,i))
		   (loop
		     (if* (>= ,i ,max) then (fail))
		     (if* (eql ,ch (schar ,buffer ,i)) 
			then (return (buf-substr start ,i ,buffer ,downcasep)))
		     (incf ,i)
		     )))
	      
	      (collect-to-eol (buffer i max)
		;; return a string containing up to the given char
		`(let ((start ,i))
		   (loop
		     (if* (>= ,i ,max) 
			then (return (buf-substr start ,i ,buffer)))
		     (let ((thisch (schar ,buffer ,i)))
		       (if* (eq thisch #\return)
			  then (let ((ans (buf-substr start ,i ,buffer)))
				 (incf ,i)  ; skip to newline
				 (return ans))
			elseif (eq thisch #\newline)
			  then (return (buf-substr start ,i ,buffer))))
		     (incf ,i)
		     )))
	      
	      (skip-to-not (ch buffer i max)
		;; skip to first char not ch
		`(loop
		   (if* (>= ,i ,max) then (fail))
		   (if* (not (eq ,ch (schar ,buffer ,i)))
		      then (return))
		   (incf ,i)))
	      
	      (buf-substr (from to buffer &optional downcasep)
		;; create a string containing [from to }
		;;
		`(let ((res (make-string (- ,to ,from))))
		   (do ((ii ,from (1+ ii))
			(ind 0 (1+ ind)))
		       ((>= ii ,to))
		     (setf (schar res ind)
		       ,(if* downcasep
			   then `(char-downcase (schar ,buffer ii))
			   else `(schar ,buffer ii))))
		   res)))
     
     ,@body))


(defun do-http-request (uri 
			&rest args
			&key 
			(method  :get)
			(protocol  :http/1.1)
			(accept "*/*")
			content
			(format :text) ; or :binary
			cookies ; nil or a cookie-jar
			(redirect t) ; auto redirect if needed
			basic-authorization  ; (name . password)
			
			      )
  
  ;; send an http request and return the result as three values:
  ;; the response code, the headers and the body
  (let ((creq (make-http-client-request 
	       uri  
	       :method method
	       :protocol protocol
	       :accept  accept
	       :content content
	       :cookies cookies
	       :basic-authorization basic-authorization
	       )))

    (unwind-protect
	(progn 
	  (read-client-response-headers creq)
	  (let* ((atype (if* (eq format :text) 
			   then 'character
			   else '(unsigned-byte 8)))
		 ans
		 res
		 (start 0)
		 (end nil)
		 body)
	    (loop
	
	      (if* (null ans)
		 then (setq ans (make-array 1024 :element-type atype)
			    start 0))
		
	
	      (setq end (client-request-read-sequence ans creq :start start))
	      (if* (zerop end)
		 then ; eof
		      (return))
	      (if* (eql end 1024)
		 then ; filled up
		      (push ans res)
		      (setq ans nil)
		 else (setq start end)))
      
	    ; we're out with res containing full arrays and 
	    ; ans either nil or holding partial data up to but not including
	    ; index start
      
	    (if* res
	       then ; multiple items
		    (let* ((total-size (+ (* 1024 (length res)) start))
			   (bigarr (make-array total-size :element-type atype)))
		      (let ((sstart 0))
			(dolist (arr (reverse res))
			  (replace bigarr arr :start1 sstart)
			  (incf sstart (length arr)))
			(if* ans 
			   then ; final one 
				(replace bigarr ans :start1 sstart)))
		
		      (setq body bigarr)
		      )
	       else ; only one item
		    (if* (eql 0 start)
		       then ; nothing returned
			    (setq body nil)
		       else (setq body (subseq ans 0 start))))

	    (if* (and redirect
		      (eql 302 (client-request-response-code creq)))
	       then ; must do a redirect to get to the read site
		    (format t "doing redirect~%")
		    
		    (apply #'do-http-request
			   (net.uri:merge-uris
			    (cdr (assoc "location" (client-request-headers creq)
					:test #'equal))
			    uri)
			   args)
	       else ; return the values
		    (values 
		     (client-request-response-code creq)
		     (client-request-headers  creq)
		     body))))
      
      ; protected form:
      (client-request-close creq))))


    
		
		
		
		
		
		
		      



(defun make-http-client-request (uri &key 
				     (method  :get)  ; :get, :post, ....
				     (protocol  :http/1.1)
				     keep-alive 
				     (accept "*/*") 
				     cookies  ; nil or a cookie-jar
				     basic-authorization
				     content-length 
				     content)
  
   
  ;; start a request 
  
  ; parse the uri we're accessing
  (if* (not (typep uri 'net.uri:uri))
     then (setq uri (net.uri:parse-uri uri)))
  
  ; make sure it's an http uri
  (if* (not (eq :http (or (net.uri:uri-scheme uri) :http)))
     then (error "Can only do client access of http uri's, not ~s" uri))
  
  ; make sure that there's a host
  (let ((host (net.uri:uri-host uri))
	(sock)
	(port))
    (if* (null host)
       then (error "need a host in the client request: ~s" uri))
    
    (setq sock 
      (socket:make-socket :remote-host host
			  :remote-port (setq port
					 (or (net.uri:uri-port uri) 80))
			  :format :bivalent))
    
    (format sock "~a ~a ~a~a"
	    (string-upcase (string method))
	    (or (net.uri:uri-path uri) "/")
	    (string-upcase (string protocol))
	    crlf)

    ; always send a Host header, required for http/1.1 and a good idea
    ; for http/1.0
    (if* (not (eql 80 port))
       then (format sock "Host: ~a:~a~a" host port crlf)
       else (format sock "Host: ~a~a" host crlf))
    
    ; now the headers
    (if* keep-alive
       then (format sock "Connection: Keep-Alive~a" crlf))

    (if* accept
       then (format sock "Accept: ~a~a" accept crlf))
    
    (if* content
       then (typecase content
	      ((array character (*)) nil)
	      ((array (unsigned-byte 8) (*)) nil)
	      (t (error "Illegal content array: ~s" content)))
	    
	    (setq content-length (length content)))
    
    (if* content-length
       then (format sock "Content-Length: ~s~a" content-length crlf))
    
	    
    (if* cookies 
       then (let ((str (compute-cookie-string uri
					      cookies)))
	      (if* str
		 then (format sock "Cookie: ~a~a" str crlf))))

    (if* basic-authorization
       then (format sock "Authorization: Basic ~a~a"
		    (base64-encode
		     (format nil "~a:~a" 
			     (car basic-authorization)
			     (cdr basic-authorization)))
		    crlf))
    

    (write-string crlf sock)  ; final crlf
    
    ; send out the content if there is any.
    ; this has to be done differently so that if it looks like we're
    ; going to block doing the write we start another process do the
    ; the write.  
    (if* content
       then (write-sequence content sock))
    
    
    (force-output sock)
    
    (make-instance 'client-request
      :uri uri
      :socket sock
      :cookies cookies
      )))


    
(defmethod read-client-response-headers ((creq client-request))
  ;; read the response and the headers
  (let ((buff (get-header-line-buffer))
	(buff2 (get-header-line-buffer))
	(pos 0)
	len
	len2
	(sock (client-request-socket creq))
	(headers)
	protocol
	response
	comment
	saveheader
	val
	)
    (unwind-protect
	(with-better-scan-macros
	    (if* (null (setq len (read-socket-line sock buff (length buff))))
	       then ; eof getting response
		    (error "premature eof from server"))
	  (macrolet ((fail ()
		       `(let ((i 0))
			  (error "illegal response from web server: ~s"
				 (collect-to-eol buff i len)))))
	    (setq protocol (collect-to #\space buff pos len))
	    (skip-to-not #\space buff pos len)
	    (setq response (collect-to #\space buff pos len))
	    (skip-to-not #\space buff pos len)
	    (setq comment (collect-to-eol buff pos len)))

	  (if* (equalp protocol "HTTP/1.0")
	     then (setq protocol :http/1.0)
	   elseif (equalp protocol "HTTP/1.1")
	     then (setq protocol :http/1.1)
	     else (error "unknown protocol: ~s" protocol))
      
	  (setf (client-request-protocol creq) protocol)
      
	  (setf (client-request-response-code creq) 
	    (quick-convert-to-integer response))
      
	  (setf (client-request-response-comment creq) comment)
      
     
	  ; now read the header lines
	  (loop
	    (if* saveheader
	       then ; buff2 has the saved header we should work on next
		    (psetf buff buff2  
			   buff2 buff)
		    (setq len len2
			  saveheader nil)
	     elseif (null (setq len (read-socket-line sock buff (length buff))))
	       then ; eof before header lines
		    (error "premature eof in headers"))
	    
	    
	    (if* (eql len 0)
	       then ; last header line
		    (return))
	  
	    ; got header line. Must get next one to see if it's a continuation
	    (if* (null (setq len2 (read-socket-line sock buff2 (length buff2))))
	       then ; eof before crlf ending the headers
		    (error "premature eof in headers")
	     elseif (and (> len2 0)
			 (eq #\space (schar buff2 0)))
	       then ; a continuation line
		    (if* (< (length buff) (+ len len2))
		       then (let ((buff3 (make-array (+ len len2 50)
						     :element-type 'character)))
			      (dotimes (i len)
				(setf (schar buff3 i) (schar buff i)))
			      (put-header-line-buffer buff)
			      (setq buff buff3)))
		    ; can all fit in buff
		    (do ((to len (1+ to))
			 (from 0 (1+ from)))
			((>= from len2))
		      (setf (schar buff to) (schar buff2 from))
		      )
	       else ; must be a new header line
		    (setq saveheader t))
	  
	    ; parse header
	    (let ((pos 0)
		  (headername)
		  (headervalue))
	      (macrolet ((fail ()
			   `(let ((i 0))
			      (error "header line missing a colon:  ~s" 
				     (collect-to-eol buff i len)))))
		(setq headername (collect-to #\: buff pos len :downcase)))
	  
	      (incf pos) ; past colon
	      (macrolet ((fail ()
			   `(progn (setq headervalue "")
				   (return))))
		(skip-to-not #\space buff pos len)
		(setq headervalue (collect-to-eol buff pos len)))
	  
	      (push (cons headername headervalue) headers)))
      
	  (setf (client-request-headers creq) headers)
	  
	  ;; do cookie processing
	  (let ((jar (client-request-cookies creq)))
	    (if* jar
	       then ; do all set-cookie requests
		    (dolist (headval headers)
		      (if* (equal "set-cookie" (car headval))
			 then (save-cookie
			       (client-request-uri creq)
			       jar
			       (cdr headval))))))
	  
	  
	  (if* (equalp "chunked" (client-response-header-value 
				  creq "transfer-encoding"))
	     then ; data will come back in chunked style
		  (setf (client-request-bytes-left creq) :chunked)
		  (socket:socket-control (client-request-socket creq)
				  :input-chunking t)
	   elseif (setq val (client-response-header-value
			     creq "content-length"))
	     then ; we know how many bytes are left
		  (setf (client-request-bytes-left creq) 
		    (quick-convert-to-integer val))
	   elseif (not (equalp "keep-alive"
			       (client-response-header-value
				creq "connection")))
	     then ; connection will close, let it indicate eof
		  (setf (client-request-bytes-left creq) :unknown)
	     else ; no data in the response
		  nil)
	  
		  
	  
	  creq  ; return the client request object
	  )
      (progn (put-header-line-buffer buff2 buff)))))
		  


(defmethod client-request-read-sequence (buffer
					 (creq client-request)
					 &key
					 (start 0)
					 (end (length buffer)))
  ;; read the next (end-start) bytes from the body of client request, handling
  ;;   turning on chunking if needed
  ;;   return index after last byte read.
  ;;   return 0 if eof
  (let ((bytes-left (client-request-bytes-left creq))
	(socket (client-request-socket creq))
	(last start))
    (if* (integerp bytes-left)
       then ; just a normal read-sequence
	    (if* (zerop bytes-left)
	       then 0  ; eof
	       else (let ((ans (read-sequence buffer socket :start start
					      :end (+ start 
						      (min (- end start) 
							   bytes-left)))))
		      (if* (eq ans start)
			 then 0  ; eof
			 else (setf (client-request-bytes-left creq)
				(- bytes-left (- ans start)))
			      ans)))
     elseif (or (eq bytes-left :chunked)
		(eq bytes-left :unknown))
       then (handler-case (do ((i start (1+ i))
			       (stringp (stringp buffer)))
			      ((>= i end) (setq last end))
			    (setq last i)
			    (let ((ch (if* stringp
					 then (read-char socket nil nil)
					 else (read-byte socket nil nil))))
			      (if* (null ch)
				 then (return)
				 else (setf (aref buffer i) ch))))
	      (excl::socket-chunking-end-of-file
		  (cond)
		(declare (ignore cond))
		; remember that there is no more data left
		(setf (client-request-bytes-left creq) :eof)
		nil))
	    ; we return zero on eof, regarless of the value of start
	    ; I think that this is ok, the spec isn't completely clear
	    (if* (eql last start) 
	       then 0 
	       else last)
     elseif (eq bytes-left :eof)
       then 0
       else (error "socket not setup for read correctly")
	    )))
  

(defmethod client-request-close ((creq client-request))
  (close (client-request-socket creq)))


(defun quick-convert-to-integer (str)
  ; take the simple string and convert it to an integer
  ; it's assumed to be a positive number
  ; no error checking is done.
  (let ((res 0))
    (dotimes (i (length str))
      (let ((chn (- (char-code (schar str i)) #.(char-code #\0))))
	(if* (<= 0 chn 9)
	   then (setq res (+ (* 10 res) chn)))))
    res))


(defmethod client-response-header-value ((creq client-request)
					 name &key parse)
  ;; return the value associated with the given name
  ;; parse it too if requested
  (let ((val (cdr (assoc name (client-request-headers creq) :test #'equal))))
    (if* (and parse val)
       then (net.iserve::parse-header-value val)
       else val)))

    
  


(defun read-socket-line (socket buffer max)
  ;; read the next line from the socket.
  ;; the line may end with a newline or a return, newline, or eof
  ;; in any case don't put that the end of line characters in the buffer
  ;; return the number of characters in the buffer which will be zero
  ;; for an empty line.
  ;; on eof return nil
  ;;
  (let ((i 0))
    (loop
      (let ((ch (read-char socket nil nil)))
	(if* (null ch)
	   then ; eof from socket
		(if* (> i 0)
		   then ; actually read some stuff first
			(return i)
		   else (return nil) ; eof
			)
	 elseif (eq ch #\return)
	   thenret ; ignore
	 elseif (eq ch #\newline)
	   then ; end of the line,
		(return i)
	 elseif (< i max)
	   then ; ignore characters beyone line end
		(setf (schar buffer i) ch)
		(incf i))))))
		
		
    
      
;; buffer pool for string buffers of the right size for a header
;; line

(defvar *response-header-buffers* nil)

(defun get-header-line-buffer ()
  ;; return the next header line buffer
  (let (buff)
    (mp:without-scheduling 
      (setq buff (pop *response-header-buffers*)))
    (if* buff
       thenret
       else (make-array 200 :element-type 'character))))

(defun put-header-line-buffer (buff &optional buff2)
  ;; put back up to two buffers
  (mp:without-scheduling
    (push buff *response-header-buffers*)
    (if* buff2 then (push buff2 *response-header-buffers*))))



    

;;;;; cookies

(defclass cookie-jar ()
  ;; holds all the cookies we've received
  ;; items is a alist where each item has the following form:
  ;; (hostname cookie-item ...)
  ;; 
  ;; where hostname is a string that must be the suffix
  ;;	of the requesting host to match
  ;; path is a string that must be the prefix of the requesting host
  ;;	to match
  ;;  
  ;;
  ((items :initform nil
	  :accessor cookie-jar-items)))

;* for a given hostname, there will be only one cookie with
; a given (path,name) pair
;
(defstruct cookie-item 
  path      ; a string that must be the prefix of the requesting host to match
  name	    ; the name of this cookie
  value	    ; the value of this cookie
  expires   ; when this cookie expires
  secure    ; t if can only be sent over a secure server
  )


(defmethod save-cookie (uri (jar cookie-jar) cookie)
  ;; we've made a request to the given host and gotten back
  ;; a set-cookie header with cookie as the value 
  ;; jar is the cookie jar into which we want to store the cookie
  
  (let* ((pval (car (net.iserve::parse-header-value cookie t)))
	 namevalue
	 others
	 path
	 domain
	 )
    (if* (consp pval)
       then ; (:param namevalue . etc)
	    (setq namevalue (cadr pval)
		  others (cddr pval))
     elseif (stringp pval)
       then (setq namevalue pval)
       else ; nothing here
	    (return-from save-cookie nil))
    
    ;; namevalue has the form name=value
    (setq namevalue (net.iserve::split-on-character namevalue #\=))
    
    ;; compute path
    (setq path (cdr (net.iserve::assoc-paramval "path" others)))
    (if* (null path)
       then (setq path (or (net.uri:uri-path uri) "/"))
       else ; make sure it's a prefix
	    (if* (not (net.iserve::match-head-p 
		       path (or (net.uri:uri-path uri) "/")))
	       then ; not a prefix, don't save
		    (return-from save-cookie nil)))
    
    ;; compute domain
    (setq domain (cdr (net.iserve::assoc-paramval "domain" others)))
    
    (if* domain
       then ; one is given, test to see if it's a substring
	    ; of the host we used
	    (if* (null (net.iserve::match-tail-p domain 
						 (net.uri:uri-host uri)))
	       then (return-from save-cookie nil))
       else (setq domain (net.uri:uri-host uri)))
    
    
    (let ((item (make-cookie-item
		 :path path
		 :name  (car namevalue)
		 :value (or (cadr namevalue) "")
		 :secure (net.iserve::assoc-paramval "secure" others)
		 :expires (cdr (net.iserve::assoc-paramval "expires" others))
		 )))
      ; now put in the cookie jar
      (let ((domain-vals (assoc domain (cookie-jar-items jar) :test #'equal)))
	(if* (null domain-vals)
	   then ; this it the first time for this host
		(push (list domain item) (cookie-jar-items jar))
	   else ; this isn't the first
		; check for matching path and name
		(do* ((xx (cdr domain-vals) (cdr xx))
		     (thisitem (car xx) (car xx)))
		    ((null xx)
		     )
		  (if* (and (equal (cookie-item-path thisitem)
				   path)
			    (equal (cookie-item-name thisitem)
				   (car namevalue)))
		     then ; replace this one
			  (setf (car xx) item)
			  (return-from save-cookie nil)))
		
		; no match, must insert based on the path length
		(do* ((prev nil xx)
		      (xx (cdr domain-vals) (cdr xx))
		      (thisitem (car xx) (car xx))
		      (length (length path)))
		    ((null xx)
		     ; put at end
		     (if* (null prev) then (setq prev domain-vals))
		     (setf (cdr prev) (cons item nil)))
		  (if* (>= (length (cookie-item-path thisitem)) length)
		     then ; can insert here
			  (if* prev
			     then (setf (cdr prev)
				    (cons item xx))
				  
			     else ; at the beginning
				  (setf (cdr domain-vals)
				    (cons item (cdr domain-vals))))
			  (return-from save-cookie nil))))))))
		  
      

(defparameter semicrlf 
    ;; useful for separating cookies, one per line
    (make-array 4 :element-type 'character
		:initial-contents '(#\; #\return
				    #\linefeed #\space)))

(defmethod compute-cookie-string (uri (jar cookie-jar))
  ;; compute a string of the applicable cookies.
  ;;
  (let ((host (net.uri:uri-host uri))
	(path (or (net.uri:uri-path uri) "/"))
	res
	rres)
    
    (dolist (hostval (cookie-jar-items jar))
      (if* (net.iserve::match-tail-p (car hostval)
				     host)
	 then ; ok for this host
	      (dolist (item (cdr hostval))
		(if* (net.iserve::match-head-p (cookie-item-path item)
					       path)
		   then ; this one matches
			(push item res)))))
    
    (if* res
       then ; have some cookies to return
	    (dolist (item res)
	      (push (cookie-item-value item) rres)
	      (push "=" rres)
	      (push (cookie-item-name item) rres)
	      (push semicrlf rres))
	    
	    (pop rres) ; remove first semicrlf
	    (apply #'concatenate 'string  rres))))

			   
			   
   
    
    
  





    
  
	    
  
		 




		      
			
					   
  
			
		      
  


		
		

	    
    
	      
    
    
    
      
    
  
  
