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

## Question 3 — Remote GCS Backend (8 points) — Associate

**Objective:** Configure a remote state backend using Google Cloud Storage.

The name of the pre-provisioned GCS bucket is in `/tmp/practice-bucket-name.txt`.

In `~/tf-practice/q03/`, write a Terraform configuration that:
1. Configures a `gcs` backend using the bucket whose name is in `/tmp/practice-bucket-name.txt`, with prefix `practice/q03`.
2. Declares the `hashicorp/null` provider and at least one `null_resource`.
3. Runs `terraform init` (you will need to confirm the backend migration if any local state exists) and `terraform apply -auto-approve` successfully.

**Verification:**
```bash
BUCKET=$(cat /tmp/practice-bucket-name.txt)
gsutil ls "gs://${BUCKET}/practice/"
```
Expected: a line showing a state file under `practice/q03/`.

---

## Question 4 — Data Source and Output (8 points) — Associate

**Objective:** Use a data source to look up existing infrastructure and expose its attributes as an output.

A VPC network named `practice-vpc` was created by the setup script. Its self_link is in `/tmp/practice-vpc-selflink.txt`.

In `~/tf-practice/q04/`, write a Terraform configuration that:
1. Declares the `hashicorp/google` provider.
2. Uses a `data "google_compute_network"` data source that looks up the network by name (`"practice-vpc"`). You must supply the `project` argument — use a variable or hard-code your project ID.
3. Declares an output named `vpc_self_link` whose value is the `self_link` attribute of the looked-up network.

**Verification:**
```bash
cd ~/tf-practice/q04
terraform output vpc_self_link
```
Expected: a string matching the value in `/tmp/practice-vpc-selflink.txt`.

---

## Question 5 — Writing and Calling a Module (10 points) — Associate+

**Objective:** Author a reusable child module and call it from a root configuration.

Write a module at `~/tf-practice/q05/modules/tagger/` that:
- Accepts three input variables: `resource_name` (string), `environment` (string), `team` (string).
- Outputs a value named `labels` that is a `map(string)` containing at minimum:
  - `name` = `var.resource_name`
  - `environment` = `var.environment`
  - `team` = `var.team`
  - `managed_by` = `"terraform"`

In the root configuration at `~/tf-practice/q05/`:
- Declare the `hashicorp/null` provider.
- Call the `tagger` module with `resource_name = "web-server"`, `environment = "prod"`, `team = "platform"`.
- Create a `null_resource` named `example` with a `triggers` block that includes all entries from the module's `labels` output (use the spread-into-triggers pattern).
- Declare an output named `labels` whose value is the module's `labels` output.

**Verification:**
```bash
cd ~/tf-practice/q05
terraform output labels
```
Expected: a map containing at minimum `name`, `environment`, `team`, and `managed_by` keys.

---

## Question 6 — for_each with a Map of Objects (10 points) — Associate+

**Objective:** Use `for_each` to create multiple resources from a map variable.

In `~/tf-practice/q06/`:

Write a `variables.tf` that declares a variable named `servers` of type:
```hcl
map(object({
  machine_type = string
  zone         = string
}))
```
with a default of at least two entries, for example:
```hcl
{
  web = { machine_type = "e2-micro",  zone = "us-central1-a" }
  api = { machine_type = "e2-small",  zone = "us-central1-b" }
}
```

Write a `main.tf` that:
- Declares the `hashicorp/null` provider.
- Creates `null_resource` resources using `for_each` over `var.servers`. Name the resource block `server`. Each resource should have a `triggers` block with `machine_type` and `zone` from the map values.

**Verification:**
```bash
cd ~/tf-practice/q06
terraform state list
```
Expected (one line per map entry, order may vary):
```
null_resource.server["api"]
null_resource.server["web"]
```

---

## Question 7 — templatefile() Function (10 points) — Associate+

**Objective:** Use the `templatefile()` built-in function to render a template.

The file `~/tf-practice/q07/startup.sh.tpl` already exists with the following content:
```
#!/bin/bash
ENV="${env}"
PROJECT="${project}"
echo "Running ${project} in ${env}"
```

