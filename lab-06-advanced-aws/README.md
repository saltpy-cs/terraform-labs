# Lab 06 — Advanced AWS: count, for_each, dynamic blocks, lifecycle

## Objectives

- Use `count` to create multiple instances of a resource
- Use `for_each` to create resources from a map or set, with meaningful keys
- Understand the difference between `count` and `for_each` and when to use each
- Write `dynamic` blocks to generate repeated nested blocks from a list
- Use `lifecycle` meta-argument: `create_before_destroy`, `prevent_destroy`, `ignore_changes`
- Understand how `count` and `for_each` affect resource addresses in state

---

## Concepts

### `count`

`count` is the simplest way to create multiple copies of a resource:

```hcl
resource "aws_instance" "web" {
  count = 3
  # ...
}
```

This creates three resources. Terraform addresses them by zero-based integer index:

```
aws_instance.web[0]
aws_instance.web[1]
aws_instance.web[2]
```

Inside the resource block, `count.index` gives the current instance's index. This is useful for naming:

```hcl
tags = {
  Name = "web-${count.index}"
}
```

**The reshuffling problem.** Count is fine when resources are truly identical. The problem arises when you derive `count` from a list variable and then change that list. Suppose you have:

```hcl
variable "names" { default = ["alpha", "beta", "gamma"] }

resource "aws_instance" "web" {
  count = length(var.names)
  tags  = { Name = var.names[count.index] }
}
```

The state contains `web[0]=alpha`, `web[1]=beta`, `web[2]=gamma`. If you remove `"alpha"` from the list, Terraform sees:

- `web[0]` should now be `beta` (was `alpha`) → **destroy and recreate**
- `web[1]` should now be `gamma` (was `beta`) → **destroy and recreate**
- `web[2]` no longer exists → **destroy**

Three resources are recreated even though only one was removed. This is the reshuffling problem.

### `for_each`

`for_each` creates one resource per entry in a map or set. Resources are addressed by their key, not an index:

```hcl
resource "aws_instance" "env" {
  for_each = {
    staging    = { instance_type = "t3.nano" }
    production = { instance_type = "t3.small" }
  }
  instance_type = each.value.instance_type
  tags = { Name = each.key }
}
```

State addresses:

```
aws_instance.env["staging"]
aws_instance.env["production"]
```

If you remove `"staging"` from the map, only `aws_instance.env["staging"]` is destroyed. `aws_instance.env["production"]` is untouched — no reshuffling.

Inside the resource block, `each.key` gives the map key and `each.value` gives the corresponding value object.

`for_each` accepts:
- A `map` — each entry becomes a resource, keyed by the map key
- A `set(string)` — each entry becomes a resource, keyed by the string value itself

`for_each` does **not** accept a plain `list`. Use `toset()` to convert a list of unique strings, or use a map.

### When to use `count` vs `for_each`

| Situation | Use |
|-----------|-----|
| Resources are truly identical (e.g. 5 worker nodes) | `count` |
| Resources differ in name, config, or tags | `for_each` |
| Derived from a list that might change order | `for_each` (with `toset` or map conversion) |
| You need to reference a single instance by a meaningful name | `for_each` |

In practice, `for_each` is almost always the better choice for production infrastructure. `count` can cause unintended resource recreation that is easy to miss in a plan.

### `dynamic` blocks

Many Terraform resources contain nested blocks that can repeat. The `ingress` block in `aws_security_group` is a common example. Without `dynamic`, you must write one block per rule:

```hcl
ingress { from_port = 80,  to_port = 80,  protocol = "tcp", ... }
ingress { from_port = 443, to_port = 443, protocol = "tcp", ... }
ingress { from_port = 22,  to_port = 22,  protocol = "tcp", ... }
```

With a `dynamic` block, you drive the repetition from a variable:

```hcl
dynamic "ingress" {
  for_each = var.security_group_rules
  iterator = rule   # Optional: names the loop variable. Defaults to the block label.

  content {
    from_port   = rule.value.port
    to_port     = rule.value.port
    protocol    = rule.value.protocol
    description = rule.value.description
    cidr_blocks = [var.my_ip_cidr]
  }
}
```

