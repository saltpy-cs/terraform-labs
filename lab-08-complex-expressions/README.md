# Lab 08 — Complex Expressions

## Objectives

By the end of this lab you will be able to:

- Use `for` expressions to transform lists and maps
- Use splat expressions (`[*]`) and understand when to use `for` instead
- Use the `templatefile()` function to render scripts with variables
- Write conditional expressions (ternary operator) to toggle resources
- Use built-in functions: `join`, `split`, `flatten`, `merge`, `lookup`, `length`, `toset`, `tomap`
- Compose complex `locals` blocks from these primitives
- Use `terraform console` to test expressions interactively

**Estimated cost:** Three EC2 t3.nano instances (~$0.0052/hr each). Destroy promptly. Total for a one-hour lab: ~$0.02.

---

## Concepts

### `for` Expressions

A `for` expression transforms a collection. It comes in two forms:

**List form** (square brackets → returns a list):
```hcl
[for item in var.servers : upper(item.name)]
```

**Map form** (curly braces + `=>` → returns a map):
```hcl
{for k, v in var.configs : k => v.instance_type}
```

You can filter with an `if` clause:
```hcl
[for s in var.servers : s.name if s.enabled]
```

Iterating over a map gives you both key and value:
```hcl
[for k, v in var.tags : "${k}=${v}"]
```

`for` expressions are evaluated at plan time — they operate on values known to Terraform before any API calls are made.

### Splat Expressions

Splat is a shorthand for a common `for` pattern. It only works on resources managed with `count`:

```hcl
# These two are equivalent for count-based resources:
aws_instance.web[*].id
[for i in aws_instance.web : i.id]
```

**Important limitation:** Splat does not work on `for_each` resources. For `for_each` resources, always use a `for` expression:

```hcl
# for_each resource — must use for expression
[for k, v in aws_instance.app : v.id]

# This would be a syntax error or return unexpected results:
# aws_instance.app[*].id  ← do NOT use splat with for_each
```

### `templatefile()` Function

`templatefile(path, vars)` reads a file and substitutes `${varname}` placeholders:

```hcl
user_data = templatefile("${path.module}/templates/init.sh.tpl", {
  env     = var.environment
  project = var.project_name
})
```

The template file uses standard HCL interpolation syntax:
```bash
#!/bin/bash
echo "Starting ${project} in ${env}" >> /var/log/init.log
```

`templatefile()` is preferred over `file()` + string interpolation because it keeps scripts in separate files (easier to edit, syntax-highlight, and test), and it fails at plan time if a referenced variable is missing.

### Conditional Expressions

The ternary operator: `condition ? true_value : false_value`

```hcl
# Toggle a resource with count
resource "aws_instance" "prod_only" {
  count = var.enable_production ? 1 : 0
  ...
}

# Select a value based on a condition
instance_type = var.environment == "prod" ? "t3.small" : "t3.nano"

# Handle null/optional values
subnet_id = var.custom_subnet_id != null ? var.custom_subnet_id : aws_subnet.default.id
```

When `count = 0`, Terraform creates no instances of the resource. When `count = 1`, it creates one. This is the standard pattern for optional resources.

### Built-in Functions

Terraform has a rich standard library. Key functions for data transformation:

| Function | What it does | Example |
|---|---|---|
| `join(sep, list)` | Joins list elements into a string | `join(", ", ["a","b"])` → `"a, b"` |
| `split(sep, str)` | Splits a string into a list | `split(",", "a,b")` → `["a","b"]` |
| `flatten(list_of_lists)` | Flattens nested lists | `flatten([[1,2],[3]])` → `[1,2,3]` |
| `merge(map1, map2)` | Merges maps; map2 wins on conflict | `merge({a=1},{a=2,b=3})` → `{a=2,b=3}` |
| `lookup(map, key, default)` | Safe map access with default | `lookup(m, "x", "none")` |
| `length(val)` | Count of list/map/string elements | `length(["a","b"])` → `2` |
| `toset(list)` | Converts list to set (removes duplicates) | `toset(["a","a","b"])` → `{"a","b"}` |
| `tomap(object)` | Converts object to map | used with `for_each` |
| `upper(str)` | Uppercase string | `upper("dev")` → `"DEV"` |
| `format(fmt, ...)` | Printf-style formatting | `format("%s-%d", "x", 1)` |