In `~/tf-practice/q07/`, write a Terraform configuration that:
1. Declares the `hashicorp/null` provider (no cloud provider is needed for this question).
2. In a `locals` block, uses `templatefile()` to render `startup.sh.tpl` with:
   - `env = "production"`
   - `project = "my-app"`
3. Declares an output named `rendered_script` whose value is the rendered string from locals.

**Verification:**
```bash
cd ~/tf-practice/q07
terraform output rendered_script
```
Expected: the rendered script string containing `"Running my-app in production"`.

---

## Question 8 — for Expression Transforming a List (10 points) — Associate+

**Objective:** Use a `for` expression to transform one collection type into another.

In `~/tf-practice/q08/`:

Write a configuration that:
1. Declares the `hashicorp/null` provider.
2. Defines a variable named `allowed_ips` of type `list(string)` with a default of `["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]`.
3. In a `locals` block, uses a `for` expression to transform `var.allowed_ips` into a `list(object({ cidr = string, description = string }))` where `description = "Allow traffic from ${cidr}"` for each entry.
4. Declares an output named `ip_objects` whose value is the transformed list from locals.

**Verification:**
```bash
cd ~/tf-practice/q08
terraform output ip_objects
```
Expected: a list of three objects. Each object must have a `cidr` and a `description` field where `description` equals `"Allow traffic from <cidr>"`.

---

## Question 9 — terraform import (10 points) — Associate+

**Objective:** Bring an existing GCS bucket under Terraform management using `terraform import`.

The name of a pre-existing GCS bucket is in `/tmp/practice-import-bucket.txt`.

In `~/tf-practice/q09/`:
1. Declare the `hashicorp/google` provider with your project set.
2. Write a `resource "google_storage_bucket" "imported"` block. At minimum it must contain a `name` argument set to the bucket name from `/tmp/practice-import-bucket.txt` and a `location` argument matching the bucket's region (the setup creates it in `US-CENTRAL1`). Keep the block minimal.
3. Run `terraform init`.
4. Run `terraform import google_storage_bucket.imported <bucket-name>` using the name from the file.

> Note: the import ID for a GCS bucket is simply the bucket name — not an ARN or a project-prefixed path.

5. Run `terraform plan` — it should show no changes needed (or only ignorable drift). If there are conflicting attributes, adjust the resource block to match.

**Verification:**
```bash
cd ~/tf-practice/q09
terraform state show google_storage_bucket.imported
```
Expected: output showing the bucket's attributes (name, location, project, etc.).

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

**Objective:** Write a `terraform test` file that validates a module's output.

Write a module at `~/tf-practice/q11/modules/labeler/` that:
- Accepts two input variables: `prefix` (string) and `env` (string).
- Creates a `null_resource` named `marker` with a trigger `label = "${var.prefix}-${var.env}"`.
- Outputs a value named `full_label` whose value is `"${var.prefix}-${var.env}"`.

Write a test file at `~/tf-practice/q11/tests/validate.tftest.hcl` that:
- Declares a `mock_provider "null" {}` block.
- Contains a `run` block named `"label_is_correct"` that:
  - Calls the labeler module.
  - Passes `prefix = "app"` and `env = "prod"` as input variables.
  - Asserts that `output.full_label == "app-prod"`.

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

## Question 13 — lifecycle Rules: prevent_destroy and create_before_destroy (8 points) — Professional

**Objective:** Protect a critical simulated resource from accidental deletion and observe replacement ordering.

In `~/tf-practice/q13/`:

1. Declare the `hashicorp/null` provider.
2. Create a `null_resource` named `production_db` with:
   - a `triggers` block containing `version = "v1"`
   - a `lifecycle` block setting both `prevent_destroy = true` and `create_before_destroy = true`
3. Create a second `null_resource` named `app_server` with a trigger `db_id = null_resource.production_db.id` (this simulates a dependency on the database).
4. Apply the configuration.
5. Attempt `terraform destroy -auto-approve`. Observe the error message — note which lifecycle attribute caused the failure and on which resource.
6. Without changing anything else, change the `version` trigger to `"v2"` **and** remove the `prevent_destroy = true` line from the lifecycle block. Keep `create_before_destroy = true`.
7. Run `terraform plan` — observe that `null_resource.production_db` must be replaced and note the replacement ordering in the plan output (look for `(deposed)` or the create-before-destroy ordering marker).
8. Apply and verify both resources exist in state.

