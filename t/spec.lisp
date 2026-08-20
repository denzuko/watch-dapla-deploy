;;;; t/spec.lisp -- watch-dapla-deploy/spec
;;;;
;;;; Full coverage spec for watch-dapla-deploy/deploy exports.
;;;; Run: (asdf:test-system :watch-dapla-deploy/spec)

(defpackage :watch-dapla-deploy/spec
  (:use :cl :fiveam)
  (:import-from :watch-dapla-deploy/deploy
                :invidious-network-sections
                :invidious-container-sections
                :haproxy-vhost-config
                :cinix-write-string
                :decommissioned
                :deploy-app
                :quadlets-written
                :quadlets-activated
                :haproxy-vhost-written
                :zfs-encryption-key
                :zfs-dataset-mounted
                :rootless-service-account
                :images-pulled)
  (:export :run-spec))

(in-package :watch-dapla-deploy/spec)

(def-suite :watch-spec
  :description "Full coverage spec for watch-dapla-deploy.")

(in-suite :watch-spec)

(defun ini-lines (ini)
  (remove-if (lambda (l) (zerop (length l)))
             (mapcar (lambda (l) (string-trim '(#\Space #\Return) l))
                     (uiop:split-string ini :separator '(#\Newline)))))

(defun ini-has (ini sub)
  (some (lambda (l) (search sub l)) (ini-lines ini)))

(test cinix-single-section
  "cinix-write-string serialises a single section correctly."
  (let ((ini (cinix-write-string '(("S" . (("K" . "V")))))))
    (is (ini-has ini "[S]"))
    (is (ini-has ini "K=V"))))

(test cinix-section-order
  "cinix-write-string preserves section ordering."
  (let* ((ini (cinix-write-string '(("A" . (("K" . "1"))) ("B" . (("K" . "2"))))))
         (pa (search "[A]" ini)) (pb (search "[B]" ini)))
    (is (and pa pb (< pa pb)))))

(test network-bridge
  "Network unit uses netavark bridge, not Internal=true."
  (let ((ini (cinix-write-string (invidious-network-sections))))
    (is (ini-has ini "Driver=bridge"))
    (is (not (ini-has ini "Internal=true")))))

(test network-vlsm
  "Network unit has VLSM subnet 10.89.2.4/29 and gateway 10.89.2.5."
  (let ((ini (cinix-write-string (invidious-network-sections))))
    (is (ini-has ini "Subnet=10.89.2.4/29"))
    (is (ini-has ini "Gateway=10.89.2.5"))))

(test container-home-volume-ro
  "Container home profile volume uses %h specifier, read-only."
  (let* ((ini (cinix-write-string (invidious-container-sections)))
         (lines (ini-lines ini))
         (vol (find-if (lambda (l) (and (search "Volume=" l) (search "%h" l))) lines)))
    (is (not (null vol)) "No Volume=%%h line found")
    (when vol (is (search ":ro" vol) "Volume=%%h not read-only"))))

(test container-data-volume-srv
  "Writable data volume uses /srv/%U specifier."
  (is (ini-has (cinix-write-string (invidious-container-sections)) "Volume=/srv/%U")))

(test container-no-publish-port
  "Container unit has no PublishPort — netavark handles routing."
  (is (not (ini-has (cinix-write-string (invidious-container-sections)) "PublishPort"))))

(test container-cispec-labels
  "Container unit carries required org.cispec CMDB labels."
  (let ((ini (cinix-write-string (invidious-container-sections))))
    (is (ini-has ini "Label=org.cispec.managed-by=consfigurator"))))

(test container-image
  "Container unit uses correct OCI image oci.dapla.net/ghcr.io/iv-org/invidious:latest."
  (is (ini-has (cinix-write-string (invidious-container-sections)) "oci.dapla.net/ghcr.io/iv-org/invidious:latest")))

(test haproxy-tls-frontend
  "HAProxy config has TLS frontend on port 443."
  (is (search "bind *:443" (haproxy-vhost-config))))

(test haproxy-http-redirect
  "HAProxy config redirects HTTP to HTTPS."
  (is (search "redirect scheme https" (haproxy-vhost-config))))

(test haproxy-security-headers
  "HAProxy config sets all required security response headers."
  (let ((cfg (haproxy-vhost-config)))
    (is (search "Strict-Transport-Security" cfg))
    (is (search "X-Content-Type-Options" cfg))
    (is (search "X-Frame-Options" cfg))
    (is (search "Referrer-Policy" cfg))
    (is (search "Permissions-Policy" cfg))))

(test haproxy-netavark-backend
  "HAProxy backend targets netavark gateway 10.89.2.5:3000."
  (let ((cfg (haproxy-vhost-config)))
    (is (search "10.89.2.5:3000" cfg))
    (is (not (search "127.0.0.1" cfg)))))

(test haproxy-vhost-written-exported
  "haproxy-vhost-written is fbound and exported."
  (is (fboundp 'watch-dapla-deploy/deploy::haproxy-vhost-written)))

(test quadlets-written-exported
  "quadlets-written is fbound and exported."
  (is (fboundp 'watch-dapla-deploy/deploy::quadlets-written)))

(test quadlets-activated-exported
  "quadlets-activated is fbound and exported."
  (is (fboundp 'watch-dapla-deploy/deploy::quadlets-activated)))

(test zfs-encryption-key-exported
  "zfs-encryption-key is fbound and exported."
  (is (fboundp 'watch-dapla-deploy/deploy::zfs-encryption-key)))

(test zfs-dataset-mounted-exported
  "zfs-dataset-mounted is fbound and exported."
  (is (fboundp 'watch-dapla-deploy/deploy::zfs-dataset-mounted)))

(test rootless-service-account-exported
  "rootless-service-account is fbound and exported."
  (is (fboundp 'watch-dapla-deploy/deploy::rootless-service-account)))

(test images-pulled-exported
  "images-pulled is fbound and exported."
  (is (fboundp 'watch-dapla-deploy/deploy::images-pulled)))

(test decommissioned-exported
  "decommissioned is fbound and exported."
  (is (fboundp 'watch-dapla-deploy/deploy::decommissioned)))

(test deploy-app-exported
  "deploy-app is fbound and exported."
  (is (fboundp 'watch-dapla-deploy/deploy::deploy-app)))

(test container-sections-zero-arity
  "Container-sections function takes zero args after specifier refactor."
  (is (listp (ignore-errors (invidious-container-sections)))))

(defun run-spec ()
  "Run the full watch-dapla-deploy spec suite."
  (let ((results (run :watch-spec)))
    (fiveam:explain! results)
    (unless (every #'fiveam::test-passed-p results)
      (error "watch-dapla-deploy spec suite: one or more tests failed."))))
