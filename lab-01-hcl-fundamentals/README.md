# Lab 01 — HCL Fundamentals

## Objectives

- Understand HCL syntax: blocks, arguments, and expressions
- Use the four core Terraform commands: `init`, `plan`, `apply`, `destroy`
- Understand what the state file is and why it exists
- Read and understand a `.terraform.lock.hcl` file
- Use the `null` and `random` providers (no cloud credentials required)

## Concepts

### HCL — HashiCorp Configuration Language

Terraform configurations are written in HCL. Everything in a `.tf` file is made up of
**blocks**. A block has a type, zero or more labels, and a body surrounded by `{}`:

```hcl
<block_type> "<label_1>" "<label_2>" {
  <argument> = <value>
}
```

The four block types you'll encounter most often:

| Block type | Labels | Purpose |
|------------|--------|---------|
| `terraform` | none | Global settings: required version, providers, backend |
| `provider` | provider name | Configure a provider (credentials, region, etc.) |
| `resource` | type, name | Declare a piece of infrastructure to manage |
| `variable` | name | Declare an input variable |
| `output` | name | Declare a value to expose after apply |
| `data` | type, name | Read existing infrastructure (not managed) |
| `locals` | none | Compute reusable local values |

### The Terraform Workflow

```
terraform init    → download providers, set up backend
terraform plan    → show what will change (does NOT apply)
terraform apply   → create/update/destroy resources to match config
terraform destroy → destroy all managed resources
```

**`terraform plan` is safe to run at any time.** It makes no changes. Get in the habit
of always reading the plan before applying.

### Providers

Providers are plugins that know how to talk to a specific API (AWS, GCP, Kubernetes,
GitHub, random number generators, etc.). They must be declared in the `terraform {}` block
and downloaded with `terraform init`.

The `null` provider creates resources that do nothing — they exist only in state. Useful
for scripting with `local-exec` provisioners or testing Terraform logic.

The `random` provider generates random values (strings, IDs, pets) that are stable across
plan/apply cycles — they're stored in state and only change when you force it.

### The State File

After `terraform apply`, Terraform writes a `terraform.tfstate` file. This is a JSON
snapshot of every resource Terraform manages. It stores:
- The resource type and name
- All the arguments you set
- All the attributes the provider returned (IDs, ARNs, generated values)

The state is how Terraform knows what currently exists so it can compute diffs on the
next `plan`. **Never edit the state file manually** — use `terraform state` subcommands
(covered in lab 03).

### The Lock File

`.terraform.lock.hcl` is created by `terraform init`. It pins the exact provider versions
and their checksums. Commit this file to git — it ensures everyone on your team (and CI)
uses the same provider versions.

```hcl
provider "registry.terraform.io/hashicorp/random" {
  version     = "3.6.3"
  constraints = "~> 3.0"
  hashes = [
    "h1:...",  # checksums for integrity verification
  ]
}
```

## Setup

No cloud credentials required. Install Terraform only:

```bash
# macOS
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Verify
terraform version
```

## Exercises

### Exercise 1 — Initialise a configuration

```bash
cd lab-01-hcl-fundamentals/terraform
terraform init
```

Observe the output:
- "Initializing provider plugins..." — Terraform reads the `required_providers` block
- "Installing hashicorp/null v3.x.x..." — provider downloaded to `.terraform/`
- A `.terraform.lock.hcl` file is created

Look at what was created:

```bash
ls -la
cat .terraform.lock.hcl
```

The `.terraform/` directory holds the downloaded provider binary. The lock file holds
checksums. The `.terraform/` dir is in `.gitignore` (re-downloadable); the lock file
should be committed (pins exact versions).

### Exercise 2 — Read the plan

```bash
terraform plan
```

Read the output carefully:

```
Terraform will perform the following actions:

  # null_resource.hello will be created
  + resource "null_resource" "hello" {
      + id       = (known after apply)
      + triggers = {
          + "name" = (known after apply)
        }
    }

  # random_pet.name will be created
  + resource "random_pet" "name" {
      + id        = (known after apply)
      + length    = 2
      + separator = "-"
    }

  # random_string.suffix will be created
  + resource "random_string" "suffix" {
      + id      = (known after apply)
      + length  = 8
      + result  = (known after apply)
      ...
    }

Plan: 3 to add, 0 to change, 0 to destroy.
```