**Verification — step 5 (destroy must fail):**
```bash
cd ~/tf-practice/q13
terraform destroy -auto-approve
```
Expected: an error containing `prevent_destroy` (the apply should not proceed).

**Verification — step 8 (both resources exist after replacement):**
```bash
cd ~/tf-practice/q13
terraform state list
```
Expected:
```
null_resource.app_server
null_resource.production_db
```

---

## Question 14 — Operational Trigger Pattern (6 points) — Professional

**Objective:** Implement the timestamp-based `null_resource` trigger pattern used to invoke one-off operational actions from `terraform apply`.

In `~/tf-practice/q14/`:

1. Declare the `hashicorp/null` provider.
2. Declare a `string` variable named `operation_timestamp` with a default of `""`.
3. Create a `null_resource` named `trigger` with:
   - `count = var.operation_timestamp != "" ? 1 : 0`
   - a `triggers` block with a single key `ts = var.operation_timestamp`
   - a `local-exec` provisioner that prints `"Operation triggered at <timestamp>"` (substitute the actual variable value)
4. Declare an output named `operation_ran` with value `"yes"` when `operation_timestamp` is non-empty, `"no"` otherwise.

Then perform all four steps in order and verify each result:

**a.** Apply without setting `operation_timestamp`:
```bash
terraform apply -auto-approve
terraform output operation_ran   # Expected: "no"
terraform state list             # Expected: (empty — no null_resource)
```

**b.** Apply with a timestamp — record the value you used:
```bash
TS=$(date +%s)
terraform apply -auto-approve -var="operation_timestamp=${TS}"
# Expected: null_resource.trigger[0] is created, provisioner output is visible
terraform output operation_ran   # Expected: "yes"
```

**c.** Apply again with the SAME timestamp from step (b):
```bash
terraform apply -auto-approve -var="operation_timestamp=${TS}"
# Expected: "No changes." — triggers unchanged, provisioner does NOT re-run
```

**d.** Apply with a new timestamp:
```bash
terraform apply -auto-approve -var="operation_timestamp=$(date +%s)"
# Expected: null_resource.trigger[0] is replaced, provisioner runs again
```

**Verification — step (b) output:**
```bash
terraform output operation_ran
```
Expected: `"yes"`

---

## Scoring Checklist

| # | Question | Points | Complete? |
|---|----------|--------|-----------|
| 1 | Local file resource | 8 | [ ] |
| 2 | Variables, validation, count | 8 | [ ] |
| 3 | Remote GCS backend | 8 | [ ] |
| 4 | Data source and output | 8 | [ ] |
| 5 | Writing and calling a module | 10 | [ ] |
| 6 | for_each with map of objects | 10 | [ ] |
| 7 | templatefile() function | 10 | [ ] |
| 8 | for expression (list transform) | 10 | [ ] |
| 9 | terraform import | 10 | [ ] |
| 10 | Workspaces | 6 | [ ] |
| 11 | terraform test | 6 | [ ] |
| 12 | Complex for expression | 6 | [ ] |
| 13 | lifecycle rules: prevent_destroy, create_before_destroy | 8 | [ ] |
| 14 | Operational trigger pattern | 6 | [ ] |
| | **Total** | **114** | |

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

### Solution — Q3: Remote GCS Backend

**`~/tf-practice/q03/main.tf`**
```hcl
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }

  backend "gcs" {
    bucket = "<paste-bucket-name-here>"   # value from /tmp/practice-bucket-name.txt
    prefix = "practice/q03"
  }
}

resource "null_resource" "q03" {}
```

> Note: the `backend` block does not support variable interpolation. You must hard-code the
> bucket name (copy it from `/tmp/practice-bucket-name.txt`) or use partial configuration
> with `-backend-config`.

Alternative using partial backend configuration:

```hcl
terraform {
  required_providers {
    null = { source = "hashicorp/null", version = ">= 3.0" }
  }

  backend "gcs" {
    prefix = "practice/q03"
  }
}

resource "null_resource" "q03" {}
```

```bash
BUCKET=$(cat /tmp/practice-bucket-name.txt)
terraform init -backend-config="bucket=${BUCKET}"
terraform apply -auto-approve
gsutil ls "gs://${BUCKET}/practice/"
```

