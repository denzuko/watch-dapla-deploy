;;;; src/deploy.lisp -- watch-dapla-deploy/deploy core package
;;;;
;;;; Loaded as the :WATCH-DAPLA-DEPLOY/DEPLOY ASDF system. All Consfigurator
;;;; properties and the DEFHOST for the Invidious stack at watch.dapla.net
;;;; live here. watch-dapla-deploy.ros is a thin command wrapper around this
;;;; system; see watch-dapla-deploy.asd for the system definition and
;;;; t/e2e.lisp for the post-deploy validation suite.

(defpackage :watch-dapla-deploy/deploy
  (:use :cl)
  (:import-from :consfigurator
                :defprop :defhost :deploy :run :mrun :stripln
                :remote-exists-p :write-remote-file :on-change)
  (:import-from :consfigurator.property.file
                :has-content :containing-directory-exists)
  (:import-from :consfigurator.property.systemd :lingering-enabled)
  (:import-from :consfigurator.property.service :reloaded)
  (:export :*service-user* :*home-dataset* :*home-mountpoint*
           :*data-dataset* :*data-mountpoint*
           :*home-dataset-keyfile* :*data-dataset-keyfile*
           :*secrets-path* :*haproxy-fqdn*
           :deploy-app
           :zfs-encryption-key :zfs-dataset-mounted
           :rootless-service-account
           :images-pulled :quadlets-activated
           :cinix-write-string
           :quadlets-written
           :haproxy-vhost-written
           :decommissioned
           :invidious-container-sections
           :invidious-db-container-sections
           :invidious-network-sections
           :haproxy-vhost-config))

(in-package :watch-dapla-deploy/deploy)

(defparameter *service-user* "invidious"
  "Rootless system account the quadlets run under.")
(defparameter *home-dataset* "storage/users/invidious")
(defparameter *home-mountpoint* "/var/lib/invidious"
  "Service account home, backed by *HOME-DATASET*.")
(defparameter *home-dataset-keyfile* "/etc/zfs-keys/invidious-users.key"
  "Raw ZFS encryption key for *HOME-DATASET*.")
(defparameter *data-dataset* "storage/containers/invidious")
(defparameter *data-mountpoint* "/srv/invidious"
  "PostgreSQL data directory, backed by *DATA-DATASET*.")
(defparameter *data-dataset-keyfile* "/etc/zfs-keys/invidious-containers.key"
  "Raw ZFS encryption key for *DATA-DATASET*.")
(defparameter *secrets-path* "/var/lib/invidious/.env/db"
  "Generated once; holds POSTGRES_PASSWORD for the invidious database.")
(defparameter *haproxy-fqdn* "watch.dapla.net")
(defparameter *haproxy-vhost-name* "watch")

