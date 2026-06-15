# Terraform Certification Practice Test — Questions

**Time allowed:** 90 minutes  
**Total points:** 100  
**Pass mark:** 70

Start the timer only after the setup in `practice-test/setup/` has been applied successfully.

All working directories are under `~/tf-practice/`. Create each directory as needed.

---

## Question 1 — Local File Resource (8 points) — Associate

**Objective:** Demonstrate basic provider configuration and the core Terraform workflow.

In `~/tf-practice/q01/`, write a Terraform configuration that:
1. Declares the `hashicorp/local` provider (version `>= 2.0`).
2. Creates a `local_file` resource named `practice` that writes the string `Terraform Associate` to the path `/tmp/tf-practice.txt`.
3. Runs `terraform init` and `terraform apply -auto-approve` successfully.

**Verification:**
```bash
cat /tmp/tf-practice.txt
```
Expected output: `Terraform Associate`

---

## Question 2 — Variables, Validation, and count (8 points) — Associate

**Objective:** Demonstrate variable declarations with validation and use of the `count` meta-argument.

In `~/tf-practice/q02/`, write:

**`variables.tf`** defining:
- A `string` variable named `environment` with no default; add a validation rule that rejects any value not in `["dev", "staging", "prod"]` (use a clear error message).
- A `number` variable named `replica_count` with a default of `2`; add a validation rule that requires the value to be between `1` and `10` inclusive.

**`main.tf`** that:
- Declares the `hashicorp/null` provider.
- Creates `var.replica_count` `null_resource` resources named such that each has a unique name in the format `app-<environment>-<index>` (use the `count` index). Set a trigger on each with `name = "app-${var.environment}-${count.index}"`.

Apply with `environment=dev` (pass via `-var` or a `terraform.tfvars` file).

**Verification:**
```bash
cd ~/tf-practice/q02
terraform state list
```
Expected output (two lines, order may vary):
```
null_resource.app[0]
null_resource.app[1]
```

---

## Question 3 — Remote S3 Backend (8 points) — Associate

**Objective:** Configure a remote state backend using S3.

The name of the pre-provisioned S3 bucket is in `/tmp/practice-bucket-name.txt`.

In `~/tf-practice/q03/`, write a Terraform configuration that:
1. Configures an `s3` backend using the bucket whose name is in `/tmp/practice-bucket-name.txt`, with key `practice/q03.tfstate` and region `us-east-1`.
2. Declares the `hashicorp/null` provider and at least one `null_resource`.
3. Runs `terraform init` (you will need to confirm the backend migration if any local state exists) and `terraform apply -auto-approve` successfully.

**Verification:**
```bash
BUCKET=$(cat /tmp/practice-bucket-name.txt)
aws s3 ls "s3://${BUCKET}/practice/"
```
Expected: a line showing `q03.tfstate`.

---

## Question 4 — Data Source and Output (8 points) — Associate

**Objective:** Use a data source to look up existing infrastructure and expose its attributes as an output.

The ID of the pre-provisioned VPC is in `/tmp/practice-vpc-id.txt`.

In `~/tf-practice/q04/`, write a Terraform configuration that:
1. Declares the `hashicorp/aws` provider for region `us-east-1`.
2. Uses a `data "aws_vpc"` data source that looks up the VPC by filtering on its ID (use the value from `/tmp/practice-vpc-id.txt` — you may hard-code it or read it with `file()`).
3. Declares an output named `vpc_cidr` whose value is the CIDR block of the looked-up VPC.

**Verification:**
```bash
cd ~/tf-practice/q04
terraform output vpc_cidr
```
Expected: a valid CIDR block string (e.g., `"172.31.0.0/16"`).

---

## Question 5 — Writing and Calling a Module (10 points) — Associate+

**Objective:** Author a reusable child module and call it from a root configuration.

Write a module at `~/tf-practice/q05/modules/tagger/` that:
- Accepts three input variables: `resource_name` (string), `environment` (string), `team` (string).
- Outputs a value named `tags` that is a `map(string)` containing at minimum:
  - `Name` = `var.resource_name`
  - `Environment` = `var.environment`
  - `Team` = `var.team`
  - `ManagedBy` = `"Terraform"`

In the root configuration at `~/tf-practice/q05/`:
- Declare the `hashicorp/null` provider.
- Call the `tagger` module with `resource_name = "web-server"`, `environment = "prod"`, `team = "platform"`.
- Create a `null_resource` named `example` with a `triggers` block that includes all entries from the module's `tags` output (use the spread-into-triggers pattern).
- Declare an output named `tags` whose value is the module's `tags` output.