### Composing `locals`

`locals` blocks are the primary place to compose these functions into meaningful values:

```hcl
locals {
  # Derived from variables — computed once, referenced many times
  enabled_envs = [for e in var.environments : e if e != "prod" || var.enable_production]
  
  # Build a map for for_each
  instance_map = {for e in local.enabled_envs : e => var.instance_config[e]}
  
  # Merge base tags with computed tags
  common_tags = merge(var.base_tags, {
    managed_by = "terraform"
    project    = var.project_name
  })
}
```

Locals are not re-evaluated — they are computed once during planning and reused. This makes complex expressions fast and their values inspectable via `terraform console`.

### Using `terraform console` for Testing

The `terraform console` command opens an interactive REPL for evaluating expressions against your current state and variable values:

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

This is invaluable for debugging complex expressions before committing them to configuration files.

### Dynamic Blocks

For resources that have repeating nested blocks, `dynamic` generates them from a collection:

```hcl
resource "aws_security_group" "web" {
  dynamic "ingress" {
    for_each = var.allowed_ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
}
```

`for_each` in a `dynamic` block iterates over a list or map. The loop variable is `<block_name>.value` (for lists) or `<block_name>.key` / `<block_name>.value` (for maps).

---

## Setup

### Prerequisites

- Terraform >= 1.6 installed
- AWS CLI configured (`aws configure` or environment variables)
- An AWS account with permissions to create EC2, VPC, and IAM resources

### Configure Variables

