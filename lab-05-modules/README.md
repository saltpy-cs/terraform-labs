# Lab 05 — Modules

## Objectives

- Write a reusable GCP VPC module with inputs and outputs
- Call the module from a root configuration
- Pass variables into a module and consume its outputs
- Understand module versioning: local paths vs Terraform Registry
- Use a public module from the Terraform Registry (pattern demonstration)
- Understand module encapsulation — only declared outputs are accessible

---

## Concepts

### What is a module?

A Terraform module is any directory that contains `.tf` files. There is nothing special about a module's syntax — it is just Terraform code. The distinction is in how it is used:

- **Root module**: the directory where you run `terraform init`, `plan`, and `apply`. Every Terraform project has exactly one root module.
- **Child module**: any module called from within another module using a `module` block. Child modules can be local (a subdirectory) or remote (Terraform Registry, Git, etc.).

Modules solve a code-organisation problem. Without them, every environment (dev, staging, prod) would repeat the same network, firewall, and instance definitions. Modules let you write the logic once and call it multiple times with different inputs.

### Module structure: convention vs requirement

Terraform does not enforce any particular file layout, but the community convention for a module is:

```
modules/vpc/
  variables.tf   # Input variable declarations (what callers must/can provide)
  main.tf        # Resources and data sources
  outputs.tf     # Output value declarations (what callers can read back)
```

You can put everything in a single `main.tf` and it will work. The split into three files is a readability convention that makes inputs, resources, and outputs easy to find.

### The `module` block

A module call looks like this:

```hcl
module "vpc" {
  source = "./modules/vpc"    # Required: where the module code lives

  # All other arguments are passed to the module as input variables
  network_name = "my-vpc"
  project      = var.gcp_project
}
```

After calling a module you access its outputs via `module.<name>.<output_name>`:

```hcl
resource "google_compute_firewall" "allow_ssh" {
  network = module.vpc.network_name
}
```

### Local modules

When `source` starts with `./` or `../` Terraform treats it as a local path relative to the calling configuration:

```hcl
source = "./modules/vpc"
```

Local modules do not have a `version` argument — you control the source directly. They are ideal for splitting a large configuration into logical chunks within the same repository.

After adding or changing a local module `source`, you must run `terraform init` again for Terraform to pick up the change. Terraform copies the module into `.terraform/modules/`.

### Registry modules

