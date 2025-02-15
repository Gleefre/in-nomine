;;;; This file is a part of IN-NOMINE.
;;;; Copyright (c) 2015 Masataro Asai (guicho2.71828@gmail.com),
;;;;               2022 Michał "phoe" Herda (phoe@disroot.org)


(defpackage #:in-nomine/test
  (:use #:cl
        #:in-nomine
        #:fiveam)
  ;; Private symbols for testing.
  (:import-from #:in-nomine
                #:*namespaces*
                #:ensure-namespace)
  (:import-from #:alexandria
                #:type=
                #:ignore-some-conditions)
  (:import-from #:introspect-environment
                #:typexpand-1)
  (:import-from #:closer-mop
                #:intern-eql-specializer)
  (:export #:in-nomine))

(in-package #:in-nomine/test)

(def-suite in-nomine)
(in-suite in-nomine)

;;; Internal structure tests

(test internal-structure
  (let* ((ns1 *namespaces*)
         (ns2 (symbol-namespace 'namespace))
         (ns3 (ensure-namespace 'namespace))
         (ns4 (gethash 'namespace (namespace-binding-table ns1)))
         (ns5 (gethash 'namespace (namespace-binding-table ns2)))
         (ns6 (gethash 'namespace (namespace-binding-table ns3))))
    (is (eq ns1 ns2))
    (is (eq ns1 ns3))
    (is (eq ns1 ns4))
    (is (eq ns1 ns5))
    (is (eq ns1 ns6))))

;;; Condition tests

(test makunbound-metanamespace
  (multiple-value-bind (value condition)
      (ignore-errors (namespace-makunbound 'namespace))
    (is (null value))
    (is (typep condition 'error))
    (is (string= (princ-to-string condition)
                 (format nil "Unable to remove the NAMESPACE namespace.")))))

(test macroexpansion-time-errors
  (multiple-value-bind (value condition)
      (ignore-errors (macroexpand-1 `(define-namespace cl:car t)))
    (is (null value))
    (is (typep condition 'error))
    (is (string= (princ-to-string condition)
                 (format nil "~S is a standard Common Lisp symbol and it ~
                              cannot be used as a namespace name."
                         'cl:car))))
  (multiple-value-bind (value condition)
      (ignore-errors
       (flet ((validate-restart (condition)
                (let ((restart (find-restart 'continue condition)))
                  (is (string= (princ-to-string restart)
                               "Redefine the namespace.")))))
         (handler-bind ((error #'validate-restart))
           (macroexpand-1 `(define-namespace namespace t)))))
    (is (null value))
    (is (typep condition 'error))
    (is (string= (princ-to-string condition)
                 (format nil "Attempting to redefine namespace NAMESPACE.")))))

;;; Metanamespace

(defmacro with-namespace ((name value) &body body)
  ;; NOTE: HANDLER-BIND is here to muffle any redefinition warnings which may
  ;;       happen when reevaluating DEFINE-NAMESPACE, which may happen when
  ;;       running the test suite multiple times in a row.
  `(let ((,name (handler-bind ((warning #'muffle-warning)) ,value)))
     (declare (ignorable ,name))
     ,@body))

(test metanamespace
  (with-namespace (namespace *namespaces*)
    ;; Name
    (is (eq 'namespace (namespace-name namespace)))
    ;; Accessor
    (let ((accessor (namespace-accessor namespace)))
      (is (eq 'symbol-namespace accessor))
      (is (eq namespace (funcall accessor 'namespace)))
      ;; Condition
      (let ((condition-name (namespace-condition-name namespace)))
        (is (eq 'unbound-namespace condition-name))
        (flet ((verify-cell-error-name (condition)
                 (is (eq 'yet-another-namespace (cell-error-name condition)))))
          (signals unbound-namespace
            (handler-bind ((unbound-namespace #'verify-cell-error-name))
              (funcall accessor 'yet-another-namespace))))
        ;; No tests for writer, boundp, and makunbound, because the NAMESPACE
        ;; namespace does not have them.
        ))
    ;; Type name
    (let ((type-name (namespace-type-name namespace)))
      (is (null type-name)))
    ;; Type
    (let ((value-type (namespace-value-type namespace)))
      (is (eq 'namespace value-type)))
    ;; Behavior booleans
    (let ((errorp (namespace-error-when-not-found-p namespace))
          (errorpp (namespace-errorp-arg-in-accessor-p namespace))
          (defaultp (namespace-default-arg-in-accessor-p namespace)))
      (is (eq 't errorp)
          (eq 'nil errorpp)
          (eq 't defaultp)))
    ;; Binding table
    (let ((binding-table (namespace-binding-table namespace)))
      (is (hash-table-p binding-table))
      (is (eq namespace (gethash 'namespace binding-table))))
    ;; Docstrings for namespaces are managed by namespace objects themselves,
    ;; hence both documentation type and table are meant to be null.
    (progn
      (let ((documentation-type (namespace-documentation-type namespace)))
        (is (null documentation-type)))
      (let ((documentation-table (namespace-documentation-table namespace)))
        (is (null documentation-table))))
    ;; Documentation
    (is (string= "A namespace for managing namespaces."
                 (documentation 'namespace 'namespace)))
    (is (string= "A namespace for managing namespaces."
                 (documentation namespace 't)))))

;;; Short form tests

(test short-form
  (with-namespace (namespace (define-namespace thing keyword nil
                               "A thing namespace."))
    ;; Return value of DEFINE-NAMESPACE
    (is (typep namespace 'namespace))
    ;; Name
    (is (eq 'thing (namespace-name namespace)))
    ;; Accessor
    (let ((accessor (namespace-accessor namespace)))
      (is (eq 'symbol-thing accessor))
      (funcall (fdefinition `(setf ,accessor)) :thing 'this-thing)
      (is (eq :thing (funcall accessor 'this-thing)))
      ;; Condition
      (let ((condition-name (namespace-condition-name namespace)))
        (is (eq 'unbound-thing condition-name))
        (flet ((verify-cell-error-name (condition)
                 (is (eq 'that-thing (cell-error-name condition)))))
          (signals unbound-thing
            (handler-bind ((unbound-thing #'verify-cell-error-name))
              (funcall accessor 'that-thing))))
        ;; Binding table
        (let ((binding-table (namespace-binding-table namespace)))
          (is (hash-table-p binding-table))
          (is (eq 'eq (hash-table-test binding-table)))
          (is (eq :thing (gethash 'this-thing binding-table))))
        ;; Boundp
        (let ((boundp-symbol (namespace-boundp-symbol namespace)))
          (is (eq 'thing-boundp boundp-symbol))
          (is (funcall boundp-symbol 'this-thing))
          (is (null (funcall boundp-symbol 'that-thing)))
          ;; Makunbound
          (let ((makunbound-symbol (namespace-makunbound-symbol namespace)))
            (is (eq 'thing-makunbound makunbound-symbol))
            (funcall makunbound-symbol 'this-thing)
            (is (null (funcall boundp-symbol 'this-thing))))
          ;; Accessor default arg
          (is (eq :thing (funcall accessor 'this-thing :thing)))
          (is (eq :thing (funcall accessor 'this-thing)))))
      ;; CLEAR-NAMESPACE
      (funcall (fdefinition `(setf ,accessor)) :nothing 'that-thing)
      (is (eq :thing (funcall accessor 'this-thing)))
      (is (eq :nothing (funcall accessor 'that-thing)))
      (clear-namespace 'thing)
      (signals unbound-thing (funcall accessor 'this-thing))
      (signals unbound-thing (funcall accessor 'that-thing))
      ;; Restarts
      (flet ((handle (c) (use-value :thing c)))
        (is (eq :thing (handler-bind ((unbound-thing #'handle))
                         (funcall accessor 'this-thing)))))
      (signals unbound-thing (funcall accessor 'this-thing))
      (flet ((handle (c) (store-value :thing c)))
        (is (eq :thing (handler-bind ((unbound-thing #'handle))
                         (funcall accessor 'this-thing)))))
      (is (eq :thing (funcall accessor 'this-thing))))
    ;; Hash table test
    (let ((test (namespace-hash-table-test namespace)))
      (eq test 'eq))
    ;; Type name
    (let ((type-name (namespace-type-name namespace)))
      (is (eq 'thing-type type-name))
      (is (type= 'keyword type-name)))
    ;; Type
    (let ((value-type (namespace-value-type namespace)))
      (is (eq 'keyword value-type)))
    ;; Documentation
    (is (symbol-thing 'this-thing))
    (is (string= "A thing."
                 (setf (documentation 'this-thing 'thing) "A thing.")))
    (is (string= "A thing." (documentation 'this-thing 'thing)))
    ;; Documentation table
    (let ((documentation-table (namespace-documentation-table namespace)))
      (is (hash-table-p documentation-table))
      (is (eq 'eq (hash-table-test documentation-table)))
      (is (string= "A thing." (gethash 'this-thing documentation-table))))
    ;; Documentation
    (is (string= "A thing namespace." (documentation 'thing 'namespace)))
    (is (string= "A thing namespace." (documentation namespace 't)))
    ;; Definer
    (is (null (namespace-definer-name namespace)))
    (is (null (namespace-definer namespace)))
    (clear-namespace 'thing)))

;;; Long form tests

(test long-form-customized
  (with-namespace (namespace (define-namespace stuff
                               :name-type string
                               :value-type string
                               :accessor string-stuff
                               :condition-name not-enough-stuff
                               :type-name stuff
                               :makunbound-symbol yeet-stuff
                               :boundp-symbol stuff-exists-p
                               :documentation-type some-stuff
                               :error-when-not-found-p t
                               :errorp-arg-in-accessor-p t
                               :default-arg-in-accessor-p t
                               :hash-table-test equal
                               :documentation "Stuff."
                               :binding-table-var *binding-stuff*
                               :documentation-table-var *documentation-stuff*
                               :definer-name defstuff
                               :definer t))
    ;; Return value of DEFINE-NAMESPACE
    (is (typep namespace 'namespace))
    ;; Name
    (is (eq 'stuff (namespace-name namespace)))
    ;; Accessor
    (let ((accessor (namespace-accessor namespace)))
      (is (eq 'string-stuff accessor))
      (funcall (fdefinition `(setf ,accessor)) "value-1" "key-1")
      (is (equal "value-1" (funcall accessor "key-1")))
      ;; Condition
      (let ((condition-name (namespace-condition-name namespace)))
        (is (eq 'not-enough-stuff condition-name))
        (flet ((verify-cell-error-name (condition)
                 (is (equal "key-2" (cell-error-name condition)))))
          (signals not-enough-stuff
            (handler-bind ((not-enough-stuff #'verify-cell-error-name))
              (funcall accessor "key-2"))))
        ;; Binding table
        (is (null (namespace-binding-table namespace)))
        (is (boundp '*binding-stuff*))
        (locally (declare (special *binding-stuff*))
          (is (hash-table-p *binding-stuff*))
          (is (equal "value-1" (gethash "key-1" *binding-stuff*)))
          (is (eq *binding-stuff* (symbol-value '*binding-stuff*))))
        ;; Boundp
        (let ((boundp-symbol (namespace-boundp-symbol namespace)))
          (is (eq 'stuff-exists-p boundp-symbol))
          (is (funcall boundp-symbol "key-1"))
          (is (null (funcall boundp-symbol "key-2")))
          ;; Makunbound
          (let ((makunbound-symbol (namespace-makunbound-symbol namespace)))
            (is (eq 'yeet-stuff makunbound-symbol))
            (funcall makunbound-symbol "key-1")
            (is (null (funcall boundp-symbol "key-1")))))
        ;; Accessor errorp arg here
        (is (null (funcall accessor "key-1" nil)))
        ;; Accessor default arg
        (is (equal "value-1" (funcall accessor "key-1" nil "value-1")))
        (is (equal "value-1" (funcall accessor "key-1" nil))))
      ;; CLEAR-NAMESPACE
      (funcall (fdefinition `(setf ,accessor)) "value-2" "key-2")
      (is (equal "value-1" (funcall accessor "key-1")))
      (is (equal "value-2" (funcall accessor "key-2")))
      (clear-namespace 'stuff)
      (signals not-enough-stuff (funcall accessor "key-1"))
      (signals not-enough-stuff (funcall accessor "key-2"))
      ;; Restarts
      (flet ((handle (c) (use-value "value" c)))
        (is (equal "value" (handler-bind ((not-enough-stuff #'handle))
                             (funcall accessor "key")))))
      (signals not-enough-stuff (funcall accessor "key"))
      (flet ((handle (c) (store-value "value" c)))
        (is (equal "value" (handler-bind ((not-enough-stuff #'handle))
                             (funcall accessor "key")))))
      (is (equal "value" (funcall accessor "key"))))
    ;; Type name
    (let ((type-name (namespace-type-name namespace)))
      (is (eq 'stuff type-name))
      (is (type= 'string type-name)))
    ;; Type
    (let ((value-type (namespace-value-type namespace)))
      (is (eq 'string value-type)))
    ;; Namespace documentation
    (is (string= "Stuff." (documentation 'stuff 'namespace)))
    (is (string= "Stuff." (documentation namespace 't)))
    ;; Value documentation
    (is (string= "docs" (setf (documentation "key" 'some-stuff) "docs")))
    (is (string= "docs" (documentation "key" 'some-stuff)))
    ;; Documentation table
    (let ((documentation-table (namespace-documentation-table namespace)))
      (is (hash-table-p documentation-table))
      (is (string= "docs" (gethash "key" documentation-table)))
      (is (eq documentation-table (symbol-value '*documentation-stuff*))))
    ;; Definer
    (is (eq 'defstuff (namespace-definer-name namespace)))
    (is (fboundp 'defstuff))
    (let ((some-stuff (eval '(defstuff "some-stuff" "Hello world"))))
      (is (string= "Hello world" some-stuff))
      (is (string= "Hello world" (string-stuff "some-stuff"))))))

(test long-form-definer-default-name
  (with-namespace (namespace (define-namespace default-definer
                               :definer t))
    (is (eq (namespace-definer-name namespace)
            'define-default-definer))
    (is (fboundp 'define-default-definer))
    (let ((some-val (eval '(define-default-definer something 7))))
      (is (= 7 some-val))
      (is (= 7 (symbol-default-definer 'something))))))

(test long-form-definer-only-name
  (with-namespace (namespace (define-namespace only-name
                               :definer-name defonly))
    (is (eq (namespace-definer-name namespace)
            'defonly))
    (is (fboundp 'defonly))
    (let ((val (eval '(defonly val 3))))
      (is (= 3 val))
      (is (= 3 (symbol-only-name 'val))))))

(test long-form-definer-function
  (with-namespace (namespace (define-namespace function-definer-simple
                               :definer cons))
    (let ((val (eval `(define-function-definer-simple val :a :b))))
      (is (eq :a (car val)))
      (is (eq :b (cdr val)))
      (let ((nval (symbol-function-definer-simple 'val)))
        (is (eq :a (car nval)))
        (is (eq :b (cdr nval))))))
  (with-namespace (namespace (define-namespace function-definer-quoted
                               :definer 'cons))
    (let ((val (eval `(define-function-definer-quoted val :a :b))))
      (is (eq :a (car val)))
      (is (eq :b (cdr val)))
      (let ((nval (symbol-function-definer-quoted 'val)))
        (is (eq :a (car nval)))
        (is (eq :b (cdr nval))))))
  (with-namespace (namespace (define-namespace function-definer-fun
                               :definer #'cons))
    (let ((val (eval `(define-function-definer-fun val :a :b))))
      (is (eq :a (car val)))
      (is (eq :b (cdr val)))
      (let ((nval (symbol-function-definer-fun 'val)))
        (is (eq :a (car nval)))
        (is (eq :b (cdr nval))))))
  (with-namespace (namespace (define-namespace function-definer-lambda
                               :definer (lambda (a b)
                                          (+ a b))))
    (let ((val (eval `(define-function-definer-lambda val 3 4))))
      (is (eq 7 val))
      (is (eq 7 (symbol-function-definer-lambda 'val))))))

(test long-form-definer-macro
  (with-namespace (namespace (define-namespace function-definer-macro
                               :definer (((&rest args)
                                          &body body)
                                         `(lambda (,@args)
                                            ,@body))))
    (let ((f (eval `(define-function-definer-macro f (a b)
                      (+ a b)))))
      (is (eq f (symbol-function-definer-macro 'f)))
      (is (functionp f))
      (is (= 7 (funcall f 3 4))))))

(test long-form-default-values
  (with-namespace (namespace (define-namespace default
                               ;; A single keyword argument is required to
                               ;; trigger the long form.
                               :documentation nil))
    (macrolet ((frob (&rest args)
                 (loop for (accessor expected) on args by #'cddr
                       collect `(is (eq ,expected (,accessor namespace)))
                         into result
                       finally (return `(progn ,@result)))))
      (frob namespace-name 'default
            namespace-name-type 'symbol
            namespace-value-type 't
            namespace-accessor 'symbol-default
            namespace-condition-name 'unbound-default
            namespace-type-name 'default-type
            namespace-makunbound-symbol 'default-makunbound
            namespace-boundp-symbol 'default-boundp
            namespace-documentation-type 'default
            namespace-hash-table-test 'eq
            namespace-error-when-not-found-p 't
            namespace-errorp-arg-in-accessor-p 'nil
            namespace-default-arg-in-accessor-p 't
            namespace-definer-name 'nil
            namespace-definer 'nil)
      (is (not (fboundp 'define-default)))
      (let ((binding-table (namespace-binding-table namespace)))
        (is (eq 'eq (hash-table-test binding-table)))
        (is (= 0 (hash-table-count binding-table))))
      (let ((documentation-table (namespace-documentation-table namespace)))
        (is (eq 'eq (hash-table-test documentation-table)))
        (is (= 0 (hash-table-count documentation-table))))
      (let* ((specializers (list (find-class 't)
                                 (intern-eql-specializer 'default)))
             (method (find-method #'documentation '() specializers nil)))
        (is (not (null method))))
      (let* ((specializers (list (find-class 't)
                                 (find-class 't)
                                 (intern-eql-specializer 'default)))
             (method (find-method #'(setf documentation) '() specializers nil)))
        (is (not (null method)))))))

(test long-form-null-values
  (with-namespace (namespace (define-namespace empty
                               :accessor nil
                               :name-type nil
                               :value-type nil
                               :makunbound-symbol nil
                               :boundp-symbol nil
                               :type-name nil
                               :documentation-type nil
                               :condition-name nil
                               :hash-table-test nil
                               :error-when-not-found-p nil
                               :errorp-arg-in-accessor-p nil
                               :default-arg-in-accessor-p nil
                               :definer-name nil
                               :definer nil))
    (macrolet ((frob (&rest args)
                 (loop for (accessor expected) on args by #'cddr
                       collect `(is (eq ,expected (,accessor namespace)))
                         into result
                       finally (return `(progn ,@result)))))
      (frob namespace-name 'empty
            namespace-name-type nil
            namespace-value-type nil
            namespace-accessor nil
            namespace-condition-name nil
            namespace-type-name nil
            namespace-makunbound-symbol nil
            namespace-boundp-symbol nil
            namespace-documentation-type nil
            namespace-hash-table-test nil
            namespace-error-when-not-found-p nil
            namespace-errorp-arg-in-accessor-p nil
            namespace-default-arg-in-accessor-p nil
            namespace-binding-table nil
            namespace-documentation-table nil
            namespace-definer-name nil
            namespace-definer nil)
      (is (namespace-boundp 'empty))
      (is (not (fboundp 'symbol-empty)))
      (is (not (fboundp 'symbol-makunbound)))
      (is (not (fboundp 'symbol-boundp)))
      (flet ((type-boundp (x) (or (find-class x nil)
                                  (nth-value 1 (typexpand-1 x)))))
        (is (not (type-boundp 'empty-type)))
        (is (not (type-boundp 'unbound-empty))))
      (let* ((specializers (list (find-class 't)
                                 (intern-eql-specializer 'empty)))
             (method (find-method #'documentation '() specializers nil)))
        (is (null method)))
      (let* ((specializers (list (find-class 't)
                                 (find-class 't)
                                 (intern-eql-specializer 'empty)))
             (method (find-method #'(setf documentation) '() specializers nil)))
        (is (null method))))))

(test describe-object-in-namespace
  (with-namespace (namespace (define-namespace something))
    (let ((docstring "Namespace test - FOO to BAR in SOMETHING"))
      (setf (symbol-something :foo) :bar
            (documentation :foo 'something) docstring)
      (let ((description (with-output-to-string (stream)
                           (describe-object :foo stream))))
        (is (search docstring description))))))
