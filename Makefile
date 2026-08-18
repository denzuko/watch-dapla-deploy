TARGET    := watch-dapla-deploy
PREFIX    := usr/local
BUILDROOT := build/$(PREFIX)/bin
MANROOT   := build/$(PREFIX)/man/man1
REGISTRY  := oci.dapla.net/denzuko
VERSION   := $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)

# `test` runs the post-deploy WATCH-DAPLA-DEPLOY/E2E suite against a LIVE
# deploy -- it is not a build-time unit test, and has nothing to validate
# without a target host that is already deployed to. It is excluded from
# `all` for that reason; run it explicitly once something is deployed.
all: doc $(TARGET).tgz

$(BUILDROOT):
	@mkdir -p $@

$(MANROOT):
	@mkdir -p $@

$(BUILDROOT)/$(TARGET): $(TARGET).ros $(BUILDROOT)
	@ros dump executable $(TARGET).ros -o $@

build/$(TARGET).md: $(TARGET).ros docs.ros $(TARGET).asd src/deploy.lisp src/docs.lisp t/e2e.lisp
	@ros docs.ros

$(MANROOT)/$(TARGET).1: build/$(TARGET).md $(MANROOT)
	@pandoc -s -t man build/$(TARGET).md -o $@

$(TARGET).tgz: $(BUILDROOT)/$(TARGET)
	@tar zcvf $@ -C build $(shell echo "$(PREFIX)" | cut -d/ -f1)

install: $(TARGET).tgz
	@tar -C / -xzvf $<

test: $(TARGET).ros
	@./$< e2e

doc: $(MANROOT)/$(TARGET).1

## dist — sign and push binary artifact to OCI registry
dist: $(BUILDROOT)/$(TARGET)
	@echo "--> Computing digest..."
	sha256sum $(BUILDROOT)/$(TARGET) > $(TARGET).sha256
	@echo "--> Signing binary with cosign..."
	cosign sign-blob --yes \
	  --output-signature $(TARGET).sig \
	  --output-certificate $(TARGET).pem \
	  $(BUILDROOT)/$(TARGET)
	@echo "--> Pushing artifact to $(REGISTRY)/$(TARGET):$(VERSION) via ORAS..."
	oras push $(REGISTRY)/$(TARGET):$(VERSION) \
	  $(BUILDROOT)/$(TARGET):application/octet-stream \
	  $(TARGET).sha256:application/vnd.dapla.sha256 \
	  $(TARGET).sig:application/vnd.dev.cosign.simplesigning.v1+json \
	  $(TARGET).pem:application/vnd.dev.cosign.certificate.v1+pem
	@echo "--> Attaching SLSA provenance attestation..."
	cosign attest-blob --yes \
	  --predicate /dev/null \
	  --type slsaprovenance \
	  --bundle $(TARGET).bundle \
	  $(BUILDROOT)/$(TARGET)
	oras attach $(REGISTRY)/$(TARGET):$(VERSION) \
	  --artifact-type application/vnd.dev.cosign.bundle.v1 \
	  $(TARGET).bundle:application/vnd.dev.cosign.bundle.v1+json
	@echo "--> $(TARGET):$(VERSION) signed and pushed."

clean:
	@-rm -Rf build

distclean: clean
	@-rm -f $(TARGET).tgz $(TARGET).sha256 $(TARGET).sig $(TARGET).pem $(TARGET).bundle .*.swp
