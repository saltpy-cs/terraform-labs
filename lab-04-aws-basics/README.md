# Lab 04 — AWS Provider Basics

> **COST WARNING:** This lab creates an EC2 instance (t3.nano, ~$0.0052/hr). The instance must be running for exercises 6–9. Run `terraform destroy` as soon as you have finished — do not leave it running overnight.

## Objectives

By the end of this lab you will be able to:

- Configure the AWS provider with a region and version constraints
- Build a complete VPC with subnet, internet gateway, and route table
- Create a security group with restricted inbound rules
- Launch an EC2 instance into a public subnet
- Explain and demonstrate implicit vs explicit resource dependencies
- Read `terraform plan` output: understand `+`, `~`, `-`, and `-/+` symbols
- Use a `data` source to look up the latest AMI rather than hardcoding an ID

---

## Concepts

### Provider configuration

The **provider** is the plugin that knows how to talk to a specific cloud API. Each provider is declared in the `required_providers` block and configured in a `provider` block:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

**Version constraints:**

| Constraint | Meaning |
|---|---|
| `~> 5.0` | `>= 5.0, < 6.0` — allows patch and minor updates within major version 5 |
| `~> 5.32` | `>= 5.32, < 5.33` — allows only patch updates |
| `>= 5.0, < 6.0` | Equivalent to `~> 5.0`, explicit form |
| `= 5.32.0` | Pin to an exact version |

The `~>` (pessimistic constraint) is the most common choice. It lets you receive bug fixes automatically while protecting against breaking changes in the next major version.

### AWS provider authentication chain

The AWS provider looks for credentials in this order:

