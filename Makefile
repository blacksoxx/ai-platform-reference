# ai-platform-reference
# Every target runs on a laptop unless it says otherwise. `make help` lists them.

SHELL := /bin/sh
.DEFAULT_GOAL := help

KIND_CLUSTER    ?= ai-platform-ci
KUBE_CONTEXT    ?= kind-$(KIND_CLUSTER)
PLATFORMS       ?= linux/amd64,linux/arm64
IMAGE_PREFIX    ?= ghcr.io/blacksoxx/ai-platform-reference
IMAGE_TAG       ?= dev
GPU_PROBE_IMAGE := $(IMAGE_PREFIX)/gpu-probe:$(IMAGE_TAG)

.PHONY: help lint test ci-up ci-down ci-status e2e demo lab-bootstrap image-gpu-probe test-gpu-probe

help: ## list targets
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-18s %s\n", $$1, $$2}'

lint: ## render every overlay, validate against schemas, lint YAML and Kyverno policies
	scripts/lint.sh

test: lint test-gpu-probe ## everything that runs without a cluster

ci-up: ## create the kind cluster, install Cilium and Argo CD, apply the root Application
	clusters/ci/bootstrap.sh

ci-down: ## delete the kind cluster
	kind delete cluster --name $(KIND_CLUSTER)

ci-status: ## sync and health of every Argo CD Application
	kubectl --context $(KUBE_CONTEXT) get applications.argoproj.io -n argocd

e2e: ## wait until every Application is Healthy, then run the proofs
	scripts/e2e.sh

demo: ## run the proofs in demo order against a running environment (docs/demo.md)
	scripts/demo.sh

lab-bootstrap: ## how to bootstrap the lab cluster, one role at a time (docs/setup-lab.md)
	@clusters/lab/bootstrap.sh || true

image-gpu-probe: ## build images/gpu-probe for arm64 and amd64 into the local image store
	docker buildx build --platform $(PLATFORMS) --load -t $(GPU_PROBE_IMAGE) images/gpu-probe

test-gpu-probe: image-gpu-probe ## run the probe under each platform and check the reported arch
	@set -e; for p in $$(echo $(PLATFORMS) | tr ',' ' '); do \
	  case $$p in linux/amd64) want=x86_64 ;; linux/arm64) want=aarch64 ;; *) want=unknown ;; esac; \
	  got=$$(docker run --rm --platform $$p $(GPU_PROBE_IMAGE) | awk '/^arch:/ {print $$2}'); \
	  if [ "$$got" = "$$want" ]; then echo "ok    $$p reports $$got"; \
	  else echo "FAIL  $$p reports '$$got', want $$want"; exit 1; fi; \
	done
