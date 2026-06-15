# Lab 06 — Advanced GCP: count, for_each, dynamic blocks, lifecycle

## Objectives

- Use `count` to create multiple GCE instances
- Use `for_each` to create multiple subnets and instances from a map
- Understand the reshuffling problem with `count` vs `for_each`
- Write `dynamic` blocks to generate repeated `allow` blocks in a firewall rule
- Use `lifecycle` meta-arguments: `create_before_destroy`, `prevent_destroy`, `ignore_changes`
- Understand how `count` and `for_each` affect resource addresses in state

---

## Concepts

### `count`

`count` is the simplest way to create multiple copies of a resource:

```hcl
resource "google_compute_instance" "web" {
  count = 3
  name  = "web-${count.index}"
  # ...
}
```

This creates three resources. Terraform addresses them by zero-based integer index:

```
google_compute_instance.web[0]
google_compute_instance.web[1]
google_compute_instance.web[2]
```

Inside the resource block, `count.index` gives the current instance's index. This is useful for naming and for writing metadata that identifies each instance.

**The reshuffling problem.** Count is fine when resources are truly identical. The problem arises when you derive `count` from a list variable and then change that list. Suppose you have:

```hcl
variable "names" { default = ["alpha", "beta", "gamma"] }

resource "google_compute_instance" "web" {
  count = length(var.names)
  name  = var.names[count.index]
}
```

The state contains `web[0]=alpha`, `web[1]=beta`, `web[2]=gamma`. If you remove `"alpha"` from the list, Terraform sees:

- `web[0]` should now be `beta` (was `alpha`) → **destroy and recreate**
- `web[1]` should now be `gamma` (was `beta`) → **destroy and recreate**
- `web[2]` no longer exists → **destroy**

Three resources are affected even though only one was removed. This is the reshuffling problem.

### `for_each`

`for_each` creates one resource per entry in a map or set. Resources are addressed by their key, not an index:

```hcl
resource "google_compute_instance" "env" {
  for_each     = { dev = "e2-micro", staging = "e2-micro" }
  machine_type = each.value
  name         = each.key
}
```

State addresses:

```
google_compute_instance.env["dev"]
google_compute_instance.env["staging"]
```

If you remove `"dev"` from the map, only `google_compute_instance.env["dev"]` is destroyed. `google_compute_instance.env["staging"]` is untouched — no reshuffling.

Inside the resource block, `each.key` gives the map key and `each.value` gives the corresponding value.

`for_each` accepts:
- A `map` — each entry becomes a resource, keyed by the map key
- A `set(string)` — each entry becomes a resource, keyed by the string value itself

`for_each` does **not** accept a plain `list`. Use `toset()` to convert a list of unique strings, or use a map.

### When to use `count` vs `for_each`

| Situation | Use |
|-----------|-----|
| Resources are truly identical (e.g. 3 worker nodes) | `count` |
| Resources differ in name, config, or placement | `for_each` |
| Derived from a list that might change order | `for_each` (with `toset` or map conversion) |
| You need to reference a single instance by a meaningful name | `for_each` |

In practice, `for_each` is almost always the better choice for production infrastructure. `count` can cause unintended resource recreation that is easy to miss in a plan.

### `dynamic` blocks

Many Terraform resources contain nested blocks that can repeat. The `allow` block in `google_compute_firewall` is a common example. Without `dynamic`, you must write one block per rule:

```hcl
allow { protocol = "tcp"; ports = ["22"] }
allow { protocol = "tcp"; ports = ["80"] }
allow { protocol = "tcp"; ports = ["443"] }
```

With a `dynamic` block, you drive the repetition from a variable:

```hcl
dynamic "allow" {
  for_each = var.firewall_rules
  iterator = rule   # Optional: names the loop variable. Defaults to the block label.

  content {
    protocol = rule.value.protocol
    ports    = [rule.value.port]
  }
}
```

The `content {}` block defines what each generated nested block looks like. Inside `content`, use `<iterator>.value` to access the current item and `<iterator>.key` for the index or map key.

Adding a new entry to `var.firewall_rules` generates a new `allow` block automatically without any structural code change.

