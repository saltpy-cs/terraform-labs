# Lab 08 — Complex Expressions (GCP)

## Objectives

By the end of this lab you will be able to:

- Use `for` expressions to transform lists and maps
- Use splat expressions (`[*]`) and understand when to use `for` instead
- Use the `templatefile()` function to render startup scripts with variables
- Write conditional expressions (ternary operator) to toggle resources on and off
- Use built-in functions: `join`, `split`, `flatten`, `merge`, `lookup`, `length`, `toset`, `tomap`
- Compose complex `locals` blocks from these primitives
- Use `terraform console` to test expressions interactively

**Estimated cost:** GCE e2-micro instances (~$0.00 for the first under GCP Always Free; < $0.02/hr for additional instances). Destroy promptly after the lab.

---

## Concepts

### `for` Expressions

A `for` expression transforms a collection. It comes in two forms:

**List form** (square brackets — returns a list):
```hcl
[for item in var.servers : upper(item.name)]
```

**Map form** (curly braces + `=>` — returns a map):
```hcl
{for k, v in var.configs : k => v.machine_type}
```

You can filter with an `if` clause:
```hcl
[for s in var.servers : s.name if s.enabled]
```

Iterating over a map gives you both key and value:
```hcl
[for k, v in var.labels : "${k}=${v}"]
```

`for` expressions are evaluated at plan time — they operate on values Terraform knows before any API calls.

### Filtering with `if`

The `if` clause inside a `for` expression conditionally excludes elements:

```hcl
enabled_envs = [
  for env in var.environments : env
  if env != "prod" || var.enable_production
]
```

This keeps all non-prod environments unconditionally, and includes `prod` only when `enable_production` is true.

### Splat Expressions

Splat is shorthand for a common `for` pattern. It only works on `count`-based resources:

```hcl
# Equivalent for count-based resources:
google_compute_instance.web[*].id
[for i in google_compute_instance.web : i.id]
```

**Critical limitation:** Splat does **not** work on `for_each` resources. For `for_each` resources, always use a `for` expression:

```hcl
# for_each resource — must use for expression
[for k, v in google_compute_instance.app : v.id]

# This returns unexpected results with for_each — do NOT use:
# google_compute_instance.app[*].id
```

### `templatefile()` Function

`templatefile(path, vars)` reads a file and substitutes `${varname}` placeholders at plan time:

```hcl
metadata_startup_script = templatefile("${path.module}/../templates/startup.sh.tpl", {
  env     = each.key
  project = var.project_name
})
```

The template file uses HCL interpolation syntax:

```bash
#!/bin/bash
echo "Starting ${project} in ${env}" >> /var/log/startup.log
```

`templatefile()` fails at plan time if a referenced variable is missing from the `vars` map. This is safer than string interpolation on a raw `file()` read.

### Conditional Expressions

The ternary operator: `condition ? true_value : false_value`

```hcl
# Toggle a resource with count
resource "google_storage_bucket" "prod_data" {
  count = var.enable_production ? 1 : 0
  ...
}

# Reference a conditional resource (always index with [0])
output "prod_bucket" {
  value = var.enable_production ? google_storage_bucket.prod_data[0].name : "not created"
}
```

When `count = 0`, Terraform creates no instances of the resource. When `count = 1`, it creates exactly one.

### Dynamic Blocks

For resources that have repeating nested blocks, `dynamic` generates them from a collection:

```hcl
resource "google_compute_firewall" "main" {
  dynamic "allow" {
    for_each = local.firewall_allow_rules
    content {
      protocol = allow.value.protocol
      ports    = [allow.value.port]
    }
  }
}
```

`for_each` in a `dynamic` block iterates over a list or map. The loop variable is `<block_name>.value` for lists and `<block_name>.key` / `<block_name>.value` for maps.

### Built-in Functions

| Function | What it does | Example |
|---|---|---|
| `join(sep, list)` | Joins list elements into a string | `join(", ", ["a","b"])` → `"a, b"` |
| `split(sep, str)` | Splits a string into a list | `split(",", "a,b")` → `["a","b"]` |
| `flatten(list_of_lists)` | Flattens nested lists one level | `flatten([[1,2],[3]])` → `[1,2,3]` |
| `merge(map1, map2)` | Merges maps; later maps win on conflict | `merge({a=1},{a=2,b=3})` → `{a=2,b=3}` |
| `lookup(map, key, default)` | Safe map access with fallback | `lookup(m, "x", "none")` |
| `length(val)` | Count of list/map/string elements | `length(["a","b"])` → `2` |
| `toset(list)` | Converts list to set (removes duplicates, stable keys for `for_each`) | `toset(["a","a","b"])` → `{"a","b"}` |
| `tomap(object)` | Converts object to map | useful with `for_each` |
| `upper(str)` | Uppercase | `upper("dev")` → `"DEV"` |
| `jsonencode(val)` | Serialises any value to JSON string | useful for debugging locals |