The `content {}` block defines what each generated nested block looks like. Inside `content`, use `<iterator>.value` to access the current item and `<iterator>.key` for the index or map key.

Adding a new entry to `var.security_group_rules` generates a new `ingress` block automatically.

`dynamic` blocks work wherever a resource accepts repeated nested blocks: `ingress`/`egress` in security groups, `ebs_block_device` on instances, `setting` in Elastic Beanstalk, and many others.

### `lifecycle` meta-argument

The `lifecycle` block modifies how Terraform manages the create/update/destroy cycle for a resource. It is a meta-argument — it applies to any resource type.

#### `create_before_destroy = true`

By default, when Terraform needs to replace a resource (because an immutable attribute changed), it destroys the existing resource first, then creates the new one. For zero-downtime deployments this order is wrong.

```hcl
resource "aws_instance" "web" {
  # ...
  lifecycle {
    create_before_destroy = true
  }
}
```

With `create_before_destroy = true`, Terraform creates the replacement first, then destroys the original. This matters for resources that serve live traffic. Note: the new and old resources will exist simultaneously for a brief period, so they must not conflict on unique constraints (e.g., fixed Elastic IP addresses).

#### `prevent_destroy = true`

Causes Terraform to error if a plan would destroy the resource:

```hcl
resource "aws_db_instance" "primary" {
  # ...
  lifecycle {
    prevent_destroy = true
  }
}
```

```
Error: Instance cannot be destroyed
  Resource aws_db_instance.primary has lifecycle.prevent_destroy set, but the
  plan calls for this resource to be destroyed.
```

Use this for stateful resources where accidental deletion is catastrophic: databases, S3 buckets with data, KMS keys. To actually destroy the resource, you must first remove the `prevent_destroy = true` line and re-apply.

`prevent_destroy` does not protect against `terraform destroy` or `terraform state rm`. It only stops plans that would implicitly destroy the resource due to a configuration change.

#### `ignore_changes`

Tells Terraform to ignore drift on specific attributes. After the resource is created, Terraform will never modify the listed attributes, even if the real resource diverges from the configuration.

```hcl
resource "aws_instance" "env" {
  # ...
  lifecycle {
    ignore_changes = [tags["LastModified"]]
  }
}
```

Common use cases:
- Tags written by external systems (CI/CD pipelines, deployment tools)
- `ami` — if you want to manage AMI updates outside Terraform (e.g., with an ASG launch template)
- `desired_count` on an ECS service managed by an auto-scaler

`ignore_changes = all` is available but should be used sparingly — it effectively turns off drift detection for the entire resource.

### Resource addresses with `count` and `for_each`

This affects more than readability. Resource addresses are used in:

- `terraform state list` output
- `terraform state rm <address>` for manual state surgery
- `terraform import <address> <id>` to import existing resources
- `-target=<address>` for targeted applies

Knowing whether a resource uses `count` or `for_each` tells you how to construct its address:

```bash
# count
terraform state show 'aws_instance.web[0]'
terraform state rm 'aws_instance.web[2]'

# for_each (note the quotes around the key)
terraform state show 'aws_instance.env["staging"]'
terraform state rm 'aws_instance.env["staging"]'
```

---

## Setup

**Prerequisites**: AWS CLI configured, Terraform >= 1.5 installed.

**Estimated cost**: 3× EC2 t3.nano = ~$0.015/hr combined. Destroy promptly when done.

1. Find your public IP:
   ```bash
   curl -s https://checkip.amazonaws.com
   ```

2. Create `terraform/terraform.tfvars`:
   ```hcl
   my_ip_cidr = "YOUR.IP.HERE/32"
   ```

---

## Exercises

### Exercise 1 — Inspect the dynamic block

Open `terraform/main.tf` and find the `aws_security_group.web` resource. Trace how `var.security_group_rules` flows into the `dynamic "ingress"` block.

Now open `terraform/variables.tf` and add a fourth rule to the `security_group_rules` default:

```hcl
{ port = 8080, protocol = "tcp", description = "Alt HTTP" },
```

Run `terraform plan` (before applying). The plan should show one new ingress rule being added to the security group. No other resources should change. Revert this change before continuing.

### Exercise 2 — Apply

