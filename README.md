# Infrastructure as Code Toolkit

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Terraform](https://img.shields.io/badge/Terraform-1.6+-purple.svg)](https://www.terraform.io/)
[![Ansible](https://img.shields.io/badge/Ansible-2.15+-red.svg)](https://www.ansible.com/)
[![CI](https://github.com/barry-au-yeung/infrastructure-as-code-toolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/barry-au-yeung/infrastructure-as-code-toolkit/actions/workflows/ci.yml)
[![AWS](https://img.shields.io/badge/AWS-EKS%20%7C%20RDS%20%7C%20VPC%20%7C%20S3-orange.svg)](https://aws.amazon.com/)

Terraform modules + Ansible playbooks for AWS — EKS, RDS, VPC, S3 with remote state and multi-environment support.

---

## Background / Why I Built This

We had 3 engineers manually clicking through the AWS console for every new environment. Every time the product team needed a staging environment for a new client, one of us would spend the better part of a week babysitting wizard screens, copying security group IDs between browser tabs, and hoping nobody forgot to enable encryption on the new RDS instance.

The worst part wasn't the time. It was the inconsistency. Dev looked different from staging. Staging looked different from prod. We chased bugs that only existed in one environment because someone had clicked a different checkbox six months ago and nobody remembered. We had a "runbook" that was a 47-step Google Doc, last updated 14 months prior, with three different people's handwriting in the comments.

I spent two weekends building the first version of this toolkit. By the end of the second weekend, we could provision a full environment — VPC, EKS cluster, RDS, S3 buckets, IAM roles, everything — in 45 minutes. That went from 3 days (when we were lucky) to 45 minutes. Reproducibly. With a full audit trail in git.

**What this toolkit gives you:**
- Opinionated but configurable Terraform modules for the AWS services we actually use in production
- Multi-environment support with shared module code and per-environment variable overrides
- Remote state in S3 with DynamoDB locking — no more "who has the state file" conversations
- Ansible playbooks for day-2 operations: app deploys, node bootstrapping, rolling updates
- A CI pipeline that validates, lints, and dry-runs every PR before it touches real infrastructure

**Scale this operates at:**
- 12+ AWS environments (dev, staging, prod, per-client sandbox)
- EKS clusters with 3-50 nodes depending on environment
- RDS Multi-AZ in prod, single-AZ in dev (cost-conscious)
- VPCs across 3 AWS regions

I'm a DevOps engineer with 12 years of experience and I've seen every flavor of "we'll do IaC later." This is what "doing it properly" looks like without being over-engineered.

---

## Architecture

```
infrastructure-as-code-toolkit/
├── terraform/
│   ├── modules/
│   │   ├── vpc/          # VPC, subnets, NAT, flow logs
│   │   ├── eks/          # EKS cluster, node groups, IRSA
│   │   └── rds/          # RDS, Multi-AZ, encryption, param groups
│   └── environments/
│       ├── dev/          # Small instances, single-AZ, relaxed policies
│       └── prod/         # HA, Multi-AZ, strict security
├── ansible/
│   └── playbooks/
│       ├── app-deploy.yml        # Rolling app deploys to EC2/k8s
│       └── k8s-node-setup.yml    # Bootstrap k8s worker nodes
└── .github/
    └── workflows/
        └── ci.yml               # Validate, lint, plan on PRs
```

### Network Layout (per environment)

```
VPC (10.x.0.0/16)
├── Public Subnets (one per AZ)
│   ├── 10.x.0.0/24  — us-east-1a
│   ├── 10.x.1.0/24  — us-east-1b
│   └── 10.x.2.0/24  — us-east-1c
│       └── NAT Gateways (one per AZ in prod, one total in dev)
├── Private App Subnets (one per AZ)
│   ├── 10.x.10.0/24 — EKS nodes, app tier
│   ├── 10.x.11.0/24
│   └── 10.x.12.0/24
└── Private Data Subnets (one per AZ)
    ├── 10.x.20.0/24 — RDS, ElastiCache
    ├── 10.x.21.0/24
    └── 10.x.22.0/24
```

### Module Dependency Order

```
vpc  ──►  eks  ──►  (app workloads)
  └────►  rds  ──►  (app workloads)
```

Remote state is stored in S3 (`s3://your-org-tf-state/<env>/terraform.tfstate`) with DynamoDB locking (`your-org-tf-locks`). Each environment is an independent Terraform root module that references shared modules.

---

## Quick Start

### Prerequisites

```bash
# Required tools
terraform >= 1.6
ansible >= 2.15
aws-cli >= 2.0
kubectl >= 1.28
helm >= 3.12

# Install via brew (macOS/Linux)
brew install terraform ansible awscli kubectl helm

# Verify
terraform version
ansible --version
aws --version
```

### 1. Bootstrap Remote State (one-time per AWS account)

```bash
# Create the S3 bucket and DynamoDB table for remote state
aws s3api create-bucket \
  --bucket your-org-tf-state \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket your-org-tf-state \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket your-org-tf-state \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

aws dynamodb create-table \
  --table-name your-org-tf-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### 2. Configure AWS Credentials

```bash
export AWS_PROFILE=your-profile
# or
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=us-east-1
```

### 3. Deploy Dev Environment

```bash
cd terraform/environments/dev

# Copy and edit the tfvars
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars

# Initialize (downloads providers, configures remote state)
terraform init

# Preview changes
terraform plan -out=tfplan

# Apply
terraform apply tfplan
```

### 4. Configure kubectl for EKS

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name $(terraform output -raw cluster_name)

kubectl get nodes
```

### 5. Run an Ansible Playbook

```bash
cd ansible

# Install dependencies
pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml

# Deploy app (rolling update)
ansible-playbook playbooks/app-deploy.yml \
  -i inventory/dev \
  -e "app_version=v1.2.3 env=dev"
```

---

## Usage Examples

### Example 1: Provision a New Dev Environment

```bash
cd terraform/environments/dev
terraform init
terraform apply -var="cluster_name=dev-us-east-1" -var="environment=dev"
```

Expected runtime: 15-20 minutes (EKS control plane takes the longest).

### Example 2: Use the VPC Module Standalone

```hcl
module "vpc" {
  source = "../../modules/vpc"

  name             = "my-vpc"
  environment      = "staging"
  vpc_cidr         = "10.20.0.0/16"
  azs              = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets  = ["10.20.10.0/24", "10.20.11.0/24", "10.20.12.0/24"]
  public_subnets   = ["10.20.0.0/24", "10.20.1.0/24", "10.20.2.0/24"]
  database_subnets = ["10.20.20.0/24", "10.20.21.0/24", "10.20.22.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = true   # false in prod for HA
  enable_vpc_flow_logs   = true

  tags = {
    Team    = "platform"
    CostCenter = "infra"
  }
}
```

### Example 3: EKS with Custom Node Groups

```hcl
module "eks" {
  source = "../../modules/eks"

  cluster_name    = "my-cluster"
  cluster_version = "1.29"
  environment     = "prod"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  node_groups = {
    general = {
      instance_types = ["m5.xlarge"]
      min_size       = 3
      max_size       = 10
      desired_size   = 3
      disk_size      = 50
    }
    gpu = {
      instance_types = ["g4dn.xlarge"]
      min_size       = 0
      max_size       = 5
      desired_size   = 0
      disk_size      = 100
      labels = {
        "workload-type" = "gpu"
      }
      taints = [{
        key    = "nvidia.com/gpu"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]
    }
  }

  enable_irsa = true
}
```

### Example 4: RDS with Encrypted Multi-AZ

```hcl
module "rds" {
  source = "../../modules/rds"

  identifier        = "my-app-prod"
  engine            = "postgres"
  engine_version    = "15.4"
  instance_class    = "db.r6g.xlarge"
  allocated_storage = 100
  environment       = "prod"

  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.database_subnets
  allowed_cidr_blocks = module.vpc.private_subnets_cidr_blocks

  multi_az            = true
  storage_encrypted   = true
  deletion_protection = true

  backup_retention_period = 30
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  parameters = [
    { name = "log_connections",         value = "1" },
    { name = "log_disconnections",      value = "1" },
    { name = "log_min_duration_statement", value = "1000" }
  ]
}
```

### Example 5: Rolling App Deploy with Ansible

```bash
# Deploy a specific version with zero downtime
ansible-playbook ansible/playbooks/app-deploy.yml \
  -i ansible/inventory/prod \
  -e "app_name=api-server" \
  -e "app_version=v2.4.1" \
  -e "deploy_strategy=rolling" \
  -e "max_unavailable=1" \
  --check   # dry-run first

# Then apply for real
ansible-playbook ansible/playbooks/app-deploy.yml \
  -i ansible/inventory/prod \
  -e "app_name=api-server" \
  -e "app_version=v2.4.1" \
  -e "deploy_strategy=rolling"
```

---

## Configuration

### Terraform Environment Variables

| Variable | Description | Default | Required |
|---|---|---|---|
| `AWS_PROFILE` | AWS credentials profile | — | Yes (or key/secret) |
| `AWS_DEFAULT_REGION` | Target AWS region | `us-east-1` | No |
| `TF_VAR_environment` | Environment name (`dev`, `staging`, `prod`) | — | Yes |

### Key Terraform Input Variables (per module)

#### VPC Module

| Variable | Type | Description | Default |
|---|---|---|---|
| `name` | string | VPC name prefix | — |
| `vpc_cidr` | string | VPC CIDR block | `"10.0.0.0/16"` |
| `azs` | list(string) | Availability zones | — |
| `private_subnets` | list(string) | Private subnet CIDRs | — |
| `public_subnets` | list(string) | Public subnet CIDRs | — |
| `database_subnets` | list(string) | Database subnet CIDRs | `[]` |
| `enable_nat_gateway` | bool | Create NAT gateways | `true` |
| `single_nat_gateway` | bool | One NAT for all AZs (cost saving) | `false` |
| `enable_vpc_flow_logs` | bool | Enable VPC Flow Logs to CloudWatch | `true` |

#### EKS Module

| Variable | Type | Description | Default |
|---|---|---|---|
| `cluster_name` | string | EKS cluster name | — |
| `cluster_version` | string | Kubernetes version | `"1.29"` |
| `vpc_id` | string | VPC ID | — |
| `subnet_ids` | list(string) | Subnets for nodes | — |
| `node_groups` | map(object) | Node group configs | see vars file |
| `enable_irsa` | bool | Enable IAM Roles for Service Accounts | `true` |
| `cluster_addons` | map(object) | EKS managed add-ons | see vars file |
| `cluster_endpoint_public_access` | bool | Public API server endpoint | `true` |
| `cluster_endpoint_public_access_cidrs` | list(string) | CIDR whitelist for API server | `["0.0.0.0/0"]` |

#### RDS Module

| Variable | Type | Description | Default |
|---|---|---|---|
| `identifier` | string | RDS instance identifier | — |
| `engine` | string | DB engine (`postgres`, `mysql`) | `"postgres"` |
| `engine_version` | string | DB engine version | `"15.4"` |
| `instance_class` | string | RDS instance class | `"db.t3.medium"` |
| `allocated_storage` | number | Storage in GB | `20` |
| `multi_az` | bool | Enable Multi-AZ | `false` |
| `storage_encrypted` | bool | Encrypt storage | `true` |
| `deletion_protection` | bool | Prevent accidental deletion | `false` |
| `backup_retention_period` | number | Days to retain backups | `7` |

### Ansible Variables

| Variable | Description | Example |
|---|---|---|
| `app_name` | Application name | `api-server` |
| `app_version` | Version tag to deploy | `v2.4.1` |
| `env` | Environment | `dev`, `prod` |
| `deploy_strategy` | Rolling or blue/green | `rolling` |
| `max_unavailable` | Nodes unavailable during roll | `1` |
| `ecr_registry` | ECR registry URL | `123456789.dkr.ecr.us-east-1.amazonaws.com` |

---

## What I Would Do Differently

After running this in production for two years, here's what I'd change if I were starting fresh:

**1. Terragrunt from day one.**
I added Terragrunt at v2 of this toolkit. It eliminates the boilerplate in environment `main.tf` files — each environment becomes a thin config file instead of copy-pasted module calls. The DRY improvement is significant once you have more than 3 environments.

**2. Separate state per module, not per environment.**
Having one state file per environment gets unwieldy. I'd split it: `vpc/terraform.tfstate`, `eks/terraform.tfstate`, `rds/terraform.tfstate`. Smaller blast radius, faster plans, easier debugging.

**3. Policy-as-code from the beginning.**
OPA/Conftest should be in the CI pipeline from the first commit, not bolted on later. Retroactively adding policy checks to existing resources is painful. Start with `terraform-compliance` or Checkov and keep the rules simple early on.

**4. Tag everything from the start.**
I got lazy about tags in the early modules. Then someone asked "how much does the analytics environment cost?" and I had no good answer. Every resource should have at minimum: `Environment`, `Team`, `CostCenter`, `ManagedBy=terraform`.

**5. Pin provider versions tighter.**
`~> 5.0` for the AWS provider is not tight enough. `= 5.31.0` and bump intentionally. Provider upgrades have broken plans in ways that were hard to debug because we'd also upgraded Terraform itself in the same week.

**6. Use data sources instead of hardcoding AMI IDs.**
I have `ami-0abcdef...` strings in a few old playbooks. They rot. Use `aws_ami` data sources with filters and let Terraform find the current AMI at plan time.

---

## Contributing

This is a personal toolkit but PRs are welcome for:
- Bug fixes
- Additional Terraform modules (ElastiCache, SQS, CloudFront)
- Ansible roles for new services
- Documentation improvements

**Workflow:**
1. Fork the repo
2. Create a feature branch (`git checkout -b feat/add-elasticache-module`)
3. Run `make lint` and `make validate` — both must pass
4. Open a PR with a description of what changed and why

**Code standards:**
- All Terraform modules must have `variables.tf`, `outputs.tf`, and a working example in the README
- Variables must have descriptions and types
- No hardcoded AWS account IDs or region strings in modules (pass them in)
- Ansible tasks must have `name:` set
- Use `no_log: true` on any task that handles credentials

---

## License

MIT License. See [LICENSE](LICENSE) for details.

Built by Barry Au Yeung — 12 years of watching people click through the AWS console so you don't have to.







