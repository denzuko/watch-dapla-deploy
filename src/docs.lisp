;;;; src/docs.lisp -- watch-dapla-deploy/docs

(defpackage :watch-dapla-deploy/docs
  (:use :cl)
  (:import-from :40ants-doc :defsection))

(in-package :watch-dapla-deploy/docs)

(defsection @watch-dapla-deploy (:title "watch-dapla-deploy")
  "Roswell/Consfigurator deploy of Invidious at watch.dapla.net."
  (@deploy-properties section)
  (@quadlet-builders section))


(defsection @network-allocation (:title "Network Allocation")
  "The watch.dapla.net service runs on netavark bridge network
   podman4 (10.89.2.4/29), gateway 10.89.2.5.

   Full dapla.net VLSM allocation within 10.89.2.0/26:

   | Service | Network  | Subnet          | Gateway      | Prefix | Containers |
   |---------|----------|-----------------|--------------|--------|------------|
   | find    | podman3  | 10.89.2.0/30    | 10.89.2.1   | /30    | 1          |
   | watch   | podman4  | 10.89.2.4/29    | 10.89.2.5   | /29    | 2          |
   | meet    | podman5  | 10.89.2.12/29   | 10.89.2.13  | /29    | 3          |
   | feed    | podman6  | 10.89.2.20/30   | 10.89.2.21  | /30    | 1          |
   | save    | podman7  | 10.89.2.24/30   | 10.89.2.25  | /30    | 1          |
   | burn    | podman8  | 10.89.2.28/30   | 10.89.2.29  | /30    | 1          |
   | link    | podman9  | 10.89.2.32/30   | 10.89.2.33  | /30    | 1          |
   | support | podman10 | 10.89.2.36/29   | 10.89.2.37  | /29    | 4          |

   Existing host networks: podman1=10.89.0.0/24, podman2=10.89.1.0/24.
   HAProxy backend points to the gateway IP on the container's natural
   internal port. No loopback binding, no port arithmetic.")

(defsection @deploy-properties (:title "Consfigurator Properties")
  (watch-dapla-deploy/deploy:zfs-encryption-key       function)
  (watch-dapla-deploy/deploy:zfs-dataset-mounted      function)
  (watch-dapla-deploy/deploy:rootless-service-account function)
  (watch-dapla-deploy/deploy:images-pulled            function)
  (watch-dapla-deploy/deploy:quadlets-written         function)
  (watch-dapla-deploy/deploy:haproxy-vhost-written    function)
  (watch-dapla-deploy/deploy:quadlets-activated       function)
  (watch-dapla-deploy/deploy:deploy-app               function))

(defsection @quadlet-builders (:title "Quadlet Unit Builders")
  (watch-dapla-deploy/deploy:cinix-write-string               function)
  (watch-dapla-deploy/deploy:service-account-uid              function)
  (watch-dapla-deploy/deploy:invidious-network-sections       function)
  (watch-dapla-deploy/deploy:invidious-db-container-sections  function)
  (watch-dapla-deploy/deploy:invidious-container-sections     function)
  (watch-dapla-deploy/deploy:haproxy-vhost-config             function))