**Verification:**
```bash
cd ~/tf-practice/q05
terraform output tags
```
Expected: a map containing at minimum `Name`, `Environment`, `Team`, and `ManagedBy` keys.

---

## Question 6 — for_each with a Map of Objects (10 points) — Associate+

**Objective:** Use `for_each` to create multiple resources from a map variable.

In `~/tf-practice/q06/`:

Write a `variables.tf` that declares a variable named `servers` of type:
```hcl
map(object({
  instance_type = string
  port          = number
}))
```
with a default of:
```hcl
{
  web = { instance_type = "t3.micro", port = 80 }
  api = { instance_type = "t3.small", port = 8080 }
  db  = { instance_type = "t3.medium", port = 5432 }
}
```

Write a `main.tf` that:
- Declares the `hashicorp/null` provider.
- Creates `null_resource` resources using `for_each` over `var.servers`. Name the resource block `server`. Each resource should have a `triggers` block with `instance_type` and `port` from the map values.

**Verification:**
```bash
cd ~/tf-practice/q06
terraform state list
```
Expected (three lines, order may vary):
```
null_resource.server["api"]
null_resource.server["db"]
null_resource.server["web"]
```

---

## Question 7 — templatefile() Function (10 points) — Associate+

**Objective:** Use the `templatefile()` built-in function to render a template.

The file `~/tf-practice/q07/template.txt.tpl` already exists with the following content:
```
Hello, ${name}! You are in ${region}.
```

In `~/tf-practice/q07/`, write a Terraform configuration that:
1. Declares the `hashicorp/aws` provider for region `us-east-1`.
2. Uses `data "aws_region" "current" {}` to retrieve the current AWS region.
3. In a `locals` block, uses `templatefile()` to render `template.txt.tpl` with:
   - `name = "Terraform"`
   - `region = data.aws_region.current.name`
4. Declares an output named `rendered` whose value is the rendered string from locals.

**Verification:**
```bash
cd ~/tf-practice/q07
terraform output rendered
```
Expected: `"Hello, Terraform! You are in us-east-1."`

---

## Question 8 — for Expression Transforming a List (10 points) — Associate+

**Objective:** Use a `for` expression to transform one collection type into another.

In `~/tf-practice/q08/`:

Write a configuration that:
1. Declares the `hashicorp/null` provider.
2. Defines a variable named `allowed_cidrs` of type `list(string)` with a default of `["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]`.
3. In a `locals` block, uses a `for` expression to transform `var.allowed_cidrs` into a `list(object({ cidr = string, description = string }))` where `description = "Allow from ${cidr}"` for each entry.
4. Declares an output named `cidr_objects` whose value is the transformed list from locals.

**Verification:**
```bash
cd ~/tf-practice/q08
terraform output cidr_objects
```
Expected: a list of three objects. Each object must have a `cidr` and a `description` field where `description` equals `"Allow from <cidr>"`.

---

## Question 9 — terraform import (10 points) — Associate+

**Objective:** Bring an existing resource under Terraform management using `terraform import`.

The name of a pre-existing S3 bucket is in `/tmp/practice-import-bucket.txt`.

