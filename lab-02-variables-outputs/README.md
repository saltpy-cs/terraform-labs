# Lab 02 — Variables, Outputs, Locals, and Data Sources

## Objectives

- Define input variables with types, defaults, descriptions, and validation rules
- Mark variables as `sensitive` to suppress them from plan and output
- Compute reusable values with `locals`
- Define output values and control their sensitivity
- Use a `data` source to read existing infrastructure
- Understand the difference between `variable`, `local`, `output`, and `data`

## Concepts

### Input Variables

Variables are declared in `variable` blocks. They let callers (or the operator via
`-var` flags and `.tfvars` files) customise a configuration without editing source code.

```hcl
variable "environment" {
  type        = string
  description = "Deployment environment"
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}
```

**Types** tell Terraform how to parse and validate the value:

| Type | Example |
|------|---------|
| `string` | `"us-east-1"` |
| `number` | `3` |
| `bool` | `true` |
| `list(string)` | `["a", "b", "c"]` |
| `set(string)` | like list but unordered, no duplicates |
| `map(string)` | `{ dev = "t3.nano", prod = "t3.small" }` |
| `object({...})` | `{ name = string, port = number }` |
| `any` | no type checking |

**How values are set** (in precedence order, lowest to highest):
1. Default in `variable` block
2. `.tfvars` file passed with `-var-file=`
3. `terraform.tfvars` in working directory (auto-loaded)
4. `*.auto.tfvars` files (auto-loaded)
5. `-var` flag on command line
6. Environment variable `TF_VAR_<name>`

### Sensitive Variables

Mark a variable `sensitive = true` to prevent Terraform from showing its value in
plan output, logs, or terminal. The value is still stored in state (unencrypted) — use
a secrets manager for truly sensitive values.

```hcl
variable "db_password" {
  type      = string
  sensitive = true
}
```

### Local Values

`locals` are computed values you define once and reuse. Unlike variables, they cannot
be overridden from outside the module — they're internal.

```hcl
locals {
  name_prefix = "${var.project}-${var.environment}"
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
```

Use `local.<name>` to reference them. Good uses for locals:
- Avoid repeating the same expression (DRY principle)
- Name complex expressions so they're readable
- Compute a value once that several resources use

### Output Values

Outputs expose values after `terraform apply`. They appear in terminal output and are
accessible to other Terraform configurations via `terraform_remote_state`.

```hcl
output "bucket_name" {
  description = "The S3 bucket name"
  value       = aws_s3_bucket.main.id
}
```

Mark an output `sensitive = true` to suppress it from terminal output. It can still
be read with `terraform output -json` and is stored in state.

### Data Sources

`data` blocks read existing infrastructure that Terraform doesn't manage. The syntax
mirrors `resource`, but uses the `data` keyword:

```hcl
data "aws_region" "current" {}  # no arguments — reads the currently configured region

data "aws_vpc" "default" {
  default = true  # look up the default VPC in this account
}
```

Reference data source attributes with `data.<type>.<name>.<attribute>`:

```hcl
resource "aws_subnet" "example" {
  vpc_id = data.aws_vpc.default.id
}
```

Data sources make configurations portable — you look up IDs at plan time rather than
hardcoding them.

## Setup

No cloud credentials required for this lab. All exercises use the `random` provider.

```bash
cd lab-02-variables-outputs/terraform
terraform init
```

## Exercises

### Exercise 1 — Explore the variable definitions

Read `variables.tf`. Note:
- Which variables have defaults and which are required
- Which types are used (string, number, list, map, object)
- The validation blocks and their error messages
- Which variable is marked `sensitive`

Then try to initialise with a missing required variable:

```bash
terraform plan
# Terraform will prompt for any required variables without defaults.
# Enter any string at the prompt for app_name.
```

### Exercise 2 — Set variables via tfvars

Copy the example file and customise it:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set:
```hcl
app_name    = "my-app"
environment = "dev"
```

Now `terraform plan` uses the file automatically without prompting.

### Exercise 3 — Trigger a validation error

Test the validation rule on `environment`:

```bash
terraform plan -var='environment=production'
```

You should see:
```
│ Error: Invalid value for variable
│
│   on variables.tf line 12, in variable "environment":
│   12:     condition     = contains(["dev", "staging", "prod"], var.environment)
│
│ environment must be dev, staging, or prod.
```

Now try the numeric validation:

```bash
terraform plan -var='replica_count=0'
terraform plan -var='replica_count=11'
```

Both should fail with validation errors.

### Exercise 4 — Variable precedence

Variable precedence is highest to lowest: CLI flag > auto.tfvars > terraform.tfvars > default.

Test it:

```bash
# The terraform.tfvars sets environment=dev.
# The -var flag overrides it:
terraform plan -var='environment=staging'
```

Look at the plan output to confirm `staging` is being used, not `dev` from the tfvars file.

### Exercise 5 — Apply and inspect outputs

```bash
terraform apply
```

Review all outputs:

```bash
terraform output
terraform output -json
```

Note that the output marked `sensitive = true` shows `<sensitive>` in regular output
but its value appears in JSON output. This is intentional — outputs are always readable
via the API, just suppressed from casual display.

```bash
# Show the sensitive output value explicitly
terraform output mock_secret
```

### Exercise 6 — Locals in action

Open `locals.tf` and read through the local values. Then use `terraform console` to
evaluate expressions interactively — a very useful debugging tool:

```bash
terraform console
```

Inside the console:

```hcl
# Evaluate a local
local.name_prefix

# Evaluate a built-in function
upper("hello")
join("-", ["a", "b", "c"])
length([1, 2, 3])
merge({a = 1}, {b = 2})

# Exit
exit
```

`terraform console` loads the current state and configuration, so you can reference
any resource, variable, or local. Use it whenever you're unsure what an expression evaluates to.

### Exercise 7 — Explore the data source

The configuration includes a `data "external"` source that calls a local script to
simulate reading external data, and a `data "terraform_remote_state"` block is commented
out (covered in lab 03). Look at the simpler `data` usage in `main.tf`:

```bash
terraform state show data.external.info
```

Observe that data sources appear in state, prefixed with `data.`. They are refreshed
on every plan.

### Exercise 8 — Override a local at the expression level

Locals cannot be overridden from outside, but you can change the *variables* that feed
them. Edit `terraform.tfvars` to set `environment = "prod"`. Re-plan and observe how
the `common_tags` local (which uses `var.environment`) changes throughout the plan.

### Exercise 9 — Destroy

```bash
terraform destroy
```

This lab creates no cloud resources — destroy removes only local state tracking the
random resources.

## Key Takeaways

- Variables are the interface to a module; locals are internal implementation details
- Use validation blocks to catch bad values before Terraform even reaches the provider
- `sensitive = true` suppresses display but does NOT encrypt the value in state
- Precedence order: CLI `-var` > `.auto.tfvars` > `terraform.tfvars` > variable defaults
- `data` blocks read existing infrastructure; their attributes are available after plan
- `terraform console` is invaluable for testing expressions and functions interactively
- Commit `terraform.tfvars.example` to git; add `terraform.tfvars` to `.gitignore`

## Cleanup

```bash
terraform destroy
```

No cloud resources — no charges incurred.
