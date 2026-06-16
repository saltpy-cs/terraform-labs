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
- Understand the difference between `list`, `set`, and `map` types and when to use each
- Convert between collection types with `toset()`, `tolist()`, and `tomap()`
- Flatten nested structures (`map(object({ list }))`) into a map suitable for `for_each`

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

### Collection Types: list, set, and map

Terraform has three collection types that look similar but behave differently.
Choosing the wrong one is a common source of `for_each` errors.

| Type | Ordered? | Duplicates? | Indexed by | Common use |
|------|----------|-------------|------------|------------|
| `list(T)` | Yes | Yes | Integer (`[0]`, `[1]`) | Positional sequences, `count` |
| `set(T)` | No | No | Value itself | `for_each` keys, deduplication |
| `map(T)` | No | Keys unique | String key | Named config, `for_each` |
| `object({...})` | — | — | Named attribute | Structured config with mixed types |

**Why `for_each` requires a set or map, not a list:**

```hcl
# ERROR — for_each does not accept a list
resource "google_compute_subnetwork" "bad" {
  for_each = ["dev", "staging", "prod"]  # list: Terraform refuses this
}

# CORRECT — convert to set first
resource "google_compute_subnetwork" "ok" {
  for_each = toset(["dev", "staging", "prod"])
}
```

Lists have integer indices (`[0]`, `[1]`, `[2]`). If you remove `"dev"` from position 0,
every other element shifts: what was `[1]` is now `[0]`. Terraform would see that as a
change to every resource. Sets and maps have stable, value-based keys — removing `"dev"`
only affects the `"dev"` resource.

**Sets have no guaranteed order.** In practice Terraform sorts `set(string)` values
alphabetically, but this is an implementation detail you should not rely on. If order
matters, use a list. If stability matters, use a set or map.

**`object` vs `map`:** a `map(T)` requires all values to have the same type `T`. An
`object({ name = string, count = number })` can have mixed types but the keys are fixed
at declaration time. Use `object` for structured configuration; use `map` when you need
a variable number of identically-typed values.

### Type Conversions

`toset()`, `tolist()`, and `tomap()` convert between collection types:

```hcl
# list → set: removes duplicates, loses position
toset(["b", "a", "a", "c"])
# result: {"a", "b", "c"}  (alphabetical, duplicate removed)

# set → list: materialises in (implementation-defined) order
tolist(toset(["c", "a", "b"]))
# result: ["a", "b", "c"]  (sorted alphabetically in practice)

# object → map: all values must share a type
tomap({ dev = "e2-micro", prod = "e2-small" })
# result: {"dev" = "e2-micro", "prod" = "e2-small"}
```

`keys(map)` and `values(map)` extract the two sides of a map as lists:

```hcl
keys(var.instance_config)    # ["dev", "prod", "staging"]
values({ a = 1, b = 2 })    # [1, 2]
```

### Flattening Nested Structures

The most important pattern for real-world Terraform: a variable describes a
hierarchy, but `for_each` needs a flat map with unique string keys.

**The problem:** you have `map(object({ subnets = list(string) }))` — a map of VPCs,
each containing a list of subnet CIDRs. You cannot use this directly with `for_each`
because the type is not a flat map.

**The solution — nested `for` + `merge([...]...)`:**

```hcl
variable "vpc_config" {
  type = map(object({
    cidr    = string
    subnets = list(string)
  }))
  default = {
    dev  = { cidr = "10.20.0.0/16", subnets = ["10.20.1.0/24", "10.20.2.0/24"] }
    prod = { cidr = "10.30.0.0/16", subnets = ["10.30.1.0/24", "10.30.2.0/24", "10.30.3.0/24"] }
  }
}

locals {
  all_subnets = merge([
    for vpc_name, vpc in var.vpc_config : {       # outer for: one map per VPC
      for idx, cidr in vpc.subnets :              # inner for: one entry per subnet
        "${vpc_name}-subnet-${idx}" => {          # composite key — must be unique
          vpc_name = vpc_name
          cidr     = cidr
          vpc_cidr = vpc.cidr
        }
    }
  ]...)                                           # ... spreads the list into merge()
}
```

Step through what this produces:

1. **Outer for** iterates over `vpc_config` — produces a **list of two maps**:
   ```hcl
   [
     { "dev-subnet-0"  = {...}, "dev-subnet-1"  = {...} },
     { "prod-subnet-0" = {...}, "prod-subnet-1" = {...}, "prod-subnet-2" = {...} }
   ]
   ```

2. **`merge([...]...)`** collapses the list of maps into one flat map. The `...`
   (spread operator) unpacks the list so `merge` receives each map as a separate
   argument — `merge(map1, map2)` — rather than a single list argument.