In `~/tf-practice/q09/`:
1. Declare the `hashicorp/aws` provider for region `us-east-1`.
2. Write a `resource "aws_s3_bucket" "imported"` block. At minimum it must contain a `bucket` argument set to the bucket name from `/tmp/practice-import-bucket.txt`. (Do not set arguments that would conflict with the existing bucket's configuration — keep the block minimal.)
3. Run `terraform init`.
4. Run `terraform import aws_s3_bucket.imported <bucket-name>` using the name from the file.
5. Run `terraform plan` — it should show no changes needed (or only ignorable drift). If there are conflicting attributes, adjust the resource block to match.

**Verification:**
```bash
cd ~/tf-practice/q09
terraform state show aws_s3_bucket.imported
```
Expected: output showing the bucket's attributes (ARN, bucket name, region, etc.).

---

## Question 10 — Workspaces (6 points) — Professional

**Objective:** Create and manage multiple Terraform workspaces with isolated state.

In `~/tf-practice/q10/`:
1. Write a configuration that declares the `hashicorp/null` provider and creates a single `null_resource` named `env_marker` with a trigger `env = terraform.workspace`.
2. Create three workspaces named `dev`, `staging`, and `prod`.
3. Switch to each workspace in turn and run `terraform apply -auto-approve` so that each workspace has its own state file.
4. Verify that each workspace has an independent state (the resource in `dev` is not visible when you are in `staging`, etc.).

**Verification:**
```bash
cd ~/tf-practice/q10
terraform workspace list
```
Expected: all three workspaces listed (plus `default`).

Then verify isolation:
```bash
terraform workspace select dev && terraform state list
terraform workspace select staging && terraform state list
terraform workspace select prod && terraform state list
```
Each should show `null_resource.env_marker` in its own state.

---

## Question 11 — terraform test (6 points) — Professional

**Objective:** Write a `terraform test` file that validates a module using a mock provider.

Write a module at `~/tf-practice/q11/modules/namer/` that:
- Accepts two input variables: `prefix` (string) and `suffix` (string).
- Outputs a value named `full_name` whose value is `"${var.prefix}-${var.suffix}"`.
- Requires no provider (use `terraform { required_providers {} }` or omit the block entirely).

Write a test file at `~/tf-practice/q11/tests/validate.tftest.hcl` that:
- Uses a `mock_provider` block for `null` (even if the module needs no provider, declare one to demonstrate the syntax — or omit if the module truly needs none).
- Contains a `run` block named `"name_is_correct"` that:
  - Calls the namer module (set `module` in the run block, or use `command = plan` against a root config).
  - Passes `prefix = "app"` and `suffix = "prod"` as input variables.
  - Asserts that `output.full_name == "app-prod"`.

From `~/tf-practice/q11/`, run:
```bash
terraform init
terraform test
```

**Verification:**
```bash
cd ~/tf-practice/q11
terraform test
```
Expected: `1 passed, 0 failed.`

---

## Question 12 — Complex for Expression (6 points) — Professional

**Objective:** Use a `for` expression to produce formatted strings from a map of objects.

In `~/tf-practice/q12/`:

Write a configuration that:
1. Declares the `hashicorp/null` provider.
2. Defines a variable named `instances` of type `map(object({ ip = string, port = number }))` with a default of:
```hcl
{
  web = { ip = "10.0.1.5", port = 80 }
  api = { ip = "10.0.2.5", port = 8080 }
}
```
3. In a `locals` block, uses a `for` expression over `var.instances` to produce a `list(string)` where each string has the format `"<name>: <ip>:<port>"`.
4. Declares an output named `connection_strings` whose value is the list from locals.

**Verification:**
```bash
cd ~/tf-practice/q12
terraform output connection_strings
```
Expected (order may vary):
```
tolist([
  "api: 10.0.2.5:8080",
  "web: 10.0.1.5:80",
])
```

---

## Scoring Checklist

| # | Question | Points | Complete? |
|---|----------|--------|-----------|
| 1 | Local file resource | 8 | [ ] |
| 2 | Variables, validation, count | 8 | [ ] |
| 3 | Remote S3 backend | 8 | [ ] |
| 4 | Data source and output | 8 | [ ] |
| 5 | Writing and calling a module | 10 | [ ] |
| 6 | for_each with map of objects | 10 | [ ] |
| 7 | templatefile() function | 10 | [ ] |
| 8 | for expression (list transform) | 10 | [ ] |
| 9 | terraform import | 10 | [ ] |
| 10 | Workspaces | 6 | [ ] |
| 11 | terraform test | 6 | [ ] |
| 12 | Complex for expression | 6 | [ ] |
| | **Total** | **100** | |

---

## Solutions

> Read the solutions only after you have completed and scored the test, or when you are
> using this as a study guide. Looking at solutions during the test defeats its purpose.

---

### Solution — Q1: Local File Resource

**`~/tf-practice/q01/main.tf`**
```hcl
terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0"
    }
  }
}

resource "local_file" "practice" {
  filename = "/tmp/tf-practice.txt"
  content  = "Terraform Associate"
}
```

```bash
cd ~/tf-practice/q01
terraform init
terraform apply -auto-approve
cat /tmp/tf-practice.txt
```

---

### Solution — Q2: Variables, Validation, and count

**`~/tf-practice/q02/variables.tf`**
```hcl
variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "replica_count" {
  type    = number
  default = 2

  validation {
    condition     = var.replica_count >= 1 && var.replica_count <= 10
    error_message = "replica_count must be between 1 and 10 inclusive."
  }
}
```

**`~/tf-practice/q02/main.tf`**
```hcl
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

resource "null_resource" "app" {
  count = var.replica_count

  triggers = {
    name = "app-${var.environment}-${count.index}"
  }
}
```

```bash
cd ~/tf-practice/q02
terraform init
terraform apply -auto-approve -var="environment=dev"
terraform state list
```

---

### Solution — Q3: Remote S3 Backend

**`~/tf-practice/q03/main.tf`**
```hcl
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }

  backend "s3" {
    bucket = "<paste-bucket-name-here>"   # value from /tmp/practice-bucket-name.txt
    key    = "practice/q03.tfstate"
    region = "us-east-1"
  }
}

resource "null_resource" "q03" {}
```

> Note: the `backend` block does not support variable interpolation. You must hard-code the
> bucket name (copy it from `/tmp/practice-bucket-name.txt`) or use partial configuration
> with `-backend-config`.

Alternative using partial backend configuration:

**`~/tf-practice/q03/main.tf`** (backend block omitted — use `-backend-config`)
```hcl
terraform {
  required_providers {
    null = { source = "hashicorp/null", version = ">= 3.0" }
  }

  backend "s3" {
    key    = "practice/q03.tfstate"
    region = "us-east-1"
  }
}

resource "null_resource" "q03" {}
```

```bash
BUCKET=$(cat /tmp/practice-bucket-name.txt)
terraform init -backend-config="bucket=${BUCKET}"
terraform apply -auto-approve
aws s3 ls "s3://${BUCKET}/practice/"
```

---

### Solution — Q4: Data Source and Output

**`~/tf-practice/q04/main.tf`**
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_vpc" "practice" {
  id = file("/tmp/practice-vpc-id.txt")
}

