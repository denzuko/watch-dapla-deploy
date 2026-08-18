.PHONY: build test doc dist clean

## build — compile a static binary via ros dump executable
build:
	ros dump executable watch-dapla-deploy --output watch-dapla-deploy

## test — run the e2e suite against a live deployment
test:
	./watch-dapla-deploy.ros e2e

## doc — generate HTML documentation via docs.ros
doc:
	ros docs.ros

## dist — package the binary for distribution
dist: build
	tar czf watch-dapla-deploy.tar.gz watch-dapla-deploy

## clean — remove build artifacts
clean:
	rm -f watch-dapla-deploy watch-dapla-deploy.tar.gz