---

### Solution — Q4: Data Source and Output

**`~/tf-practice/q04/main.tf`**
```hcl
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0"
    }
  }
}

variable "gcp_project" {
  type = string
}

provider "google" {
  project = var.gcp_project
}

data "google_compute_network" "practice" {
  name    = "practice-vpc"
  project = var.gcp_project
}

output "vpc_self_link" {
  value = data.google_compute_network.practice.self_link
}
```

> `data "google_compute_network"` requires the `project` argument — it will not fall back
> to the provider default for data source lookups. Pass your project ID via `-var` or a
> `terraform.tfvars` file.

```bash
cd ~/tf-practice/q04
terraform init
terraform apply -auto-approve -var="gcp_project=<your-project-id>"
terraform output vpc_self_link
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
output "labels" {
  value = {
    name        = var.resource_name
    environment = var.environment
    team        = var.team
    managed_by  = "terraform"
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
  triggers = module.tagger.labels
}

output "labels" {
  value = module.tagger.labels
}
```

```bash
cd ~/tf-practice/q05
terraform init
terraform apply -auto-approve
terraform output labels
```

---

### Solution — Q6: for_each with a Map of Objects

**`~/tf-practice/q06/variables.tf`**
```hcl
variable "servers" {
  type = map(object({
    machine_type = string
    zone         = string
  }))

  default = {
    web = { machine_type = "e2-micro", zone = "us-central1-a" }
    api = { machine_type = "e2-small", zone = "us-central1-b" }
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
    machine_type = each.value.machine_type
    zone         = each.value.zone
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
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

locals {
  rendered_script = templatefile("${path.module}/startup.sh.tpl", {
    env     = "production"
    project = "my-app"
  })
}

output "rendered_script" {
  value = local.rendered_script
}
```

The template file (`startup.sh.tpl`) was created by the setup configuration:
```
#!/bin/bash
ENV="${env}"
PROJECT="${project}"
echo "Running ${project} in ${env}"
```

```bash
cd ~/tf-practice/q07
terraform init
terraform apply -auto-approve
terraform output rendered_script
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

variable "allowed_ips" {
  type    = list(string)
  default = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

locals {
  ip_objects = [
    for cidr in var.allowed_ips : {
      cidr        = cidr
      description = "Allow traffic from ${cidr}"
    }
  ]
}

output "ip_objects" {
  value = local.ip_objects
}
```

```bash
cd ~/tf-practice/q08
terraform init
terraform apply -auto-approve
terraform output ip_objects
```

---

### Solution — Q9: terraform import

**`~/tf-practice/q09/main.tf`**
```hcl
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0"
    }
  }
}

variable "gcp_project" {
  type = string
}

provider "google" {
  project = var.gcp_project
}

resource "google_storage_bucket" "imported" {
  name     = "<paste-bucket-name-here>"   # value from /tmp/practice-import-bucket.txt
  location = "US-CENTRAL1"
  project  = var.gcp_project
}
```

```bash
IMPORT_BUCKET=$(cat /tmp/practice-import-bucket.txt)
cd ~/tf-practice/q09
terraform init
terraform import -var="gcp_project=<your-project-id>" \
  google_storage_bucket.imported "${IMPORT_BUCKET}"
terraform state show google_storage_bucket.imported
```

> The import ID for a `google_storage_bucket` is the bucket name alone — not an ARN or
> a project-prefixed path. After import, run `terraform plan` and adjust the resource
> block if there are drift warnings (e.g., `uniform_bucket_level_access`). Use a
> `lifecycle { ignore_changes = all }` block if you want to silence all drift.

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

**`~/tf-practice/q11/modules/labeler/main.tf`**
```hcl
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

variable "prefix" {
  type = string
}

variable "env" {
  type = string
}

resource "null_resource" "marker" {
  triggers = {
    label = "${var.prefix}-${var.env}"
  }
}

output "full_label" {
  value = "${var.prefix}-${var.env}"
}
```