### Composing `locals`

`locals` blocks are the right place to compose complex derived values. They are computed once at plan time and can be referenced anywhere:

```hcl
locals {
  enabled_envs = [for e in var.environments : e if e != "prod" || var.enable_production]
  env_map      = {for e in local.enabled_envs : e => var.instance_config[e]}
  common_labels = merge(var.base_labels, { managed_by = "terraform" })
}
```

Define once; reference many times. Inspect them with `terraform console`.

### `terraform console` for Testing

The `terraform console` command opens an interactive REPL that evaluates expressions against your current variable values and state:

```
$ terraform console
> [for e in ["dev","staging","prod"] : upper(e)]
tolist([
  "DEV",
  "STAGING",
  "PROD",
])
> merge({"a"=1}, {"b"=2, "a"=99})
{
  "a" = 99
  "b" = 2
}
> ^D
```

This is invaluable for debugging complex expressions before committing them to `.tf` files. It does not modify state.

---

## Setup

### Prerequisites

- Terraform >= 1.5 installed
- `gcloud` CLI installed and initialised (`gcloud init`)
- A GCP project with billing enabled

### Authenticate with GCP

```bash
gcloud auth application-default login
```

### Configure Variables

```bash
cd lab-08-complex-expressions/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
gcp_project       = "your-actual-project-id"
gcp_region        = "us-central1"
gcp_zone          = "us-central1-a"
project_name      = "tf-lab08"
enable_production = true
```

---

## Exercises

### Exercise 1 — Read and Trace the Locals

Open `terraform/locals.tf` and trace how each local is built from variables. Before running anything, write down what you expect each local to contain when all three environments are enabled.

1. `enabled_envs` — which variable controls whether `prod` is included?
2. `instance_names` — what does the resulting list look like with all three envs?
3. `env_map` — what are the keys? What are the values?
4. `common_labels` — how does `merge()` work here?
5. `firewall_allow_rules` — what is each element of this list?

After you have written down your predictions, initialise Terraform and open the console to verify:

```bash
terraform init
terraform console
```

In the console, evaluate (after a `terraform.tfvars` is in place):

```
local.enabled_envs
local.instance_names
local.env_map
local.firewall_allow_rules
```

Type `Ctrl+D` to exit.

### Exercise 2 — Conditional Apply (enable_production=false)

```bash
terraform apply -var='enable_production=false'
```

Type `yes` when prompted. Expected: Terraform creates instances for `dev` and `staging` only. The `prod` instance and `google_storage_bucket.prod_data` are excluded.

Check the output:

```bash
terraform output enabled_environments
```

Expected:

```
tolist([
  "dev",
  "staging",
])
```

Check the prod bucket output:

```bash
terraform output prod_bucket
```

Expected:

```
"not created"
```

### Exercise 3 — Re-apply with Production Enabled

```bash
terraform apply
```

(The default `enable_production=true` from `terraform.tfvars` is used.)

Expected: Terraform adds the `prod` instance and `google_storage_bucket.prod_data[0]`.

Look for these lines in the plan:

```
# google_compute_instance.app["prod"] will be created
# google_storage_bucket.prod_data[0] will be created
```

After apply:

```bash
terraform output enabled_environments
terraform output prod_bucket
```

Expected:

```
tolist([
  "dev",
  "staging",
  "prod",
])
"tf-lab08-prod-data-xxxxxxxx"
```

### Exercise 4 — Inspect the Startup Script

View the template source:

```bash
cat ../templates/startup.sh.tpl
```

Inspect the rendered startup script for the `dev` instance in state:

```bash
terraform state show 'google_compute_instance.app["dev"]' | grep -A5 metadata_startup_script
```

The `metadata_startup_script` attribute will show the rendered content with `${env}` and `${project}` replaced by `dev` and `tf-lab08`. This substitution happens at plan time when `templatefile()` is evaluated.