(defparameter *port-base* 10000
  "Added to the service account UID to derive the loopback PublishPort.
   Keeps all ports above 1024 and clear of well-known service ranges.")

(defparameter *config-path* "/var/lib/invidious/.config/invidious/config.yml"
  "Invidious application configuration file.")

(defprop zfs-encryption-key :posix (path)
  "Generate a raw 32-byte ZFS encryption key at PATH via `openssl rand -out`,
   once, left alone on redeploy. The key is written directly by openssl to
   avoid binary corruption through shell capture and string re-encoding."
  (:desc (format nil "ZFS encryption key at ~A" path))
  (:check (remote-exists-p path))
  (:apply
   (containing-directory-exists path)
   (mrun "openssl" "rand" "-out" path "32")
   (mrun "chmod" "600" path)))

(defun zfs-create-command (dataset mountpoint keyfile)
  "The `zfs create` command line for DATASET at MOUNTPOINT, with
   AES-256-GCM encryption keyed from KEYFILE when supplied."
  (if keyfile
      (format nil "zfs create -o mountpoint=~A -o encryption=aes-256-gcm -o keyformat=raw -o keylocation=file://~A ~A"
              mountpoint keyfile dataset)
      (format nil "zfs create -o mountpoint=~A ~A" mountpoint dataset)))

(defprop zfs-dataset-mounted :posix (dataset mountpoint &optional keyfile)
  "Ensure DATASET exists, mounted at MOUNTPOINT. When KEYFILE is given the
   dataset is created with AES-256-GCM native encryption. If the dataset
   exists but is not mounted, the key is loaded and the dataset mounted."
  (:desc (format nil "ZFS dataset ~A mounted at ~A~:[~; (encrypted)~]"
                  dataset mountpoint keyfile))
  (:check
   (multiple-value-bind (out err exit)
       (run :may-fail (format nil "zfs get -H -o value mounted ~A" dataset))
     (declare (ignore err))
     (and (zerop exit) (string= "yes" (stripln out)))))
  (:apply
   (if (zerop (mrun :for-exit (format nil "zfs list -H -o name ~A" dataset)))
       (progn
         (when keyfile (mrun (format nil "zfs load-key ~A" dataset)))
         (mrun (format nil "zfs mount ~A" dataset)))
       (mrun (zfs-create-command dataset mountpoint keyfile)))))

(defprop rootless-service-account :posix (username home)
  "Ensure a system account USERNAME exists with home directory HOME,
   without creating that directory. The home is ZFS-backed and provisioned
   by ZFS-DATASET-MOUNTED, so useradd -m would collide with a directory
   that is already present."
  (:desc (format nil "System account ~A at ~A" username home))
  (:check (zerop (mrun :for-exit "id" username)))
  (:apply (mrun "useradd" "--system" "--no-create-home"
                "--home-dir" home username)))

(defprop db-secret-file :posix (path user)
  "Generate the postgres password once via `openssl rand -hex 32` and
   persist it at PATH, mode 0600, owned by USER. Left alone on redeploy;
   the postgres data volume password cannot be rotated out from under it
   on every run. CONTAINING-DIRECTORY-EXISTS is always called first:
   WRITE-REMOTE-FILE has no directory-creation logic of its own."
  (:desc (format nil "DB secret at ~A" path))
  (:check (remote-exists-p path))
  (:apply
   (containing-directory-exists path)
   (let ((pass (stripln (mrun "openssl" "rand" "-hex" "32"))))
     (write-remote-file
      path
      (format nil "POSTGRES_PASSWORD=~A~%POSTGRES_USER=invidious~%POSTGRES_DB=invidious~%"
              pass)
      :mode #o600)
     (mrun "chown" (format nil "~A:~A" user user) path))))

(defprop invidious-config :posix (path user fqdn db-secret-path)
  "Write the Invidious config.yml at PATH. The database password is read
   from DB-SECRET-PATH at deploy time, so credentials are never hardcoded
   in this source file. Left alone on redeploy once present."
  (:desc (format nil "Invidious config.yml at ~A" path))
  (:check (remote-exists-p path))
  (:apply
   (containing-directory-exists path)
   (let* ((secret (uiop:read-file-string db-secret-path))
          (pass (second
                 (uiop:split-string
                  (first (remove-if-not
                          (lambda (l) (uiop:string-prefix-p "POSTGRES_PASSWORD=" l))
                          (uiop:split-string secret :separator '(#\Newline))))
                  :separator '(#\=)))))
     (write-remote-file
      path
      (format nil "channel_threads: 1~%feed_threads: 1~%~
db:~%  user: invidious~%  password: ~A~%  host: invidious-db~%  port: 5432~%  dbname: invidious~%~
check_tables: true~%external_port: 443~%domain: ~A~%https_only: true~%hsts: true~%~
admins:~%  - denzuko~%registration_enabled: false~%login_enabled: true~%statistics_enabled: false~%"
              pass fqdn)
      :mode #o600)
     (mrun "chown" (format nil "~A:~A" user user) path))))

(defprop images-pulled :posix (user &rest images)
  "Pull IMAGES into USER's rootless Podman image store via `machinectl shell`."
  (:desc (format nil "Podman images pulled for ~A" user))
  (:check
   (every (lambda (image)
            (zerop (mrun :for-exit
                    (format nil "machinectl shell ~A@ /usr/bin/podman image exists ~A"
                            user image))))
          images))
  (:apply
   (dolist (image images)
     (mrun (format nil "machinectl shell ~A@ /usr/bin/podman pull ~A" user image)))))

(defun cinix-write-string (sections)
  "Serialize an alist of (section-name . ((key . value) ...)) into
   INI/systemd unit-file text. The write-side counterpart to cl-inix's
   read-side parser; keys may repeat within a section since each section
   is an ordered list of conses."
  (with-output-to-string (s)
    (dolist (section sections)
      (format s "[~A]~%" (car section))
      (dolist (kv (cdr section))
        (format s "~A=~A~%" (car kv) (cdr kv)))
      (format s "~%"))))


(defun invidious-network-sections ()
  "Cinix AST for invidious.network: internal-only network."
  '(("Network" . (("NetworkName" . "watch")
                  ("Driver"      . "bridge")
                  ("Subnet"      . "10.89.2.4/29")
                  ("Gateway"     . "10.89.2.5")))))

(defun invidious-db-container-sections (data-mountpoint)
  "Cinix AST for invidious-db.container: postgres:16-alpine, ZFS-backed
   volume, health-checked via pg_isready."
  `(("Unit" . (("Description" . "Invidious PostgreSQL database")))
    ("Container" . (("Image"         . "oci.dapla.net/library/postgres:16-alpine")
                    ("ContainerName" . "invidious-db")
                    ("AutoUpdate"    . "registry")
                    ("EnvironmentFile" . "%S/invidious/db.env")
                    ("Volume"        . ,(format nil "~A:/var/lib/postgresql/data:Z"
                                                data-mountpoint))
                    ("Network"       . "invidious.network")
                    ("HealthCmd"     . "pg_isready -U invidious -d invidious")
                    ("HealthStartPeriod" . "10s")
                    ("HealthInterval"    . "30s")
                    ("HealthTimeout"     . "5s")
                    ("HealthRetries"     . "5")))
    ("Service" . (("Restart"          . "on-failure")
                  ("TimeoutStartSec"  . "120")
                  ("TimeoutStopSec"   . "30")))
    ("Install" . (("WantedBy" . "default.target")))))

(defun invidious-container-sections (config-path)
  "Cinix AST for invidious.container: binds to 127.0.0.1 only, mounts
   the generated config.yml read-only. The loopback port is the service
   account UID, per dapla.net convention."
      `(("Unit" . (("Description" . "Invidious YouTube frontend")
                 ("After"       . "network-online.target invidious-db.service")
                 ("Wants"       . "network-online.target")
                 ("Requires"    . "invidious-db.service")))
      ("Container" . (("Image"         . "oci.dapla.net/ghcr.io/iv-org/invidious:latest")
                      ("ContainerName" . "invidious")
                      ("AutoUpdate"    . "registry")
                      ("PublishPort"   . ,(format nil "127.0.0.1:~A:~A" port port))
                      ("Volume"        . ,(format nil "~A:/invidious/config/config.yml:ro,Z"
                                                  config-path))
                      ("Network"       . "invidious.network")
                      ("Label"         . "io.containers.autoupdate=registry")
                      ("Label"           . "org.cispec.application=watch-dapla-deploy")
                      ("Label"           . "org.cispec.managed-by=consfigurator")
                      ("Label"           . "org.cispec.fqdn=watch.dapla.net")
                      ("Label"           . "org.cispec.service-account=invidious")))
      ("Service" . (("Restart"         . "on-failure")
                    ("TimeoutStartSec" . "120")
                    ("TimeoutStopSec"  . "30")))
      ("Install" . (("WantedBy" . "default.target"))))))

(defun haproxy-vhost-config ()
  "HAProxy vhost configuration for watch.dapla.net.
   Backend uses the netavark bridge gateway IP 10.89.2.5 on the
   container's natural internal port. No loopback, no port arithmetic.

;;; dapla.net netavark service network allocation
;;; All subnets within 10.89.2.0/26 (64 addresses).
;;; Existing host networks: podman1=10.89.0.0/24, podman2=10.89.1.0/24.
;;;
;;; Service       Network     Subnet           Gateway      Prefix  Containers
;;; find          podman3     10.89.2.0/30     10.89.2.1    /30     1
;;; watch         podman4     10.89.2.4/29     10.89.2.5    /29     2
;;; meet          podman5     10.89.2.12/29    10.89.2.13   /29     3
;;; feed          podman6     10.89.2.20/30    10.89.2.21   /30     1
;;; save          podman7     10.89.2.24/30    10.89.2.25   /30     1
;;; burn          podman8     10.89.2.28/30    10.89.2.29   /30     1
;;; link          podman9     10.89.2.32/30    10.89.2.33   /30     1
;;; support       podman10    10.89.2.36/29    10.89.2.37   /29     4
  "
  (format nil
"frontend watch_http
  bind *:80
  acl host_watch hdr(host) -i watch.dapla.net
  redirect scheme https code 301 if host_watch

frontend watch_https
  bind *:443 ssl crt /etc/haproxy/certs/watch.dapla.net.pem alpn h2,http/1.1
  acl host_watch hdr(host) -i watch.dapla.net
  http-response set-header Strict-Transport-Security \"max-age=63072000; includeSubDomains; preload\"
  http-response set-header X-Content-Type-Options nosniff
  http-response set-header X-Frame-Options SAMEORIGIN
  http-response set-header Referrer-Policy strict-origin-when-cross-origin
  http-response set-header Permissions-Policy \"interest-cohort=()\""
  use_backend watch_be if host_watch

backend watch_be
  balance roundrobin
  option httpchk GET /
  http-check expect status 200
  timeout connect 5s
  timeout server  60s
  server invidious 10.89.2.5:3000 check inter 10s rise 2 fall 3
"))

(defprop haproxy-vhost-written :posix ()
  "Write the HAProxy vhost config for this service. Skipped when the
   service account does not yet exist, since the port cannot be determined.
   Reloads HAProxy only when content changes."
  (:desc (format nil "HAProxy vhost written for ~A" *haproxy-fqdn*))
  (:check nil)
  (:apply
        (unless port
       (consfigurator:inapplicable-property
        "Service account ~A does not exist; cannot determine port."
        *service-user*))
     (let* ((cfg-path (format nil "/etc/haproxy/conf.d/~A.cfg" *haproxy-vhost-name*))
            (new-content (haproxy-vhost-config))
            (current (when (probe-file cfg-path)
                       (uiop:read-file-string cfg-path))))
       (unless (equal new-content current)
         (containing-directory-exists cfg-path)
         (write-remote-file cfg-path new-content)
         (consfigurator.property.service:reloaded "haproxy"))))))

(defhost invidious-host (:deploy (:local))
  "The Invidious stack's host: two AES-256-GCM-encrypted ZFS datasets,
   the rootless service account and its linger, the generated DB secret,
   the Invidious config.yml, pulled images, the three quadlet units, and
   the HAProxy vhost, applied in dependency order."
  (zfs-encryption-key *home-dataset-keyfile*)
  (zfs-encryption-key *data-dataset-keyfile*)
  (zfs-dataset-mounted *home-dataset* *home-mountpoint* *home-dataset-keyfile*)
  (zfs-dataset-mounted *data-dataset* *data-mountpoint* *data-dataset-keyfile*)
  (rootless-service-account *service-user* *home-mountpoint*)
  (lingering-enabled *service-user*)
  (db-secret-file *secrets-path* *service-user*)
  (invidious-config *config-path* *service-user* *haproxy-fqdn* *secrets-path*)
  (images-pulled *service-user*
                  "oci.dapla.net/library/postgres:16-alpine"
                  "oci.dapla.net/ghcr.io/iv-org/invidious:latest")
  (quadlets-written *service-user* *home-mountpoint* *data-mountpoint* *config-path*)
  (quadlets-activated *service-user*)
  (haproxy-vhost-written))


(defprop decommissioned :posix (user)
  "Tear down the watch-dapla-deploy stack in least-destructive-first order.
   Steps:
     1. Stop all containers in the service account session.
     2. Remove the HAProxy vhost config and reload HAProxy.
     3. Terminate the service account login session.
     4. Disable linger so the account session does not restart.
     5. Delete the service account.
     6. Destroy all ZFS datasets (irreversible without a backup).
     7. Remove the ZFS encryption key files.
   Confirm a current rsync.net replica or snapshot exists before
   executing steps 6 and 7."
  (:desc (format nil "watch-dapla-deploy decommissioned for ~~A" user))
  (:apply
   (mrun (format nil "machinectl shell ~~A@ /usr/bin/systemctl --user stop --all" user))
   (mrun "rm" "-f" (format nil "/etc/haproxy/conf.d/~~A.cfg" *haproxy-vhost-name*))
   (mrun "systemctl" "reload" "haproxy")
   (mrun "loginctl" "terminate-user" user)
   (mrun "loginctl" "disable-linger" user)
   (mrun "userdel" user)
   (mrun "zfs" "destroy" "-r" 'storage/users/invidious')
   (mrun "zfs" "destroy" "-r" 'storage/containers/invidious')
   (mrun "rm" "-f" '/etc/zfs-keys/invidious-users.key')
   (mrun "rm" "-f" '/etc/zfs-keys/invidious-containers.key')))

(defun deploy-app ()
  "Provision the Invidious stack via INVIDIOUS-HOST (Consfigurator, :local
   connection). Aborts loudly if any property is skipped, rather than
   silently proceeding against a partially-provisioned host."
  (format t "~&--> Provisioning via Consfigurator (INVIDIOUS-HOST)...~%")
  (let ((provisioning-failed nil))
    (handler-bind ((consfigurator::skipped-properties
                     (lambda (c) (declare (ignore c))
                       (setf provisioning-failed t))))
      (invidious-host))
    (when provisioning-failed
      (error "INVIDIOUS-HOST provisioning reported failed properties ~
              (see the per-property report above). Refusing to proceed.")))
  (format t "~&--> Invidious stack provisioned. Visit https://~A~%" *haproxy-fqdn*))