**`~/tf-practice/q11/tests/validate.tftest.hcl`**
```hcl
mock_provider "null" {}

run "label_is_correct" {
  command = plan

  module {
    source = "../modules/labeler"
  }

  variables {
    prefix = "app"
    env    = "prod"
  }

  assert {
    condition     = output.full_label == "app-prod"
    error_message = "Expected full_label to be 'app-prod', got '${output.full_label}'"
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
  run "label_is_correct"... pass

Success! 1 passed, 0 failed.
```

> The `mock_provider "null" {}` block stubs out the null provider so the test does not
> require a real provider configuration. The `module` block in the `run` stanza points
> to the module under test using a path relative to the root module directory.

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
> appear before `web`. If you need explicit sorting, wrap with `sort()`:
> `value = sort(local.connection_strings)`.

---

### Solution — Q13: lifecycle Rules

**`~/tf-practice/q13/main.tf`**
```hcl
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

resource "null_resource" "production_db" {
  triggers = {
    version = "v1"
  }

  lifecycle {
    prevent_destroy       = true
    create_before_destroy = true
  }
}

resource "null_resource" "app_server" {
  triggers = {
    db_id = null_resource.production_db.id
  }
}
```

```bash
cd ~/tf-practice/q13
terraform init
terraform apply -auto-approve

# Step 5 — attempt destroy (will fail):
terraform destroy -auto-approve
# Error: Instance cannot be destroyed
# on main.tf line X, in resource "null_resource" "production_db":
#   prevent_destroy = true
```

Step 6 — edit main.tf: change `version = "v1"` to `version = "v2"` and remove `prevent_destroy = true`. The lifecycle block should now contain only `create_before_destroy = true`.

```bash
# Step 7 — observe replacement ordering:
terraform plan
# null_resource.production_db must be replaced
# With create_before_destroy = true, the plan shows the new instance is
# created first, then the old instance is deposed (destroyed).
# Look for "(deposed)" in the plan output.

# Step 8 — apply and verify:
terraform apply -auto-approve
terraform state list
# null_resource.app_server
# null_resource.production_db
```

> `prevent_destroy = true` guards against both `terraform destroy` and any plan that would
> destroy the resource as part of a replacement. It must be removed from code (not just
> from state) before Terraform will allow destruction. `create_before_destroy = true` changes
> replacement ordering: the new resource is created and its ID is written to state before the
> old resource is destroyed. Resources that depend on the replaced resource (like `app_server`)
> see the new ID without a window where the resource is absent.

---

### Solution — Q14: Operational Trigger Pattern

**`~/tf-practice/q14/main.tf`**
```hcl
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

variable "operation_timestamp" {
  type    = string
  default = ""
}

resource "null_resource" "trigger" {
  count = var.operation_timestamp != "" ? 1 : 0

  triggers = {
    ts = var.operation_timestamp
  }

  provisioner "local-exec" {
    command = "echo 'Operation triggered at ${var.operation_timestamp}'"
  }
}

output "operation_ran" {
  value = var.operation_timestamp != "" ? "yes" : "no"
}
```

```bash
cd ~/tf-practice/q14
terraform init

# Step a — no timestamp:
terraform apply -auto-approve
terraform output operation_ran   # "no"
terraform state list             # (empty)

# Step b — set a timestamp:
TS=$(date +%s)
terraform apply -auto-approve -var="operation_timestamp=${TS}"
# null_resource.trigger[0] created; provisioner prints "Operation triggered at <ts>"
terraform output operation_ran   # "yes"

# Step c — same timestamp again:
terraform apply -auto-approve -var="operation_timestamp=${TS}"
# "No changes." — triggers map unchanged, provisioner does NOT re-run

# Step d — new timestamp:
terraform apply -auto-approve -var="operation_timestamp=$(date +%s)"
# null_resource.trigger[0] is REPLACED (new triggers), provisioner runs again
```

> The key insight: Terraform decides whether to re-run a null_resource provisioner by
> comparing the current `triggers` map to the stored one in state. If they match, Terraform
> sees the resource as up-to-date and skips it — the provisioner does not run. A unique
> timestamp guarantees the triggers map changes on every intended invocation.
>
> A boolean (`true`/`true`) trigger fails for the same reason: the second apply sees
> `trigger = true` in state and `trigger = true` in config — no change, no re-run.
> The timestamp pattern is the correct solution for retriggerable operations.