3. **Result** — a flat map with five unique keys, ready for `for_each`:
   ```hcl
   {
     "dev-subnet-0"  = { vpc_name = "dev",  cidr = "10.20.1.0/24", ... }
     "dev-subnet-1"  = { vpc_name = "dev",  cidr = "10.20.2.0/24", ... }
     "prod-subnet-0" = { vpc_name = "prod", cidr = "10.30.1.0/24", ... }
     "prod-subnet-1" = { vpc_name = "prod", cidr = "10.30.2.0/24", ... }
     "prod-subnet-2" = { vpc_name = "prod", cidr = "10.30.3.0/24", ... }
   }
   ```

Now `for_each = local.all_subnets` creates one `google_compute_subnetwork` per entry,
and the key `"prod-subnet-1"` is stable — removing `dev` only destroys the two `dev-*`
resources, leaving all `prod-*` resources untouched.

**The composite key contract:** keys must be unique across the entire flat map. A
common convention is `"<parent>-<child>"` or `"<parent>/<child>"`. Choosing a
meaningful separator helps when reading `terraform state list` output.

### `terraform console` for Testing

The `terraform console` command opens an interactive REPL that evaluates expressions against your current variable values and state:

```
$ terraform console
> [for e in ["dev","staging","prod"] : upper(e)]
[
  "DEV",
  "STAGING",
  "PROD",
]
> merge({"a"=1}, {"b"=2, "a"=99})
{
  "a" = 99
  "b" = 2
}
> exit
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

Type `exit` to quit the console.

### Exercise 2 — Conditional Apply (enable_production=false)

```bash
terraform apply -auto-approve -var='enable_production=false'
```

Expected: Terraform creates instances for `dev` and `staging` only. The `prod` instance and `google_storage_bucket.prod_data` are excluded.

This apply also creates the `google_compute_subnetwork.multi[*]` resources from `var.vpc_config`. Those subnets are a separate variable (used in exercises 10–11 to demonstrate nested structure flattening) and are not gated by `enable_production`. Note that `var.vpc_config` has `dev` and `prod` entries but no `staging` entry — the lack of a staging entry there is intentional and is covered in exercise 11.

Check the output:

```bash
terraform output enabled_environments
```

Expected:

```
[
  "dev",
  "staging",
]
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
terraform apply -auto-approve
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
[
  "dev",
  "staging",
  "prod",
]
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
Expected: `["DEV", "STAGING", "PROD"]`

**Map inversion:**
```
{for k, v in {a=1, b=2} : v => k}
```
Expected: `{ 1 = "a", 2 = "b" }`

**Filtering:**
```
[for s in ["dev", "prod"] : s if s != "prod"]
```
Expected: `["dev"]`

**join:**
```
join(", ", ["a", "b", "c"])
```
Expected: `"a, b, c"`

**flatten:**
```
flatten([[1, 2], [3, 4]])
```
Expected: `[1, 2, 3, 4]`

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

Exit the console: type `exit`.

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

Exit the console:

```
exit
```

### Exercise 8 — Inspect the Debug null_resource

Force-recreate the `null_resource.debug` to see its local-exec provisioner fire:

```bash
terraform apply -auto-approve -replace=null_resource.debug
```

In the output, look for a line from the local-exec provisioner:

```
null_resource.debug (local-exec): env_map: {"dev":{...},"prod":{...},"staging":{...}}
```

The `-replace` flag forces Terraform to destroy and recreate a specific resource, even when there are no configuration changes. It is the modern replacement for the deprecated `terraform taint` command.

This pattern — `local-exec` + `jsonencode()` — is useful for debugging complex locals during development. It prints the value of a local as JSON to stdout during `apply`. Remove it before committing production code.

### Exercise 9 — Sets vs Lists in terraform console

Open `terraform console` (you need to have applied first, or at minimum have a
`terraform.tfvars` with `gcp_project` set so variables resolve):

```bash
terraform console
```

**Part A — Observe set deduplication and ordering:**

```hcl
# A list preserves duplicates and insertion order
["staging", "dev", "dev", "prod"]

# toset() removes duplicates and sorts alphabetically
toset(["staging", "dev", "dev", "prod"])

# Back to a list: note the alphabetical order (sets have no order of their own)
tolist(toset(["staging", "dev", "dev", "prod"]))
```

**Part B — Understand why for_each refuses lists:**

```hcl
# Terraform will tell you directly:
# Error: Invalid for_each argument — a set or map is required

# Instead, always wrap a list variable in toset():
toset(var.environments)
```

**Part C — keys() and values():**

```hcl
keys(var.instance_config)
values(var.instance_config)

# Extract just the machine_type from each config object
{ for k, v in var.instance_config : k => v.machine_type }
```