output "vpc_cidr" {
  value = data.aws_vpc.practice.cidr_block
}
```

> `file()` reads `/tmp/practice-vpc-id.txt` at plan time. If the file contains a trailing
> newline, use `trimspace(file("/tmp/practice-vpc-id.txt"))`.

```bash
cd ~/tf-practice/q04
terraform init
terraform apply -auto-approve
terraform output vpc_cidr
```

---

### Solution — Q5: Writing and Calling a Module

**`~/tf-practice/q05/modules/tagger/variables.tf`**
```hcl
variable "resource_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "team" {
  type = string
}
```

**`~/tf-practice/q05/modules/tagger/outputs.tf`**
```hcl
output "tags" {
  value = {
    Name        = var.resource_name
    Environment = var.environment
    Team        = var.team
    ManagedBy   = "Terraform"
  }
}
```

**`~/tf-practice/q05/main.tf`**
```hcl
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

module "tagger" {
  source = "./modules/tagger"

  resource_name = "web-server"
  environment   = "prod"
  team          = "platform"
}

resource "null_resource" "example" {
  triggers = module.tagger.tags
}

output "tags" {
  value = module.tagger.tags
}
```

```bash
cd ~/tf-practice/q05
terraform init
terraform apply -auto-approve
terraform output tags
```

---

### Solution — Q6: for_each with a Map of Objects

**`~/tf-practice/q06/variables.tf`**
```hcl
variable "servers" {
  type = map(object({
    instance_type = string
    port          = number
  }))

  default = {
    web = { instance_type = "t3.micro",  port = 80   }
    api = { instance_type = "t3.small",  port = 8080 }
    db  = { instance_type = "t3.medium", port = 5432 }
  }
}
```

**`~/tf-practice/q06/main.tf`**
```hcl
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

resource "null_resource" "server" {
  for_each = var.servers

  triggers = {
    instance_type = each.value.instance_type
    port          = tostring(each.value.port)
  }
}
```

```bash
cd ~/tf-practice/q06
terraform init
terraform apply -auto-approve
terraform state list
```

---

### Solution — Q7: templatefile() Function

**`~/tf-practice/q07/main.tf`**
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_region" "current" {}

locals {
  rendered = templatefile("${path.module}/template.txt.tpl", {
    name   = "Terraform"
    region = data.aws_region.current.name
  })
}

output "rendered" {
  value = local.rendered
}
```

The template file (`template.txt.tpl`) was created by the setup configuration:
```
Hello, ${name}! You are in ${region}.
```

```bash
cd ~/tf-practice/q07
terraform init
terraform apply -auto-approve
terraform output rendered
```

---