```bash
cd terraform
terraform init
terraform apply
```

Type `yes` when prompted. This creates the VPC, subnets, security group, 3 count-based instances, and 2 for_each-based instances.

### Exercise 3 — Observe resource addresses in state

```bash
terraform state list
```

Identify the different address formats:

- `aws_instance.web[0]`, `aws_instance.web[1]`, `aws_instance.web[2]` — count
- `aws_instance.env["staging"]`, `aws_instance.env["production"]` — for_each

Inspect a specific resource:

```bash
terraform state show 'aws_instance.web[0]'
terraform state show 'aws_instance.env["staging"]'
```

### Exercise 4 — Demonstrate count reshuffling vs for_each stability

**Part A — count (safe removal of the last item):**

Edit `terraform/terraform.tfvars` (or override the variable):

```hcl
instance_count = 2
```

Run `terraform plan`. Observe that only `aws_instance.web[2]` is destroyed. The plan correctly removes only the last instance.

Apply the change, then restore `instance_count = 3` and apply again.

**Part B — for_each (removal of a middle item):**

Edit `terraform/variables.tf`. In the `environments` default, remove the `staging` entry entirely (leave only `production`). Run `terraform plan`.

Observe that only `aws_instance.env["staging"]` and `aws_subnet.foreach_demo["staging"]` are destroyed. `aws_instance.env["production"]` has no planned changes — no reshuffling.

Revert the change to `variables.tf` before continuing.

### Exercise 5 — `prevent_destroy` in action

Open `terraform/main.tf`. Add a `lifecycle` block to `aws_security_group.web`:

```hcl
lifecycle {
  prevent_destroy = true
}
```

Apply the change (no resource changes, just metadata). Now try:

```bash
terraform destroy
```

Terraform will error before making any changes:

```
Error: Instance cannot be destroyed
  Resource aws_security_group.web has lifecycle.prevent_destroy set...
```

Remove the `lifecycle` block and apply again to restore the normal state. Now run `terraform destroy` — it should succeed.

After verifying the error, **do not destroy yet** — continue to Exercise 6 first. Re-apply to get back to the full deployed state:

```bash
terraform apply
```

### Exercise 6 — `ignore_changes` and external drift

This exercise requires the AWS Console (or AWS CLI).

**Part A — with `ignore_changes` active:**

The `aws_instance.env` resource already has `ignore_changes = [tags["LastModified"]]` in `main.tf`.

In the AWS Console, navigate to EC2 > Instances. Find the `tf-lab06-staging` instance. Add a tag: Key = `LastModified`, Value = `2024-01-01`.

Run `terraform plan`. The plan should show **no changes** — Terraform ignores the `LastModified` tag.

**Part B — without `ignore_changes`:**

Open `terraform/main.tf`. Comment out the `ignore_changes` line:

```hcl
lifecycle {
  # ignore_changes = [tags["LastModified"]]
}
```

Run `terraform plan`. Now Terraform wants to remove the `LastModified` tag:

```
~ tags = {
  - "LastModified" = "2024-01-01" -> null
```

This is the behaviour `ignore_changes` prevents. Uncomment the line and restore the config.

### Exercise 7 — Destroy

```bash
terraform destroy
```

Confirm with `yes`. Verify in the AWS Console that no EC2 instances or VPCs remain.

---

## Key Takeaways

- Prefer `for_each` over `count` for non-identical resources. `count` reshuffling causes unexpected resource recreation when items are added or removed from the middle of a list.
- `for_each` resources are addressed by string keys (`["staging"]`). `count` resources are addressed by integer indices (`[0]`, `[1]`).
- `dynamic` blocks replace repetitive nested blocks with a data-driven loop. They work wherever a resource accepts repeated nested blocks.
- `create_before_destroy = true` is essential for zero-downtime deployments — new resource is created before the old one is destroyed.
- `prevent_destroy = true` is a safeguard for stateful resources. It only blocks implicit plan-time destruction, not `state rm` or direct API calls.
- `ignore_changes` handles legitimate external drift. Use it surgically on specific attributes, not `ignore_changes = all`.

---

## Cleanup

```bash
cd terraform
terraform destroy
```

Double-check in the AWS EC2 console that no instances remain running.
