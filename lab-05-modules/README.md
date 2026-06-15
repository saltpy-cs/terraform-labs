# Lab 05 — Modules

## Objectives

- Understand why modules exist and what problem they solve
- Write a reusable VPC module with inputs and outputs
- Call the module from a root configuration
- Pass variables into a module and consume its outputs
- Understand module versioning: local paths vs Terraform Registry
- Use a public module from the Terraform Registry
- Understand module composition (calling modules from modules)

---

## Concepts

### What is a module?

A Terraform module is any directory that contains `.tf` files. There is nothing special about a module's syntax — it is just Terraform code. The distinction is in how it is used:

- **Root module**: the directory where you run `terraform init`, `plan`, and `apply`. Every Terraform project has exactly one root module.
- **Child module**: any module called from within another module using a `module` block. Child modules can be local (a subdirectory) or remote (Terraform Registry, Git, S3, etc.).

Modules solve a code-organisation problem. Without them, every environment (dev, staging, prod) would repeat the same VPC, security group, and EC2 resource definitions. Modules let you write the logic once and call it multiple times with different inputs.

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
  source  = "./modules/vpc"    # Required: where the module code lives
  version = "~> 5.0"           # Optional for local modules; required for registry modules

  # All other arguments are passed to the module as input variables
  vpc_name = "my-vpc"
  vpc_cidr = "10.0.0.0/16"
}
```

After calling a module you access its outputs via `module.<name>.<output_name>`:

```hcl
resource "aws_instance" "web" {
  subnet_id = module.vpc.public_subnet_ids[0]
}
```

### Local modules

When `source` starts with `./` or `../` Terraform treats it as a local path relative to the calling configuration:

```hcl
source = "./modules/vpc"
```

Local modules do not have a `version` argument — you control the source directly. They are ideal for splitting a large configuration into logical chunks within the same repository.

After adding or changing a local module `source`, you must run `terraform init` again for Terraform to pick up the change. Terraform copies (or symlinks) the module into `.terraform/modules/`.

### Registry modules

Modules published to [registry.terraform.io](https://registry.terraform.io) have a three-part address:

```
<namespace>/<module-name>/<provider>
```

For example: `terraform-aws-modules/vpc/aws`

```hcl
module "vpc_registry" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "my-vpc"
  cidr = "10.0.0.0/16"
  # ...
}
```

Registry modules are downloaded on `terraform init` and cached in `.terraform/modules/`. The `version` argument is **required** for registry modules — omitting it means Terraform will always download the latest version, which can break your configuration unexpectedly when the module author makes a breaking change.

### Module versioning and the `~>` operator

The `~>` (pessimistic constraint) operator pins to a minor version while allowing patch updates:

| Constraint  | Meaning                             |
|-------------|-------------------------------------|
| `= 5.1.0`   | Exactly 5.1.0, nothing else         |
| `~> 5.1`    | 5.1.x — patch updates allowed       |
| `~> 5.0`    | 5.x.x — minor + patch updates allowed |
| `>= 5.0`    | Anything from 5.0 upward (avoid)   |

For production, `~> 5.1` (pinned to minor) is safer than `~> 5.0`. For learning, `~> 5.0` is fine.

### Module outputs and encapsulation

A module's internal resources are **not visible** to the caller. The only way to get information back from a module is through declared outputs.

If you try to access an internal resource directly:

```hcl
# WRONG — this will fail
subnet_id = module.vpc.aws_subnet.public["10.0.1.0/24"].id
```

Terraform will report an error like:

```
Error: Unsupported attribute
  module.vpc does not have an attribute named "aws_subnet"