### Solution — Q8: for Expression Transforming a List

**`~/tf-practice/q08/main.tf`**
```hcl
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

variable "allowed_cidrs" {
  type    = list(string)
  default = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

locals {
  cidr_objects = [
    for cidr in var.allowed_cidrs : {
      cidr        = cidr
      description = "Allow from ${cidr}"
    }
  ]
}

output "cidr_objects" {
  value = local.cidr_objects
}
```

```bash
cd ~/tf-practice/q08
terraform init
terraform apply -auto-approve
terraform output cidr_objects
```

---

### Solution — Q9: terraform import

**`~/tf-practice/q09/main.tf`**
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "imported" {
  bucket = "<paste-bucket-name-here>"   # value from /tmp/practice-import-bucket.txt
}
```

```bash
IMPORT_BUCKET=$(cat /tmp/practice-import-bucket.txt)
cd ~/tf-practice/q09
terraform init
terraform import aws_s3_bucket.imported "${IMPORT_BUCKET}"
terraform state show aws_s3_bucket.imported
```

After import, run `terraform plan`. If there are drift warnings (e.g., tags, versioning),
add the corresponding arguments to the resource block to match the existing state or use
`ignore_changes` in a `lifecycle` block:

```hcl
resource "aws_s3_bucket" "imported" {
  bucket = "<bucket-name>"

  lifecycle {
    ignore_changes = all
  }
}
```

---

### Solution — Q10: Workspaces

**`~/tf-practice/q10/main.tf`**
```hcl
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

resource "null_resource" "env_marker" {
  triggers = {
    env = terraform.workspace
  }
}
```

```bash
cd ~/tf-practice/q10
terraform init

terraform workspace new dev
terraform apply -auto-approve

terraform workspace new staging
terraform apply -auto-approve

terraform workspace new prod
terraform apply -auto-approve

# Verify all workspaces exist
terraform workspace list

# Verify isolation
terraform workspace select dev
terraform state list     # shows null_resource.env_marker

terraform workspace select staging
terraform state list     # independent state, also shows null_resource.env_marker

terraform workspace select prod
terraform state list     # independent state
```

---

### Solution — Q11: terraform test

**`~/tf-practice/q11/modules/namer/main.tf`**
```hcl
terraform {
  # No provider needed — this module only computes values
}

variable "prefix" {
  type = string
}

variable "suffix" {
  type = string
}

output "full_name" {
  value = "${var.prefix}-${var.suffix}"
}
```

**`~/tf-practice/q11/tests/validate.tftest.hcl`**
```hcl
run "name_is_correct" {
  command = plan

  module {
    source = "../modules/namer"
  }

  variables {
    prefix = "app"
    suffix = "prod"
  }

  assert {
    condition     = output.full_name == "app-prod"
    error_message = "Expected full_name to be 'app-prod', got '${output.full_name}'"
  }
}
```

```bash
cd ~/tf-practice/q11
terraform init
terraform test
```

Expected output:
```
tests/validate.tftest.hcl... pass
  run "name_is_correct"... pass

Success! 1 passed, 0 failed.
```

> Note: `terraform test` looks for test files in `tests/` by default. The module source
> is a relative path from the test file's location, but Terraform resolves it relative to
> the root module directory — so `"../modules/namer"` from the root `q11/` directory means
> `modules/namer`. If Terraform can't find it, try `source = "./modules/namer"`.

---

### Solution — Q12: Complex for Expression

**`~/tf-practice/q12/main.tf`**
```hcl
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

variable "instances" {
  type = map(object({
    ip   = string
    port = number
  }))

  default = {
    web = { ip = "10.0.1.5", port = 80   }
    api = { ip = "10.0.2.5", port = 8080 }
  }
}

locals {
  connection_strings = [
    for name, attrs in var.instances :
    "${name}: ${attrs.ip}:${attrs.port}"
  ]
}

output "connection_strings" {
  value = local.connection_strings
}
```

```bash
cd ~/tf-practice/q12
terraform init
terraform apply -auto-approve
terraform output connection_strings
```

Expected:
```
tolist([
  "api: 10.0.2.5:8080",
  "web: 10.0.1.5:80",
])
```

> Map iteration in Terraform is ordered lexicographically by key, so `api` will always
> appear before `web`. If the question requires a sorted list (as shown), the output
> is deterministic. If you need explicit sorting, use `sort()`:
> `value = sort(local.connection_strings)`.
