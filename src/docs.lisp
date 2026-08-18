;;;; src/docs.lisp -- watch-dapla-deploy/docs
;;;;
;;;; 40ants-doc sections for the watch-dapla-deploy system.

(defpackage :watch-dapla-deploy/docs
  (:use :cl)
  (:import-from :40ants-doc :defsection))

(in-package :watch-dapla-deploy/docs)

(defsection @watch-dapla-deploy (:title "watch-dapla-deploy")
  "Roswell/Consfigurator deploy of Invidious at watch.dapla.net."
  (@deploy-properties section)
  (@quadlet-builders section))

(defsection @deploy-properties (:title "Consfigurator Properties")
  (watch-dapla-deploy/deploy:zfs-encryption-key        function)
  (watch-dapla-deploy/deploy:zfs-dataset-mounted       function)
  (watch-dapla-deploy/deploy:rootless-service-account  function)
  (watch-dapla-deploy/deploy:images-pulled             function)
  (watch-dapla-deploy/deploy:quadlets-activated        function)
  (watch-dapla-deploy/deploy:deploy-app                function))

(defsection @quadlet-builders (:title "Quadlet Unit Builders")
  (watch-dapla-deploy/deploy:cinix-write-string             function)
  (watch-dapla-deploy/deploy:invidious-network-sections     function)
  (watch-dapla-deploy/deploy:invidious-db-container-sections function)
  (watch-dapla-deploy/deploy:invidious-container-sections   function)
  (watch-dapla-deploy/deploy:haproxy-vhost-config           function))