**Part D — Type inspection:**

```hcl
# These look similar but are different types:
length(["a", "b", "c"])    # list — ordered
length(toset(["a","b","c"])) # set — unordered

# Object vs map: both are key/value but object has fixed keys, map is dynamic
{ name = "alice", age = 30 }          # object (mixed types ok)
tomap({ dev = "t1", prod = "t2" })   # map (all values same type)
```

Exit the console: type `exit`.

### Exercise 10 — Trace the nested flattening in console

Stay in (or reopen) `terraform console`:

```bash
terraform console
```

Trace the `all_subnets` local step by step:

```hcl
# Step 1: see the raw input — a map of objects, each containing a list
var.vpc_config

# Step 2: the outer for produces a LIST of maps (one map per VPC)
[for vpc_name, vpc in var.vpc_config : { for idx, cidr in vpc.subnets : "${vpc_name}-subnet-${idx}" => cidr }]

# Step 3: merge() collapses the list into one flat map — note the ... spread
merge([for vpc_name, vpc in var.vpc_config : { for idx, cidr in vpc.subnets : "${vpc_name}-subnet-${idx}" => cidr }]...)

# Step 4: the full local (with all fields)
local.all_subnets

# Step 5: count how many subnets were produced
length(local.all_subnets)

# Step 6: list just the keys — these become the for_each resource addresses
keys(local.all_subnets)
```

Expected from step 6 with defaults:
```
[
  "dev-subnet-0",
  "dev-subnet-1",
  "prod-subnet-0",
  "prod-subnet-1",
  "prod-subnet-2",
]
```

These keys are exactly the suffixes you'll see in `terraform state list`:
`google_compute_subnetwork.multi["dev-subnet-0"]` etc.

### Exercise 11 — Apply and inspect flattened subnets

```bash
terraform apply -auto-approve
```

The `google_compute_subnetwork.multi[*]` resources were already created in exercise 2 (they are not gated by `enable_production`). This apply adds `google_compute_instance.app["prod"]` and `google_storage_bucket.prod_data[0]` if you haven't re-applied with full production enabled since exercise 2. After apply:

```bash
# List the flattened subnet resources in state — note the stable composite keys
terraform state list | grep multi

# Inspect one entry
terraform state show 'google_compute_subnetwork.multi["prod-subnet-2"]'
```

Verify the outputs:

```bash
terraform output all_subnets_flat
terraform output subnet_names_by_vpc
terraform output env_set_vs_list
```

`subnet_names_by_vpc` inverts the structure — it groups the flat map back by VPC name
using a `for` expression with an `if` filter. Read `outputs.tf` to see how it's built.

**Stability exercise:** add a third environment to `vpc_config`:

```hcl
# In terraform.tfvars
vpc_config = {
  dev     = { cidr = "10.20.0.0/16", subnets = ["10.20.1.0/24", "10.20.2.0/24"] }
  staging = { cidr = "10.40.0.0/16", subnets = ["10.40.1.0/24"] }
  prod    = { cidr = "10.30.0.0/16", subnets = ["10.30.1.0/24", "10.30.2.0/24", "10.30.3.0/24"] }
}
```

```bash
terraform plan
```

The plan should show only **one new resource** (`staging-subnet-0`) being created.
The existing `dev-*` and `prod-*` resources are unchanged. This is key stability
property of `for_each` with composite keys — adding entries never disturbs existing ones.

Compare what would happen with a list-based approach: inserting `staging` in the middle
of a list would shift indices and Terraform would attempt to recreate every subsequent
subnet.

### Exercise 12 — Destroy

```bash
terraform destroy -auto-approve
```

Expected:

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
- `list` preserves order and allows duplicates — use with `count` or when position matters.
- `set` removes duplicates and has no guaranteed order — use as `for_each` keys when you have a list variable.
- `map` has unique string keys and no order — the natural source for `for_each`; keys become resource addresses in state.
- `toset()` is the bridge between list variables and `for_each` — the most common type conversion in Terraform.
- Nested structures (`map(object({ list }))`) cannot be used directly with `for_each`; flatten them with a nested `for` + `merge([...]...)`.
- Composite keys (`"${vpc}-subnet-${idx}"`) give `for_each` resources stable, human-readable addresses in state.

---

## Cleanup

```bash
cd lab-08-complex-expressions/terraform
terraform destroy -auto-approve
```

Verify in GCP Console that all resources are removed:

- **Compute Engine > VM instances**: no `tf-lab08` instances
- **Cloud Storage > Buckets**: no `tf-lab08-prod-data` bucket
- **VPC Network > VPC networks**: no `tf-lab08-vpc`
