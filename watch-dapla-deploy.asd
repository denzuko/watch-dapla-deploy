;;;; watch-dapla-deploy.asd
;;;;
;;;; :WATCH-DAPLA-DEPLOY is the umbrella namespace. :WATCH-DAPLA-DEPLOY/DEPLOY
;;;; is the Consfigurator provisioning system; :WATCH-DAPLA-DEPLOY/DOCS and
;;;; :WATCH-DAPLA-DEPLOY/E2E are separate subsystems so documentation and
;;;; test dependencies are never pulled into a production load.
;;;;
;;;; :WATCH-DAPLA-DEPLOY itself has no components; ASDF's slash-named
;;;; subsystem convention requires this root system to exist so every
;;;; :WATCH-DAPLA-DEPLOY/<x> system can resolve against its .asd file.

(asdf:defsystem :watch-dapla-deploy)

(asdf:defsystem :watch-dapla-deploy/deploy
  :description "Roswell/Consfigurator deploy of Invidious on rootless Podman
quadlets behind HAProxy at watch.dapla.net."
  :license "BSD-3-Clause"
  :depends-on (:cl-inix :consfigurator)
  :components ((:file "src/deploy"))
  :in-order-to ((asdf:test-op (asdf:test-op :watch-dapla-deploy/e2e))))

(asdf:defsystem :watch-dapla-deploy/docs
  :depends-on (:watch-dapla-deploy/deploy :40ants-doc :40ants-doc-full)
  :components ((:file "src/docs")))

(asdf:defsystem :watch-dapla-deploy/e2e
  :depends-on (:watch-dapla-deploy/deploy :fiveam :dexador)
  :components ((:file "t/e2e"))
  :perform (asdf:test-op (op c)
             (uiop:symbol-call :fiveam :run! :watch-dapla-deploy-e2e)))

(asdf:defsystem :watch-dapla-deploy/spec
  :description "FiveAM specification tests for the quadlet specifier refactor."
  :depends-on (:watch-dapla-deploy/deploy :fiveam)
  :components ((:file "t/spec"))
  :perform (asdf:test-op (op c)
             (uiop:symbol-call :watch-dapla-deploy/spec :run-spec)))
