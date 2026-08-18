;;;; t/e2e.lisp -- watch-dapla-deploy/e2e
;;;;
;;;; Post-deploy smoke tests for the Invidious stack. Run via
;;;; `./watch-dapla-deploy.ros e2e` against a live deployment.

(defpackage :watch-dapla-deploy/e2e
  (:use :cl :fiveam)
  (:import-from :watch-dapla-deploy/deploy :*haproxy-fqdn*)
  (:export :run-e2e))

(in-package :watch-dapla-deploy/e2e)

(def-suite :watch-dapla-deploy-e2e
  :description "Smoke tests for Invidious at watch.dapla.net.")

(in-suite :watch-dapla-deploy-e2e)

(defun base-url ()
  (format nil "https://~A" *haproxy-fqdn*))

(test http-redirect
  "Plain HTTP requests redirect to HTTPS."
  (multiple-value-bind (body status)
      (dex:get (format nil "http://~A/" *haproxy-fqdn*)
               :force-string t :want-stream nil
               :redirect nil)
    (declare (ignore body))
    (is (member status '(301 302)))))

(test frontend-responds
  "The Invidious frontend returns HTTP 200."
  (multiple-value-bind (body status)
      (dex:get (base-url) :force-string t :want-stream nil)
    (declare (ignore body))
    (is (= 200 status))))

(test api-search-endpoint
  "The /api/v1/search endpoint returns a JSON array."
  (multiple-value-bind (body status)
      (dex:get (format nil "~A/api/v1/search?q=test" (base-url))
               :force-string t :want-stream nil)
    (is (= 200 status))
    (is (char= #\[ (char (string-trim '(#\Space #\Tab #\Newline) body) 0)))))

(defun run-e2e ()
  "Run the post-deploy e2e suite and signal an error if any test fails."
  (let ((results (run :watch-dapla-deploy-e2e)))
    (unless (every #'fiveam::test-passed-p results)
      (error "watch-dapla-deploy e2e suite: one or more tests failed."))))