Key observations:
- `+` means "will be created"
- `(known after apply)` means the value is determined by the provider at creation time, not during plan
- Dependencies are shown implicitly: `null_resource.hello` triggers reference `random_pet.name.id`, so `random_pet.name` will be created first
- `random_string.suffix` has no dependencies — it and `random_pet.name` can be created in parallel

### Exercise 3 — Apply the configuration

```bash
terraform apply
```

Type `yes` when prompted. Observe:
1. `random_pet.name` is created first (no dependencies)
2. `null_resource.hello` is created second (depends on the pet name)
3. The `local-exec` provisioner runs and prints `Hello, <name>`

After apply, look at the state file:

```bash
cat terraform.tfstate
```

Find the `resources` array. Each resource has:
- `type` and `name` — the resource address
- `instances[0].attributes` — every attribute the provider returned

### Exercise 4 — Change and re-apply

Open `main.tf` and change the `separator` in `random_pet.name` from `"-"` to `"_"`.

```bash
terraform plan
```

Read the plan output. You should see two resources replaced:

```
  # random_pet.name must be replaced
-/+ resource "random_pet" "name" {
      ~ id        = "old-name" -> (known after apply) # forces replacement
      ~ separator = "-" -> "_"                        # forces replacement
        length    = 2
    }

  # null_resource.hello must be replaced
-/+ resource "null_resource" "hello" {
      ~ triggers = {
          ~ "name" = "old-name" -> (known after apply) # forces replacement
        }
    }

Plan: 2 to add, 0 to change, 2 to destroy.
```

Two things to observe:
- `-/+` means Terraform will **destroy and recreate** the resource — it cannot update in place
- The replacement **cascades**: `separator` changing forces `random_pet.name` to be replaced, which generates a new `id`, which changes the `null_resource.hello` trigger, which forces that to be replaced too
- `random_string.suffix` is unchanged — it has no dependency on `random_pet.name`

```bash
terraform apply
```

Note the new pet name in the `local-exec` output.

### Exercise 5 — Inspect state commands

```bash
# List all resources in state
terraform state list

# Show full details of a resource
terraform state show random_pet.name
terraform state show null_resource.hello
```

`terraform state show` displays the resource's current state in HCL-like format. This
is your first debugging tool when a resource behaves unexpectedly.

### Exercise 6 — Output values

The configuration defines an output named `pet_name`. Retrieve it:

```bash
terraform output
terraform output pet_name
terraform output -json
```

Outputs are also stored in state. They're how you pass values between Terraform
configurations and how you display useful information after apply.

### Exercise 7 — Understand taint and replacement

The `random_pet` resource generates a name once and keeps it. To force a new name,
use `terraform taint` (deprecated) or the modern replacement:

```bash
# Tell Terraform to replace random_pet.name on the next apply
terraform apply -replace=random_pet.name
```

This forces a new random name, which cascades to the `null_resource` (since its trigger
references the pet name). Observe the chain of replacements in the plan.

### Exercise 8 — Destroy

```bash
terraform destroy
```

Type `yes`. Observe that resources are destroyed in reverse dependency order:
`null_resource.hello` first, then `random_pet.name`.

After destroy, the state file still exists but is now empty:

```bash
cat terraform.tfstate
```

You'll see `"resources": []` — the state is empty, not deleted.

## Key Takeaways

- HCL uses blocks with types, labels, and argument bodies
- `terraform init` downloads providers; always run it after adding/changing provider requirements
- `terraform plan` is safe and should always be read before applying
- `+` = create, `~` = update in-place, `-` = destroy, `-/+` = destroy and recreate
- The state file is the source of truth for what Terraform manages — never edit it directly
- Commit `.terraform.lock.hcl` to git; add `.terraform/` to `.gitignore`
- `(known after apply)` values are determined by the provider at creation time

## Cleanup

```bash
terraform destroy
```

This lab uses no cloud resources — there is nothing to pay for and no cloud cleanup needed.