1. **Environment variables**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`
2. **Shared credentials file**: `~/.aws/credentials` (populated by `aws configure`)
3. **Shared config file**: `~/.aws/config`
4. **EC2 instance metadata / ECS task role**: used when running on AWS infrastructure

Never hardcode credentials in `.tf` files. Use environment variables in CI/CD and instance profiles when running on AWS.

### Resource addresses

Every resource in Terraform has an **address** in the form `<type>.<name>`:

```
aws_vpc.main
aws_subnet.public
aws_instance.web
```

Inside a module the address includes the module path:
```
module.networking.aws_vpc.main
```

These addresses are what you use in `terraform state show`, `terraform import`, `terraform taint`, etc.

### Implicit dependencies — the dependency graph

Terraform builds a **directed acyclic graph (DAG)** of every resource. When resource B references an attribute of resource A, Terraform adds an edge B → A in the graph, meaning B cannot be created until A exists.

Example:

```hcl
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id    # <-- this reference creates a dependency
  cidr_block = "10.0.1.0/24"
}
```

Because `aws_subnet.public` references `aws_vpc.main.id`, Terraform knows to create the VPC first, then the subnet. This is an **implicit dependency** — it is inferred from the reference, no extra annotation required.

The dependency graph determines:
- **Creation order**: resources with no dependencies can be created in parallel
- **Destruction order**: reversed — dependents are destroyed before their dependencies

### Explicit dependencies — `depends_on`

Sometimes there is a real dependency that Terraform cannot infer because no attribute is referenced.

Classic example: an IAM role needs certain policies attached before an EC2 instance boots. The instance's HCL may not reference the policy directly (it references the role ARN), but the policy must exist for the instance to function correctly.

```hcl
resource "aws_instance" "web" {
  ami           = data.aws_ami.al2023.id
  instance_type = "t3.nano"
  iam_instance_profile = aws_iam_instance_profile.web.name

  # This ensures the S3 policy is attached before the instance boots,
  # even though the HCL doesn't reference the policy object directly.
  depends_on = [aws_iam_role_policy.s3_read]
}
```

`depends_on` accepts a list of resource references. Use it sparingly — if you find yourself using it often, it may mean your resource references aren't capturing the real dependencies.

### Reading `terraform plan` output

The plan prefixes each resource or attribute with a symbol:

| Symbol | Meaning |
|---|---|
| `+` | Will be **created** |
| `-` | Will be **destroyed** |
| `~` | Will be **updated in-place** (no replacement) |
| `-/+` | Will be **destroyed and recreated** — the attribute you changed forces replacement |
| `<=` | Will be **read** (data source) |

**In-place update (`~`):** The provider can modify the resource without deleting it. Example: adding a tag to an EC2 instance.

**Destroy and recreate (`-/+`):** The provider cannot change the attribute on a running resource — it must delete and recreate it. Example: changing an EC2 instance's AMI, changing a VPC's CIDR block. This is the most dangerous plan symbol — it causes downtime and data loss if the resource holds data.

The plan summary line tells you the total:

```
Plan: 3 to add, 1 to change, 0 to destroy.
```

Always read this line before typing `yes`.

### Data sources

A `data` block **reads** existing infrastructure rather than managing it. Data sources are declared with `data "<type>" "<name>"` and referenced as `data.<type>.<name>.<attribute>`.

```hcl
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "web" {
  ami = data.aws_ami.al2023.id   # reference the data source output
  ...
}
```

Data sources are evaluated during `terraform plan`. They do not create or modify anything — they only query.

Using a data source for AMIs means your config will always launch the latest Amazon Linux 2023 AMI without you having to manually update an AMI ID. This is safer than hardcoding (which eventually refers to a deprecated or deregistered AMI).

### Security groups — restrict by IP, not `0.0.0.0/0`

A common beginner mistake is to allow SSH from `0.0.0.0/0` (the whole internet). In this lab you will practice the correct pattern: restrict inbound SSH to your own IP address.

```hcl
resource "aws_security_group" "web" {
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]   # e.g. "1.2.3.4/32"
  }
}
```

To find your public IP:
```bash
curl -s ifconfig.me
```

Then set `my_ip_cidr = "YOUR_IP/32"` in `terraform.tfvars`. The `/32` means a single host address.

---

## Setup

### Prerequisites

- AWS CLI configured with credentials
- Terraform >= 1.5 installed
- Your public IP address (see below)

### Find your public IP

```bash
curl -s ifconfig.me
```

Note the result — you will need it in Exercise 1.

### Verify AWS access

```bash
aws sts get-caller-identity
```

---

## Exercises

### Exercise 1: Create `terraform.tfvars`

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Open `terraform.tfvars` and replace `YOUR_IP/32` with your actual public IP:

```hcl
my_ip_cidr = "1.2.3.4/32"   # replace 1.2.3.4 with output of: curl ifconfig.me
```

---

### Exercise 2: `terraform init` — download the provider

```bash
terraform init
```

Expected output:
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.x.x...
- Installed hashicorp/aws v5.x.x (signed by HashiCorp)

Terraform has been successfully initialized!
```

After init, a `.terraform/` directory appears containing the downloaded provider binary. A `.terraform.lock.hcl` file is created (or updated) — this is the **dependency lock file** and should be committed to version control. It pins the exact provider version used, so everyone on the team runs the same provider.

---

### Exercise 3: `terraform plan` — read the dependency order

```bash
terraform plan
```

Read the output carefully. Observe:
- The data source (`data.aws_ami.al2023`) is read first (symbol: `<=`)
- The VPC is created first among managed resources
- The subnet, IGW, and security group depend on the VPC
- The route table and its association depend on the subnet and IGW
- The EC2 instance is created last (depends on subnet, security group, and AMI data)

Terraform parallelises creation where the graph allows it. Resources with no dependency on each other can be created simultaneously.

The plan output ends with:
```
Plan: 8 to add, 0 to change, 0 to destroy.
```

Count the `+` blocks and verify this matches.

---

### Exercise 4: Break a dependency — observe the error

This exercise shows what happens when you sever an implicit dependency.

Open `terraform/main.tf` and temporarily change the subnet's `vpc_id` to a hardcoded fake value:

```hcl
resource "aws_subnet" "public" {
  vpc_id     = "vpc-00000000000000000"   # hardcoded fake — breaks the dependency
  cidr_block = "10.0.1.0/24"
  ...
}
```

Run the plan:

```bash
terraform plan
```

Terraform no longer infers a dependency between the subnet and the VPC. In the plan, it will try to create both simultaneously. If you applied, AWS would reject the subnet creation because the VPC ID doesn't exist.

Note also that Terraform may not even surface this as an error at plan time for all resource types — some validation only happens at apply time when the provider calls the AWS API.

**Fix it:** revert the `vpc_id` back to `aws_vpc.main.id`.

---

### Exercise 5: Apply — observe creation order

```bash
terraform apply
```

Review the plan one more time, then type `yes`.

Watch the creation output:

```
aws_vpc.main: Creating...
aws_vpc.main: Creation complete after 2s [id=vpc-0a1b2c3d]
aws_internet_gateway.main: Creating...
aws_subnet.public: Creating...
aws_security_group.web: Creating...
aws_internet_gateway.main: Creation complete after 1s [id=igw-0a1b2c3d]
aws_subnet.public: Creation complete after 1s [id=subnet-0a1b2c3d]
aws_security_group.web: Creation complete after 2s [id=sg-0a1b2c3d]
aws_route_table.public: Creating...
aws_route_table.public: Creation complete after 1s [id=rtb-0a1b2c3d]
aws_route_table_association.public: Creating...
aws_route_table_association.public: Creation complete after 0s [id=rtbassoc-0a1b2c3d]
aws_instance.web: Creating...
aws_instance.web: Still creating... [10s elapsed]
aws_instance.web: Creation complete after 35s [id=i-0a1b2c3d]

Apply complete! Resources: 8 added, 0 changed, 0 destroyed.

Outputs:

ami_id             = "ami-0xxxxxxxxxxxxxxxx"
instance_id        = "i-0xxxxxxxxxxxxxxxx"
instance_public_ip = "54.x.x.x"
vpc_id             = "vpc-0xxxxxxxxxxxxxxxx"
```

Notice the dependency order in the output: VPC → IGW and Subnet in parallel → Security Group → Route Table → Association → EC2 instance.

---

### Exercise 6: SSH into the instance

```bash
# Get the public IP from outputs
terraform output instance_public_ip
```

The EC2 instance uses Amazon Linux 2023. The default user is `ec2-user`. You need an SSH key pair — if you haven't already, create one:

```bash
# Create a key pair (if you don't have one)
aws ec2 create-key-pair \
  --key-name tf-lab04 \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/tf-lab04.pem

chmod 400 ~/.ssh/tf-lab04.pem
```

> **Note:** To use this key pair, add `key_name = "tf-lab04"` to the `aws_instance` resource block, then re-apply. The security group already allows SSH from your IP.

```bash
ssh -i ~/.ssh/tf-lab04.pem ec2-user@$(terraform output -raw instance_public_ip)
```

If the connection is refused, check:
1. Your `my_ip_cidr` value in `terraform.tfvars` matches your current IP (`curl ifconfig.me`)
2. The instance is in the `running` state: `aws ec2 describe-instances --instance-ids $(terraform output -raw instance_id) --query 'Reservations[].Instances[].State.Name' --output text`

---

### Exercise 7: In-place update (`~`) — add a tag to the VPC

Open `terraform/main.tf` and add a tag to `aws_vpc.main`:

```hcl
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true

  tags = {
    Name    = var.project_name
    Lab     = "lab-04"
    Updated = "true"           # add this line
  }
}
```

Run the plan:

```bash
terraform plan
```

Expected output (relevant section):
```
  ~ aws_vpc.main
    ~ tags     = {
        ...
      + "Updated" = "true"
      }

Plan: 0 to add, 1 to change, 0 to destroy.
```

The `~` means an in-place update — AWS can apply this change without destroying and recreating the VPC. No downtime, no data loss.