```

The correct approach is to expose the information you need via an `output` block inside the module:

```hcl
# Inside modules/vpc/outputs.tf
output "public_subnet_ids" {
  value = [for subnet in aws_subnet.public : subnet.id]
}
```

Then consume it in the root:

```hcl
subnet_id = module.vpc.public_subnet_ids[0]
```

This encapsulation is intentional. It means a module author can refactor internal implementation details without breaking callers, as long as the outputs stay the same.

### No `provider` blocks inside modules

Modules should never declare their own `provider` blocks. Providers are always configured in the root module and automatically inherited by child modules. If you put a provider in a module, you create tight coupling between the module and a specific region/account, making the module impossible to reuse.

The correct pattern is to configure the provider in the root:

```hcl
# root main.tf
provider "aws" {
  region = var.aws_region
}
```

Advanced use case: if you need to pass a different provider configuration to a module (e.g., for multi-region deployments), use the `providers` meta-argument on the `module` block. This is covered in advanced courses.

### Resource addresses in state

When Terraform creates resources through a module, the state address includes the module path:

```
module.vpc.aws_vpc.this
module.vpc.aws_subnet.public["10.0.1.0/24"]
module.vpc.aws_internet_gateway.this
```

You can see this with `terraform state list`. The root module's resources have no prefix:

```
aws_instance.web
aws_security_group.web
```

### Module composition

Modules can call other modules. A "root" module can call a "network" module, which in turn calls a "subnet" module. This is module composition. In practice, keep composition shallow (one or two levels) to maintain readability.

---

## Setup

**Prerequisites**: AWS CLI configured, Terraform >= 1.5 installed.

**Estimated cost**: VPC resources are free. One EC2 t3.nano costs ~$0.0052/hr. Destroy promptly when done.

1. Find your public IP:
   ```bash
   curl -s https://checkip.amazonaws.com
   ```

2. Create a `terraform.tfvars` file in `terraform/`:
   ```hcl
   my_ip_cidr = "YOUR.IP.HERE/32"
   ```

3. Review the module structure before running any commands:
   ```
   terraform/
     modules/
       vpc/
         variables.tf   # Module inputs
         main.tf        # VPC, subnets, IGW, route tables
         outputs.tf     # vpc_id, public_subnet_ids, etc.
     main.tf            # Root: calls the module, creates EC2
     variables.tf       # Root inputs
     outputs.tf         # Root outputs
   ```

---

## Exercises

### Exercise 1 — Read the module and trace the data flow

Before running any commands, read through the module files and answer these questions:

- `modules/vpc/variables.tf` defines `vpc_cidr`. Where is it used in `modules/vpc/main.tf`?
- `modules/vpc/outputs.tf` declares `public_subnet_ids`. How is it consumed in the root `main.tf`?
- `modules/vpc/variables.tf` has `vpc_name` with no default. What happens in `main.tf` if you do not pass `vpc_name` to the module call?

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

Note how every resource inside the module is prefixed:

```
module.vpc.aws_vpc.this                     will be created
module.vpc.aws_subnet.public["10.0.1.0/24"] will be created
module.vpc.aws_subnet.public["10.0.2.0/24"] will be created
module.vpc.aws_internet_gateway.this        will be created
```

Root resources have no module prefix:

```
aws_security_group.web   will be created
aws_instance.web         will be created
```

### Exercise 4 — Apply

```bash
terraform apply
```

Type `yes` when prompted. Apply takes ~30 seconds.

### Exercise 5 — Consume module outputs

Run each output individually:

```bash
terraform output vpc_id
terraform output public_subnet_ids
terraform output instance_public_ip
```

Now query a specific element of the subnet list using `-json` and a shell command:

```bash
terraform output -json public_subnet_ids | python3 -c "import sys,json; print(json.load(sys.stdin)[0])"
```

### Exercise 6 — Extend the module cleanly

Open `terraform/modules/vpc/variables.tf` and add a new variable at the bottom:

```hcl
variable "enable_nat_gateway" {
  description = "Reserved for future use. Not yet implemented."
  type        = bool
  default     = false
}
```

Now open `terraform/main.tf` and pass the new variable in the `module "vpc"` block:

```hcl
enable_nat_gateway = false
```

Run `terraform plan`. The plan should show **no changes**. This demonstrates the clean extension pattern: you can add new optional inputs to a module without forcing callers to update or causing resource recreation.

### Exercise 7 — Registry module (read-only demo)

Open `terraform/main.tf` and uncomment the `module "vpc_registry"` block. Run:

```bash
terraform init
```

Observe the new download step:

```
Downloading registry.terraform.io/terraform-aws-modules/vpc/aws 5.x.x...
```

Run `terraform plan` — you will see many new resources that the community module would create. **Do not apply.** Comment the block back out, then run `terraform init` again to clean up the module entry.

### Exercise 8 — Observe module encapsulation (expected failure)

Edit `terraform/main.tf` temporarily. Change the `subnet_id` in `aws_instance.web` to reference the internal resource directly:

```hcl
# Intentionally wrong — for learning only
subnet_id = module.vpc.aws_subnet.public["10.0.1.0/24"].id
```

Run `terraform plan` and read the error. Then revert the change:

```hcl
subnet_id = module.vpc.public_subnet_ids[0]
```

### Exercise 9 — Destroy

```bash
terraform destroy
```

Confirm with `yes`. Verify in the AWS Console that no resources remain.

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

Double-check in the AWS EC2 console that no instances remain running.
