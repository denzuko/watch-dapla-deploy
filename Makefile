BINARY   := watch-dapla-deploy
REGISTRY := oci.dapla.net/denzuko
VERSION  := $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)

.PHONY: build test doc dist clean

## build — compile a static binary via ros dump executable
build:
	ros dump executable $(BINARY) --output $(BINARY)

## test — run the e2e suite against a live deployment
test:
	./$(BINARY).ros e2e

## doc — generate HTML documentation via docs.ros
doc:
	ros docs.ros

## dist — sign binary with cosign and push artifact to OCI registry via ORAS
dist: build
	@echo "--> Computing digest..."
	sha256sum $(BINARY) > $(BINARY).sha256
	@echo "--> Signing binary with cosign..."
	cosign sign-blob --yes \
	  --output-signature $(BINARY).sig \
	  --output-certificate $(BINARY).pem \
	  $(BINARY)
	@echo "--> Pushing artifact to $(REGISTRY)/$(BINARY):$(VERSION) via ORAS..."
	oras push $(REGISTRY)/$(BINARY):$(VERSION) \
	  $(BINARY):application/octet-stream \
	  $(BINARY).sha256:application/vnd.dapla.sha256 \
	  $(BINARY).sig:application/vnd.dev.cosign.simplesigning.v1+json \
	  $(BINARY).pem:application/vnd.dev.cosign.certificate.v1+pem
	@echo "--> Attaching SLSA provenance attestation..."
	cosign attest-blob --yes \
	  --predicate /dev/null \
	  --type slsaprovenance \
	  --bundle $(BINARY).bundle \
	  $(BINARY)
	oras attach $(REGISTRY)/$(BINARY):$(VERSION) \
	  --artifact-type application/vnd.dev.cosign.bundle.v1 \
	  $(BINARY).bundle:application/vnd.dev.cosign.bundle.v1+json
	@echo "--> $(BINARY):$(VERSION) signed and pushed."

## clean — remove build artifacts
clean:
	rm -f $(BINARY) $(BINARY).sha256 $(BINARY).sig $(BINARY).pem $(BINARY).bundle $(BINARY).tar.gz
