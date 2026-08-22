# The local twin of .github/workflows/ci.yml. Every check CI runs is a target here, and CI calls
# these targets rather than restating the commands — so "it passed locally" means the same thing.

# OpenTofu, with Terraform only as a fallback: this repo's floor is `>= 1.9` for OpenTofu and its
# `validation` blocks reference other variables, which not every Terraform version accepts.
TF ?= $(shell command -v tofu 2>/dev/null || command -v terraform 2>/dev/null)

# The root module and every module beside it. Each one is written to stand alone under
# `init -backend=false`, which is what makes validating them separately worth anything.
TF_DIRS := . $(wildcard modules/*/)

# Every chart in the repo, found rather than listed. `charts/` is excluded because that is where
# a dependency is unpacked, and a vendored upstream chart is not ours to lint.
CHARTS := $(shell find modules -name Chart.yaml -not -path '*/charts/*' -exec dirname {} \;)

# One provider download shared by every init run — the root and each module — instead of one each.
export TF_PLUGIN_CACHE_DIR ?= $(CURDIR)/.tofu-plugin-cache

OUT ?= .ci-out

# Advisory by default: a finding is reported and the run still passes. Flip to 1 here (and the
# workflow follows, it reads the same variable) once the baseline is clean.
TRIVY_EXIT ?= 0
TRIVY_ARGS ?=

.PHONY: help ci lint tofu-lint fmt fmt-check validate tflint helm helm-deps helm-lint helm-template trivy trivy-config trivy-fs clean check-tf

help: ## List the targets
	@grep -hE '^[a-z][a-z-]*:.*##' $(MAKEFILE_LIST) | sed -e 's/:[^#]*## /\t/' | expand -t 16

ci: lint trivy ## Everything the pipeline runs
lint: tofu-lint helm-lint ## Both lint halves, the two parallel CI jobs
tofu-lint: fmt-check validate tflint ## Formatting, module validation, tflint
helm: helm-lint helm-template ## Lint every chart and render it
trivy: trivy-config trivy-fs ## Misconfiguration scan of the rendered charts, secret scan of the tree

check-tf:
	@test -n "$(TF)" || { echo "neither tofu nor terraform is installed"; exit 1; }

fmt: check-tf ## Rewrite HCL to canonical form
	$(TF) fmt -recursive

fmt-check: check-tf ## Fail if any HCL is not canonically formatted
	$(TF) fmt -check -recursive

validate: check-tf ## init -backend=false && validate, for the root module and every module
	@mkdir -p "$(TF_PLUGIN_CACHE_DIR)"
	@set -e; for d in $(TF_DIRS); do \
		echo "==> $$d"; \
		$(TF) -chdir=$$d init -backend=false -input=false -no-color >/dev/null; \
		$(TF) -chdir=$$d validate -no-color; \
	done

# `--call-module-type=none` is not optional here. tflint evaluates every module call's arguments
# eagerly, with variables at their defaults — and a module call in this repo is `count = 0` when
# its variable is null, which is the default for `var.observability`. Without the flag it reads
# `local.observability.namespace` off a null and fails to build the configuration at all. The flag
# is passed here rather than in a .tflint.hcl because `--recursive` changes directory per module
# and a config file in the repository root is not found from inside one.
tflint: ## Lint HCL for unused declarations and deprecated syntax
	@if command -v tflint >/dev/null 2>&1; then tflint --recursive --call-module-type=none; \
	else echo "tflint is not installed - skipping (CI installs it)"; fi

helm-deps: ## Resolve chart dependencies, adding whatever repository a Chart.yaml names
	@set -e; for c in $(CHARTS); do \
		grep -hoE 'repository: *https?://[^ ]+' $$c/Chart.yaml 2>/dev/null \
		  | sed 's/repository: *//' | sort -u | while read -r r; do \
			helm repo add "$$(echo "$$r" | tr -cs 'a-zA-Z0-9' '-')" "$$r" --force-update >/dev/null; \
		done; \
		helm dependency build $$c >/dev/null; \
	done

helm-lint: helm-deps ## helm lint --strict, once per ci/ values file
	@set -e; for c in $(CHARTS); do \
		for v in $$c/ci/*.yaml; do \
			echo "==> $$c ($$(basename $$v))"; \
			helm lint --strict $$c -f $$v; \
		done; \
	done

helm-template: helm-deps ## Render every chart with every ci/ values file
	@set -e; rm -rf $(OUT); mkdir -p $(OUT); \
	for c in $(CHARTS); do n=$$(awk '$$1 == "name:" {print $$2; exit}' $$c/Chart.yaml); \
		for v in $$c/ci/*.yaml; do \
			helm template $$n $$c -n ci -f $$v \
			  | awk '/^---$$/{next} /^# Source: /{k = ($$3 !~ /\/charts\//); if (k) print "---"} k' \
			  > $(OUT)/$$n-$$(basename $$v .yaml).yaml; \
		done; \
	done; \
	echo "==> rendered into $(OUT)"

trivy-config: helm-template ## Scan the rendered manifests for misconfiguration
	trivy config $(OUT) --exit-code $(TRIVY_EXIT) $(TRIVY_ARGS)

trivy-fs: ## Scan the tree for committed secrets
	trivy fs . --scanners secret --skip-dirs $(OUT) --skip-dirs .terraform --skip-files '*.tfstate*' \
	  --exit-code $(TRIVY_EXIT) $(TRIVY_ARGS)

clean: ## Remove rendered manifests
	rm -rf $(OUT)