`dynamic` blocks work wherever a resource accepts repeated nested blocks: `allow`/`deny` in firewall rules, `disk` on instances, `autoscaling_policy` in autoscalers, and many others.

### `lifecycle` meta-argument

The `lifecycle` block modifies how Terraform manages the create/update/destroy cycle for a resource. It is a meta-argument — it applies to any resource type.

#### `create_before_destroy = true`

By default, when Terraform needs to replace a resource (because an immutable attribute changed), it destroys the existing resource first, then creates the new one. For zero-downtime deployments this order is wrong.

```hcl
resource "google_compute_instance" "web" {
  # ...
  lifecycle {
    create_before_destroy = true
  }
}
```

With `create_before_destroy = true`, Terraform creates the replacement first, then destroys the original. Note: the new and old resources will exist simultaneously for a brief period, so they must not conflict on unique constraints (e.g., fixed static IP addresses).

#### `prevent_destroy = true`

Causes Terraform to error if a plan would destroy the resource:

```hcl
resource "google_compute_network" "main" {
  # ...
  lifecycle {
    prevent_destroy = true
  }
}
```

```
Error: Instance cannot be destroyed
  Resource google_compute_network.main has lifecycle.prevent_destroy set, but
  the plan calls for this resource to be destroyed.
```

Use this for stateful resources where accidental deletion is catastrophic: databases, storage buckets with data, KMS keys. To actually destroy the resource, you must first remove the `prevent_destroy = true` line.

`prevent_destroy` does not protect against `terraform destroy` of a config that still contains the block (it blocks the plan phase, but only for changes that would implicitly destroy the resource). It does not stop `terraform state rm`.

#### `ignore_changes`

Tells Terraform to ignore drift on specific attributes. After the resource is created, Terraform will never modify the listed attributes, even if the real resource diverges from the configuration.

```hcl
resource "google_compute_instance" "env" {
  # ...
  lifecycle {
    ignore_changes = [metadata["startup-time"]]
  }
}
```

Common use cases:
- Metadata keys written by the instance at boot or by external systems
- Labels written by GCP services (e.g. GKE node labels)
- `desired_size` on instance groups managed by an autoscaler

`ignore_changes = all` is available but should be used sparingly — it effectively turns off drift detection for the entire resource.

### Resource addresses with `count` and `for_each`

Resource addresses are used in:

- `terraform state list` output
- `terraform state rm <address>` for manual state surgery
- `terraform import <address> <id>` to import existing resources
- `-target=<address>` for targeted applies

```bash
# count — integer index in square brackets
terraform state show 'google_compute_instance.web[0]'
terraform state rm 'google_compute_instance.web[2]'

# for_each — string key in square brackets (note the quotes inside)
terraform state show 'google_compute_instance.env["dev"]'
terraform state rm 'google_compute_instance.env["staging"]'
```

---

## Setup

**Prerequisites**: `gcloud` CLI installed, Terraform >= 1.5 installed.

**Authentication**: Run `gcloud auth application-default login` once before using Terraform.

**Estimated cost**: 3x GCE e2-micro. The first is free tier in `us-central1`; the other two are approximately $0.02/hr combined. Destroy promptly when done.

1. Authenticate with GCP:
   ```bash
   gcloud auth application-default login
   ```

2. Create `terraform/terraform.tfvars`:
   ```hcl
   gcp_project = "YOUR-PROJECT-ID"
   ```

---

## Exercises

### Exercise 1 — Inspect the dynamic block and add a rule

Open `terraform/main.tf` and find `google_compute_firewall.combined`. Trace how `var.firewall_rules` flows into the `dynamic "allow"` block.

Now open `terraform/variables.tf` and add a fourth rule to the `firewall_rules` default:

```hcl
{ port = "8080", protocol = "tcp", description = "Alt HTTP" },
```

Run `terraform plan` (before applying). The plan should show only the firewall rule updating — one new `allow` block is added. No instances or subnets should change. Revert the change before continuing.

### Exercise 2 — Apply

```bash
cd terraform
terraform init
terraform apply
```