Modules published to [registry.terraform.io](https://registry.terraform.io) have a three-part address:

```
<namespace>/<module-name>/<provider>
```

For example: `terraform-google-modules/network/google`

```hcl
module "vpc_registry" {
  source  = "terraform-google-modules/network/google"
  version = "~> 9.0"

  project_id   = var.gcp_project
  network_name = "my-vpc"
  # ...
}
```

Registry modules are downloaded on `terraform init` and cached in `.terraform/modules/`. The `version` argument is **required** for registry modules — omitting it means Terraform will always download the latest version, which can break your configuration unexpectedly when the module author makes a breaking change.

### Module versioning and the `~>` operator

The `~>` (pessimistic constraint) operator pins to a major version while allowing minor and patch updates:

| Constraint  | Meaning                                    |
|-------------|--------------------------------------------|
| `= 9.1.0`   | Exactly 9.1.0, nothing else               |
| `~> 9.1`    | 9.1.x — patch updates only               |
| `~> 9.0`    | 9.x.x — minor and patch updates allowed  |
| `>= 9.0`    | Anything from 9.0 upward (avoid this)    |

For production, `~> 9.1` (pinned to minor) is safer than `~> 9.0`. For learning, `~> 9.0` is fine.

### Module outputs and encapsulation

A module's internal resources are **not visible** to the caller. The only way to get information back from a module is through declared outputs.

If you try to access an internal resource directly:

```hcl
# WRONG — this will fail
subnetwork = module.vpc.google_compute_network.this.id
```

Terraform will report an error like:

```
Error: Unsupported attribute
  module.vpc does not have an attribute named "google_compute_network"
```

The correct approach is to expose the information you need via an `output` block inside the module:

```hcl
# Inside modules/vpc/outputs.tf
output "network_id" {
  value = google_compute_network.this.id
}
```

Then consume it in the root:

```hcl
network = module.vpc.network_id
```

This encapsulation is intentional. A module author can refactor internal implementation details without breaking callers, as long as the outputs stay the same.

### No `provider` blocks inside modules

Modules should never declare their own `provider` blocks. Providers are always configured in the root module and automatically inherited by child modules. Putting a provider inside a module creates tight coupling to a specific project/region, making the module impossible to reuse.

The correct pattern is to configure the provider in the root:

```hcl
# root main.tf
provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}
```

### Resource addresses in state

When Terraform creates resources through a module, the state address includes the module path:

```
module.vpc.google_compute_network.this
module.vpc.google_compute_subnetwork.this
```

You can see this with `terraform state list`. The root module's resources have no prefix:

```
google_compute_firewall.allow_ssh
google_compute_instance.app
```

---

## Setup

**Prerequisites**: `gcloud` CLI installed, Terraform >= 1.5 installed.

**Authentication**: Run `gcloud auth application-default login` once before using Terraform. This writes credentials that the Google provider reads automatically (Application Default Credentials).

**Estimated cost**: One GCE e2-micro falls within the GCP free tier in `us-central1`. Destroy promptly when done.

1. Authenticate with GCP:
   ```bash
   gcloud auth application-default login
   ```

2. Find your public IP:
   ```bash
   curl -s https://checkip.amazonaws.com
   ```

3. Create `terraform/terraform.tfvars`:
   ```hcl
   gcp_project = "YOUR-PROJECT-ID"
   my_ip_cidr  = "YOUR.IP.HERE/32"
   ```

4. Review the module structure before running any commands:
   ```
   terraform/
     modules/
       vpc/
         variables.tf   # Module inputs
         main.tf        # Network and subnetwork resources
         outputs.tf     # network_id, subnet_self_link, etc.
     main.tf            # Root: calls the module, creates firewall and instance
     variables.tf       # Root inputs
     outputs.tf         # Root outputs
   ```

---

## Exercises

### Exercise 1 — Read the module and trace the data flow

Before running any commands, read through the module files and answer these questions:

- `modules/vpc/variables.tf` declares `subnet_cidr`. Where is it used in `modules/vpc/main.tf`?
- `modules/vpc/outputs.tf` declares `subnet_self_link`. How is it consumed in the root `main.tf`?
- `modules/vpc/variables.tf` has `network_name` with no default. What happens in root `main.tf` if you do not pass `network_name` to the module call?

### Exercise 2 — Initialise and observe module installation

```bash
cd terraform
terraform init
```

Look for the "Initializing modules..." section in the output. Terraform reads the `source` path, copies the module into `.terraform/modules/`, and records it in `.terraform/modules/modules.json`. Inspect that file:

```bash
cat .terraform/modules/modules.json
```

### Exercise 3 — Plan and observe module resource addresses

```bash
terraform plan
```

Note how every resource inside the module is prefixed with the module path:

```
module.vpc.google_compute_network.this      will be created
module.vpc.google_compute_subnetwork.this   will be created
```

Root resources have no module prefix:

```
google_compute_firewall.allow_ssh   will be created
google_compute_instance.app         will be created
```

### Exercise 4 — Apply

```bash
terraform apply
```

Type `yes` when prompted.

### Exercise 5 — Consume module outputs

```bash
terraform output
terraform output network_id
terraform output subnet_id
terraform output instance_external_ip
```

Notice that `network_id` and `subnet_id` are values that originated inside the module. The root configuration accesses them only through the declared outputs, not directly.

### Exercise 6 — Extend the module cleanly

Open `terraform/modules/vpc/variables.tf` and add a new variable at the bottom:

```hcl
variable "description" {
  description = "Optional description for the network resource."
  type        = string
  default     = ""
}
```

Open `terraform/modules/vpc/main.tf` and uncomment the description line in `google_compute_network.this`:

```hcl
description = var.description
```

Open `terraform/main.tf` and pass the new variable in the `module "vpc"` block:

```hcl
description = ""
```

Run `terraform plan`. The plan should show **no changes** because you are passing an empty string that matches the current resource state. This demonstrates the clean extension pattern: new optional inputs can be added to a module without forcing callers to update or causing resource recreation.

### Exercise 7 — Encapsulation (expected failure)

Edit `terraform/main.tf` temporarily. In `google_compute_firewall.allow_ssh`, change the `network` argument to reference the internal resource directly:

```hcl
# Intentionally wrong — for learning only
network = module.vpc.google_compute_network.this.name
```

Run `terraform plan` and read the error:

```
Error: Unsupported attribute
  module.vpc does not have an attribute named "google_compute_network"
```

Revert the change:

```hcl
network = module.vpc.network_name
```

### Exercise 8 — Registry module pattern

Open `terraform/main.tf` and uncomment the `module "vpc_registry"` block. Run:

```bash
terraform init
```

Observe the new download step in the output — Terraform fetches the module from `registry.terraform.io`. Run `terraform plan` to see the additional resources the public module would create. **Do not apply.** Comment the block back out, then run `terraform init` again.

### Exercise 9 — Destroy

```bash
terraform destroy
```

Confirm with `yes`.

---

## Key Takeaways

- A module is any directory with `.tf` files. The root module is where you run Terraform commands.
- Modules enforce **encapsulation** — only declared outputs are accessible to callers. Internal resources cannot be referenced directly.
- Local modules use relative `./` paths. Registry modules use `namespace/name/provider` paths and require a `version` constraint.
- Always pin registry module versions with `~> MAJOR.MINOR` to avoid unexpected breaking changes.
- Run `terraform init` after any change to a `source` path.
- Module resources appear in state as `module.<name>.<resource_type>.<resource_name>`.
- Never declare `provider` blocks inside modules — providers are configured in the root and inherited automatically.

---

## Cleanup

```bash
cd terraform
terraform destroy
```

Verify in the GCP Console that no Compute Engine instances, networks, or firewall rules remain.
