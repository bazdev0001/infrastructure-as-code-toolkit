# Infrastructure as Code Toolkit — Makefile
# Run `make help` to see all available commands.

.DEFAULT_GOAL := help
SHELL         := /bin/bash
TF_VERSION    := 1.6.6
ENV           ?= dev

.PHONY: help
help: ## Show this help message
	@echo ""
	@echo "Infrastructure as Code Toolkit"
	@echo "================================"
	@echo ""
	@echo "Usage: make <target> [ENV=dev|staging|prod]"
	@echo ""
	@echo "Terraform:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -v '^help' | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-28s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Examples:"
	@echo "  make tf-plan ENV=dev"
	@echo "  make tf-apply ENV=prod"
	@echo "  make deploy APP=api-server VERSION=v1.2.3 ENV=prod"
	@echo ""

# ---------------------------------------------------------------------------
# Terraform targets
# ---------------------------------------------------------------------------

.PHONY: tf-init
tf-init: ## Initialize Terraform for ENV (default: dev)
	@echo "Initializing Terraform for environment: $(ENV)"
	cd terraform/environments/$(ENV) && terraform init

.PHONY: tf-validate
tf-validate: ## Validate Terraform configuration for ENV
	cd terraform/environments/$(ENV) && terraform validate

.PHONY: tf-fmt
tf-fmt: ## Format all Terraform files in place
	terraform fmt -recursive terraform/

.PHONY: tf-fmt-check
tf-fmt-check: ## Check Terraform formatting (no changes, CI-safe)
	terraform fmt -check -recursive terraform/

.PHONY: tf-plan
tf-plan: tf-init ## Plan Terraform changes for ENV
	@echo "Planning changes for environment: $(ENV)"
	cd terraform/environments/$(ENV) && terraform plan -out=tfplan

.PHONY: tf-apply
tf-apply: ## Apply Terraform changes for ENV (requires prior plan)
	@echo "Applying changes for environment: $(ENV)"
	@read -p "Are you sure you want to apply to $(ENV)? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	cd terraform/environments/$(ENV) && terraform apply tfplan

.PHONY: tf-destroy
tf-destroy: ## Destroy all resources for ENV (DANGEROUS)
	@echo "WARNING: This will destroy ALL resources in $(ENV)!"
	@read -p "Type the environment name to confirm: " confirm && [ "$$confirm" = "$(ENV)" ] || exit 1
	cd terraform/environments/$(ENV) && terraform destroy

.PHONY: tf-output
tf-output: ## Show Terraform outputs for ENV
	cd terraform/environments/$(ENV) && terraform output

.PHONY: tf-state-list
tf-state-list: ## List resources in Terraform state for ENV
	cd terraform/environments/$(ENV) && terraform state list

# ---------------------------------------------------------------------------
# Validation and linting
# ---------------------------------------------------------------------------

.PHONY: lint
lint: tf-fmt-check tflint ansible-lint ## Run all linters

.PHONY: tflint
tflint: ## Run TFLint on all modules
	@for module in terraform/modules/*/; do \
		echo "Linting $$module..."; \
		(cd $$module && tflint) || exit 1; \
	done

.PHONY: checkov
checkov: ## Run Checkov security scan on Terraform
	checkov -d terraform/ --framework terraform

.PHONY: ansible-lint
ansible-lint: ## Lint Ansible playbooks
	ansible-lint ansible/playbooks/

# ---------------------------------------------------------------------------
# Ansible targets
# ---------------------------------------------------------------------------

.PHONY: deploy
deploy: ## Deploy app: APP=name VERSION=tag ENV=env
	@[ -n "$(APP)" ]     || (echo "APP is required. Usage: make deploy APP=api-server VERSION=v1.2.3 ENV=dev"; exit 1)
	@[ -n "$(VERSION)" ] || (echo "VERSION is required"; exit 1)
	ansible-playbook ansible/playbooks/app-deploy.yml \
		-i ansible/inventory/$(ENV) \
		-e "app_name=$(APP) app_version=$(VERSION) env=$(ENV)"

.PHONY: deploy-dry-run
deploy-dry-run: ## Dry-run deploy: APP=name VERSION=tag ENV=env
	@[ -n "$(APP)" ]     || (echo "APP is required"; exit 1)
	@[ -n "$(VERSION)" ] || (echo "VERSION is required"; exit 1)
	ansible-playbook ansible/playbooks/app-deploy.yml \
		-i ansible/inventory/$(ENV) \
		-e "app_name=$(APP) app_version=$(VERSION) env=$(ENV) dry_run=yes"

.PHONY: node-setup
node-setup: ## Bootstrap k8s worker nodes for ENV
	@[ -n "$(JOIN_CMD)" ] || (echo "JOIN_CMD is required. Get it with: kubeadm token create --print-join-command"; exit 1)
	ansible-playbook ansible/playbooks/k8s-node-setup.yml \
		-i ansible/inventory/$(ENV) \
		-e "env=$(ENV) join_command='$(JOIN_CMD)'"

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

.PHONY: kubeconfig
kubeconfig: ## Update kubeconfig for EKS cluster in ENV
	$(eval CLUSTER_NAME := $(shell cd terraform/environments/$(ENV) && terraform output -raw cluster_name 2>/dev/null))
	$(eval REGION := $(shell cd terraform/environments/$(ENV) && terraform output -raw aws_region 2>/dev/null || echo "us-east-1"))
	@[ -n "$(CLUSTER_NAME)" ] || (echo "Could not get cluster name from Terraform output. Run tf-apply first."; exit 1)
	aws eks update-kubeconfig --region $(REGION) --name $(CLUSTER_NAME)
	@echo "kubeconfig updated for cluster: $(CLUSTER_NAME)"

.PHONY: docs
docs: ## Generate terraform-docs for all modules
	@command -v terraform-docs >/dev/null 2>&1 || (echo "terraform-docs not installed. Run: brew install terraform-docs"; exit 1)
	@for module in terraform/modules/*/; do \
		echo "Generating docs for $$module..."; \
		terraform-docs markdown table $$module > $$module/DOCS.md; \
	done

.PHONY: clean
clean: ## Remove local Terraform state and plan files (does not destroy AWS resources)
	find terraform/ -name "tfplan" -delete
	find terraform/ -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	find terraform/ -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	@echo "Cleaned local Terraform artifacts."

.PHONY: version
version: ## Show tool versions
	@echo "Terraform:    $$(terraform version -json | jq -r '.terraform_version' 2>/dev/null || terraform version | head -1)"
	@echo "Ansible:      $$(ansible --version | head -1)"
	@echo "AWS CLI:      $$(aws --version)"
	@echo "kubectl:      $$(kubectl version --client --short 2>/dev/null || echo 'not installed')"