Type `yes` when prompted. This creates the VPC, two environment subnets, one combined firewall rule, 3 count-based instances, and 2 for_each-based instances.

### Exercise 3 — Observe resource addresses in state

```bash
terraform state list
```

Identify the different address formats:

- `google_compute_instance.web[0]`, `[1]`, `[2]` — count, integer indices
- `google_compute_instance.env["dev"]`, `["staging"]` — for_each, string keys
- `google_compute_subnetwork.env["dev"]`, `["staging"]` — also for_each

Inspect specific resources:

```bash
terraform state show 'google_compute_instance.web[0]'
terraform state show 'google_compute_instance.env["dev"]'
```

### Exercise 4 — Demonstrate count reshuffling vs for_each stability

**Part A — count (removing the last item is safe):**

Edit `terraform/terraform.tfvars`:

```hcl
instance_count = 2
```

Run `terraform plan`. Only `google_compute_instance.web[2]` is destroyed. The plan correctly removes only the last instance — no reshuffling because you removed from the end.

Apply the change, then restore `instance_count = 3` and apply again.

**Part B — for_each (removing any item is safe):**

Edit `terraform/variables.tf`. In the `environments` default, remove the `dev` entry (leave only `staging`). Run `terraform plan`.

Observe that only `google_compute_instance.env["dev"]` and `google_compute_subnetwork.env["dev"]` are destroyed. `google_compute_instance.env["staging"]` has no planned changes — no reshuffling, no matter which key you remove.

Revert the change to `variables.tf` before continuing.

### Exercise 5 — `prevent_destroy` in action

Open `terraform/main.tf`. Find `google_compute_network.main` and uncomment the lifecycle block:

```hcl
lifecycle {
  prevent_destroy = true
}
```

Apply the change (no resource changes, just the block being added to config). Now try:

```bash
terraform destroy
```

Terraform will error before making any changes:

```
Error: Instance cannot be destroyed
  Resource google_compute_network.main has lifecycle.prevent_destroy set...
```

Comment the lifecycle block back out and apply again to restore the normal state:

```bash
terraform apply
```

### Exercise 6 — `ignore_changes` and external drift

This exercise requires the `gcloud` CLI.

**Part A — with `ignore_changes` active:**

The `google_compute_instance.env` resource already has `ignore_changes = [metadata["startup-time"]]` in `main.tf`.

Add a metadata entry to one of the env instances manually:

```bash
gcloud compute instances add-metadata tf-lab06-dev \
  --metadata startup-time="$(date)" \
  --zone us-central1-a
```

Run `terraform plan`. The plan should show **no changes** — Terraform ignores the `startup-time` metadata key.

**Part B — without `ignore_changes`:**

Open `terraform/main.tf`. In `google_compute_instance.env`, comment out the `ignore_changes` line:

```hcl
lifecycle {
  # ignore_changes = [metadata["startup-time"]]
}
```

Run `terraform plan`. Now Terraform wants to remove the `startup-time` metadata entry because it was not in the configuration. This is the behaviour `ignore_changes` prevents. Uncomment the line and restore the config.

### Exercise 7 — Destroy

```bash
terraform destroy
```

Confirm with `yes`.

---

## Key Takeaways

- Prefer `for_each` over `count` for non-identical resources. `count` reshuffling causes unexpected resource recreation when items are added or removed from the middle of a list.
- `for_each` resources are addressed by string keys (`["dev"]`). `count` resources are addressed by integer indices (`[0]`, `[1]`).
- `dynamic` blocks replace repetitive nested blocks with a data-driven loop. They work wherever a resource accepts repeated nested blocks — `allow` in firewall rules, `disk` on instances, and many others.
- `create_before_destroy = true` is essential for zero-downtime replacements — new resource is created before the old one is destroyed.
- `prevent_destroy = true` is a safeguard for stateful resources. It blocks implicit plan-time destruction but does not stop `state rm` or direct API calls.
- `ignore_changes` handles legitimate external drift. Use it surgically on specific attributes, not `ignore_changes = all`.

---

## Cleanup

```bash
cd terraform
terraform destroy
```

Verify in the GCP Console (Compute Engine) that no instances, networks, or firewall rules remain.