Apply it:

```bash
terraform apply
```

---

### Exercise 8: Destroy and recreate (`-/+`) — change the VPC CIDR

Now observe the most dangerous plan symbol: `-/+`.

Change the VPC CIDR block in `terraform/variables.tf`:

```hcl
variable "vpc_cidr" {
  default = "10.1.0.0/16"   # changed from 10.0.0.0/16
}
```

Run the plan:

```bash
terraform plan
```

Expected output (abbreviated):
```
-/+ aws_vpc.main (must be replaced)
    ~ cidr_block = "10.0.0.0/16" -> "10.1.0.0/16" # forces replacement

  # aws_subnet.public must be replaced
  -/+ aws_subnet.public (forces replacement)
  ...

  # aws_instance.web must be replaced
  -/+ aws_instance.web (forces replacement)
  ...

Plan: 6 to add, 0 to change, 6 to destroy.
```

Every resource that depends on the VPC must also be destroyed and recreated. The EC2 instance would be terminated. This is why `-/+` requires careful attention in production.

**Do not apply this change.** Revert `vpc_cidr` to `"10.0.0.0/16"` and verify the plan shows no changes:

```bash
terraform plan
# Should output: No changes. Your infrastructure matches the configuration.
```

---

### Exercise 9: Explicit `depends_on` — when it changes nothing

Add an explicit `depends_on` to the EC2 instance pointing to the internet gateway:

```hcl
resource "aws_instance" "web" {
  ...
  depends_on = [aws_internet_gateway.main]
}
```

Run the plan:

```bash
terraform plan
```

Expected output:
```
No changes. Your infrastructure matches the configuration.
```

Why no change? Because the EC2 instance already implicitly depends on the internet gateway — the subnet references the VPC, the route table references the IGW, and the association links them. The dependency was already in the graph. The explicit `depends_on` is redundant here — it documents intent but does not alter behaviour.

This demonstrates an important principle: `depends_on` only matters when there is a real dependency that resource references don't already capture. Adding it unnecessarily has no effect on the plan.

---

### Exercise 10: `terraform destroy` — observe reverse dependency order

```bash
terraform destroy
```

Review the destroy plan and type `yes`. Watch the destruction order in the output — it is the exact reverse of creation:

```
aws_instance.web: Destroying...
aws_instance.web: Destruction complete after 30s
aws_route_table_association.public: Destroying...
aws_security_group.web: Destroying...
aws_route_table_association.public: Destruction complete after 1s
aws_security_group.web: Destruction complete after 2s
aws_route_table.public: Destroying...
aws_route_table.public: Destruction complete after 1s
aws_internet_gateway.main: Destroying...
aws_subnet.public: Destroying...
aws_internet_gateway.main: Destruction complete after 1s
aws_subnet.public: Destruction complete after 1s
aws_vpc.main: Destroying...
aws_vpc.main: Destruction complete after 0s
```

The VPC is destroyed last because everything else depends on it. This is the dependency graph running in reverse — Terraform destroys dependents before their dependencies.

---

## Key Takeaways

- **Terraform builds a dependency graph** from resource references. Resources that reference each other are created in the correct order automatically — you do not specify the order yourself.
- **`depends_on`** is for real dependencies that aren't expressed by attribute references. Use it sparingly; overuse often indicates missing resource references.
- **`-/+` in the plan means destruction and recreation.** Changing certain attributes (VPC CIDR, AMI ID, instance type) forces replacement. Always read the full plan before applying.
- **Data sources (`data` blocks) read existing infrastructure** without creating or modifying anything. Use them for dynamic lookups (AMI IDs, availability zones, existing VPCs) rather than hardcoding values that change.
- **Always restrict security group ingress to specific IPs.** Using `0.0.0.0/0` for SSH is a common misconfiguration that exposes instances to the internet.
- **Provider version constraints** (`~> 5.0`) protect you from breaking changes in major provider releases. Commit `.terraform.lock.hcl` to version control.