### Exercise 5 — `terraform console` Session

Open the console (with `terraform.tfvars` in place):

```bash
terraform console
```

Evaluate these expressions. Predict the output before pressing Enter each time.

**List transformation:**
```
[for e in ["dev", "staging", "prod"] : upper(e)]
```
Expected: `tolist(["DEV", "STAGING", "PROD"])`

**Map inversion:**
```
{for k, v in {a=1, b=2} : v => k}
```
Expected: `{ 1 = "a", 2 = "b" }`

**Filtering:**
```
[for s in ["dev", "prod"] : s if s != "prod"]
```
Expected: `tolist(["dev"])`

**join:**
```
join(", ", ["a", "b", "c"])
```
Expected: `"a, b, c"`

**flatten:**
```
flatten([[1, 2], [3, 4]])
```
Expected: `tolist([1, 2, 3, 4])`

**merge (later map wins on conflict):**
```
merge({owner = "alice", env = "dev"}, {owner = "bob", project = "labs"})
```
Expected: `{ "env" = "dev", "owner" = "bob", "project" = "labs" }`

**toset (removes duplicates; stable keys for for_each):**
```
toset(["dev", "dev", "staging", "prod", "staging"])
```
Expected: `toset(["dev", "prod", "staging"])`

Exit with `Ctrl+D`.

### Exercise 6 — for_each Resources and Outputs

```bash
terraform output instance_ids
```

Expected (a map keyed by environment name):

```
{
  "dev"     = "projects/your-project/zones/us-central1-a/instances/tf-lab08-dev"
  "prod"    = "projects/your-project/zones/us-central1-a/instances/tf-lab08-prod"
  "staging" = "projects/your-project/zones/us-central1-a/instances/tf-lab08-staging"
}
```

The `for` expression in `outputs.tf` that produces this is:

```hcl
{ for k, v in google_compute_instance.app : k => v.id }
```

The map is more useful than a list because you can look up by environment name, not just numeric index.

### Exercise 7 — Splat vs `for` Expression

The instances in this lab use `for_each`, not `count`. Splat syntax is not valid for `for_each` resources.

Open `terraform console` and verify:

```
[for k, v in google_compute_instance.app : v.id]
```

Expected: a list of instance IDs (one per environment).

Now contrast with a hypothetical count-based resource. If `google_compute_instance.app` had used `count = 3`, you could write:

```hcl
google_compute_instance.app[*].id
```

But with `for_each`, the `[*]` splat does not work as expected — use a `for` expression instead. This is an important distinction to internalise.

### Exercise 8 — Inspect the Debug null_resource

During the apply in Exercise 3, look back at the Terraform output. You should see a line from the `null_resource.debug` local-exec provisioner:

```
null_resource.debug (local-exec): env_map: {"dev":{...},"prod":{...},"staging":{...}}
```

This pattern — `local-exec` + `jsonencode()` — is useful for debugging complex locals during development. It prints the value of a local as JSON to stdout during `apply`. Remove it before committing production code.

### Exercise 9 — Destroy

```bash
terraform destroy
```

Type `yes`. Expected:

```
Destroy complete! Resources: X destroyed.
```

Verify the instances are gone:

```bash
gcloud compute instances list
```

No `tf-lab08` entries should appear.

---

## Key Takeaways

- `for` expressions are the primary tool for transforming data. Use list form `[for ...]` for lists and map form `{for ... => ...}` for maps.
- Filtering with `if` inside a `for` expression conditionally excludes elements — this is how `enabled_envs` works.
- Splat (`[*]`) only works on `count`-based resources. For `for_each` resources, always use a `for` expression.
- `templatefile()` externalises scripts from HCL, making them easier to edit and test. Variables are substituted at plan time and the function fails fast if a variable is missing.
- Conditional expressions (`condition ? true_val : false_val`) drive feature flags via `count = var.enable_x ? 1 : 0`.
- Use `terraform console` to test and debug expressions interactively — it evaluates against real state and variable values without modifying anything.
- `locals` blocks are the right place to compose derived values. Define once; reference many times.

---

## Cleanup

```bash
cd lab-08-complex-expressions/terraform
terraform destroy
```

Verify in GCP Console that all resources are removed:

- **Compute Engine > VM instances**: no `tf-lab08` instances
- **Cloud Storage > Buckets**: no `tf-lab08-prod-data` bucket
- **VPC Network > VPC networks**: no `tf-lab08-vpc`