```bash
cd lab-08-complex-expressions/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
- Set `my_ip_cidr` to your current public IP: `$(curl -s ifconfig.me)/32`
- Optionally adjust `project_name` or `aws_region`

---

## Exercises

### Exercise 1 — Read and Trace the Locals

Open `terraform/locals.tf` and trace how each local value is built:

1. `enabled_envs` — which variable controls whether prod is included?
2. `instance_names` — what does the resulting list look like if all three environments are enabled?
3. `env_map` — what is the structure of this map? What are the keys and values?
4. `common_tags` — how does `merge()` work here?
5. `security_group_rules` — what is each element of this list?

Write down the expected value of each local before running `terraform console` to verify.

### Exercise 2 — Conditional Apply (enable_production=false)

```bash
terraform init
terraform apply -var='my_ip_cidr=0.0.0.0/0' -var='enable_production=false'
```

Type `yes` when prompted.

Expected: plan creates instances for `dev` and `staging` only — the `prod` instance is excluded because `enable_production=false`.

Observe the output:
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

The `prod` environment is absent.

### Exercise 3 — Re-apply with Production Enabled

```bash
terraform apply -var='my_ip_cidr=0.0.0.0/0'
```

(The default `enable_production=true` is used now.)

Expected: plan adds the `prod` instance. Observe:
```
# aws_instance.app["prod"] will be created
```

After apply:
```bash
terraform output enabled_environments
```

Expected:
```
tolist([
  "dev",
  "staging",
  "prod",
])
```

### Exercise 4 — Inspect Template Rendering

View the template source:
```bash
cat templates/userdata.sh.tpl
```

Find the rendered (base64-encoded) user_data in state:
```bash
terraform state show 'aws_instance.app["dev"]' | grep user_data
```

Decode it:
```bash
terraform state show 'aws_instance.app["dev"]' | grep "user_data " | awk '{print $3}' | base64 -d
```

Expected output (the rendered template with `dev` substituted):
```bash
#!/bin/bash
# Provisioned by Terraform — do not edit manually
ENV="dev"
PROJECT="tf-lab08"
echo "Starting tf-lab08 in dev environment" >> /var/log/startup.log
yum install -y httpd
systemctl start httpd
echo "<h1>tf-lab08 - dev</h1>" > /var/www/html/index.html
```

Notice how `${env}` and `${project}` were replaced with actual values at plan time by `templatefile()`.

### Exercise 5 — Interactive `terraform console`

Open the console:
```bash
terraform console
```

Evaluate these expressions one by one. Predict the output before pressing Enter:

**List transformation:**
```
[for e in ["dev", "staging", "prod"] : upper(e)]
```
Expected: `tolist(["DEV", "STAGING", "PROD"])`

**Map inversion:**
```
{for k, v in {"a": 1, "b": 2} : v => k}
```
Expected: `{ 1 = "a", 2 = "b" }`

**Filtering:**
```
[for s in ["dev", "prod"] : s if s != "prod"]
```
Expected: `tolist(["dev"])`

**Using merge:**
```
merge({"env": "dev", "owner": "alice"}, {"owner": "bob", "project": "labs"})
```
Expected: `{ "env" = "dev", "owner" = "bob", "project" = "labs" }` — `bob` wins because it came second.

**flatten:**
```
flatten([["a", "b"], ["c"], ["d", "e"]])
```
Expected: `tolist(["a", "b", "c", "d", "e"])`

**toset (removes duplicates):**
```
toset(["dev", "dev", "staging", "prod", "staging"])
```
Expected: `toset(["dev", "prod", "staging"])`

Exit the console with `Ctrl+D`.

### Exercise 6 — Splat vs `for` Expression

The instances in this lab use `for_each`, not `count`. This means splat syntax does not apply to them.

Open `terraform console` again and try:
```
[for k, v in aws_instance.app : v.id]
```
Expected: a list of instance IDs (one per environment).

Now inspect what the `instance_ids` output looks like (a map, not a list):
```bash
terraform output instance_ids
```

Expected (a map keyed by environment name):
```
{
  "dev"     = "i-0abc123..."
  "prod"    = "i-0def456..."
  "staging" = "i-0ghi789..."
}
```

The `for` expression in `outputs.tf` produces a map, which is more useful than a list because you can look up by environment name.

### Exercise 7 — Inspect the Debug Output

The configuration includes a `null_resource` that echoes the `env_map` local to stdout during apply. Check the Terraform output from Exercise 3 — you should see a line like:

```
null_resource.debug (local-exec): {"dev":{...},"prod":{...},"staging":{...}}
```

This pattern (`local-exec` + `jsonencode()`) is useful for debugging complex locals during development. Remove it before committing to production code.

### Exercise 8 — Destroy

```bash
terraform destroy -var='my_ip_cidr=0.0.0.0/0'
```

Type `yes`. Expected:
```
Destroy complete! Resources: X destroyed.
```

---

## Key Takeaways

- **`for` expressions** are the primary tool for transforming data in Terraform. Use list form `[for ...]` when you need a list; use map form `{for ... => ...}` when you need a map.
- **Filtering with `if`** inside a `for` expression is how you conditionally include elements.
- **Splat (`[*]`)** only works on `count`-based resources. For `for_each` resources, use a `for` expression.
- **`templatefile()`** externalises scripts from HCL, making them easier to edit and test. Variables are substituted at plan time.
- **Conditional expressions** (`condition ? true_val : false_val`) drive feature flags via `count = var.enable_x ? 1 : 0`.
- **Use `terraform console`** to test expressions interactively — it evaluates against real state and variable values without modifying anything.
- **`locals` blocks** are the right place to compose complex derived values. Define once, reference many times.

---

## Cleanup

```bash
terraform destroy -var='my_ip_cidr=0.0.0.0/0'
```

Verify in AWS Console that no `tf-lab08` EC2 instances remain.
