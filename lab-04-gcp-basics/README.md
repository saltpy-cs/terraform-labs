# Lab 04 — GCP Provider Basics

> **Cost warning:** A GCE e2-micro instance is free-tier eligible in us-central1 (one instance per month per billing account). Destroy promptly after completing the exercises to stay within free tier.

## Objectives

By the end of this lab you will be able to:

- Configure the GCP provider with project, region, zone, and version constraints
- Create a VPC network and subnet using GCP's global networking model
- Create firewall rules to control instance traffic
- Launch a GCE e2-micro instance using a data-source-resolved Debian image
- Explain implicit vs explicit resource dependencies in a Terraform configuration
- Read GCP resource documentation to discover available arguments
- Explain how GCP networking differs from AWS (no internet gateway, no route tables)

---

## Concepts

### GCP provider configuration

The `google` provider requires at minimum a project ID. Region and zone can be set at the provider level (as defaults) and overridden per-resource.

```hcl
provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
  zone    = var.gcp_zone
}
```

**Authentication** uses Application Default Credentials (ADC). After running `gcloud auth application-default login`, the provider picks up credentials automatically — no `credentials` argument is needed in the provider block.

Version constraints go in the `terraform` block, not the provider block:

```hcl
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}
```

`~> 6.0` means "6.x but not 7.0" — it accepts patch and minor updates but not a major version bump that could break the API.

### GCP networking vs AWS networking

This is one of the most important conceptual differences for learners coming from AWS:

| Concept | AWS | GCP |
|---|---|---|
| Network scope | Regional (one VPC per region) | Global (one VPC spans all regions) |
| Subnet scope | Availability zone | Regional |
| Internet access resource | `aws_internet_gateway` required | No resource needed |
| Routing resource | `aws_route_table` + association required | GCP manages routing automatically |
| Instance access control | Security groups attached to instance NIC | Firewall rules on the VPC, applied to instances via tags |

**No internet gateway resource in GCP.** In AWS, traffic can only leave a VPC if an Internet Gateway is attached and a route table directs `0.0.0.0/0` to that gateway — both of which are explicit Terraform resources. In GCP, any instance with an external IP address can reach the internet by default. There is no gateway object to declare.

**No route table resource in GCP.** GCP manages routing tables internally. A default route for `0.0.0.0/0` is created automatically for custom VPCs. You can add custom static routes (`google_compute_route`) for advanced cases, but basic internet access requires nothing extra.

**Firewall rules are on the VPC, not the instance.** GCP firewall rules belong to a network and are applied to instances via **network tags** (`target_tags`) or **service accounts** (`target_service_accounts`). An instance gets a rule applied by having the matching tag. This means you can change which firewall rules apply to an instance by updating its tags — without touching the firewall rules themselves.

### Data sources: finding the latest image

A data source reads existing infrastructure and makes its attributes available in your configuration. Here it finds the current latest Debian 12 image without hardcoding a name that would go stale:

```hcl
data "google_compute_image" "debian" {
  most_recent = true
  family      = "debian-12"
  project     = "debian-cloud"
}
```

The `project = "debian-cloud"` argument scopes the lookup to Debian's public image project. Without it, Terraform would search only your own project's images.

The resolved image is referenced in the boot disk: `data.google_compute_image.debian.self_link`.

Data sources are declared with `data "<type>" "<name>"` and referenced as `data.<type>.<name>.<attribute>`. They are evaluated during `terraform plan` — they read from GCP, never create or modify anything.

### Implicit vs explicit dependencies

Terraform builds a dependency graph from resource references. When one resource argument references another resource's attribute, Terraform automatically creates the referenced resource first.

**Implicit dependency** (via reference):

```hcl
resource "google_compute_subnetwork" "public" {
  network = google_compute_network.main.id  # implicit dependency on network
}
```

Terraform sees the reference to `google_compute_network.main.id` and adds an edge in the graph. The network is created before the subnet.

**Explicit dependency** (via `depends_on`):

```hcl
resource "google_compute_instance" "main" {
  depends_on = [google_compute_firewall.allow_ssh]
}
```

Use `depends_on` when a real dependency exists but is not expressed through attribute references. In this lab, the firewall rule is on the network, not on the instance — so there is no attribute in the instance block that references the firewall. The explicit `depends_on` documents that the firewall should exist before the instance starts receiving traffic.

### The `terraform plan` symbols

| Symbol | Meaning |
|---|---|
| `+` | Resource will be created |
| `-` | Resource will be destroyed |
| `~` | Resource will be updated in-place (no replacement) |
| `-/+` | Resource will be destroyed and recreated (forced replacement) |
| `<=` | Data source will be read |

**In-place update (`~`):** The provider can modify the resource without deleting it. Example: adding a tag to a GCE instance.

**Destroy and recreate (`-/+`):** The provider cannot change the attribute on a running resource. Example: changing `machine_type` on a GCE instance. This is the most dangerous symbol — in production it causes downtime and can mean data loss if the resource holds state.

---

## Setup

### Prerequisites

- Terraform >= 1.5 installed
- `gcloud` CLI installed and authenticated:

```bash
gcloud auth application-default login
```

- A GCP project with billing enabled and the Compute Engine API active:

```bash
gcloud services enable compute.googleapis.com --project=YOUR_PROJECT_ID
```

### Verify GCP access

```bash
gcloud auth application-default print-access-token > /dev/null && echo "ADC credentials are valid"
gcloud config get-value project
```

---

## Exercises

### Exercise 1: Set your IP and create terraform.tfvars

Find your public IP address:

```bash
curl ifconfig.me
```

Copy the example vars file:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars` and fill in your values:

```hcl
gcp_project  = "your-actual-project-id"
gcp_region   = "us-central1"
gcp_zone     = "us-central1-a"
project_name = "tf-lab04"
subnet_cidr  = "10.0.1.0/24"
my_ip_cidr   = "1.2.3.4/32"   # replace with output of: curl ifconfig.me
```

> Do not commit `terraform.tfvars` to source control — it may contain environment-specific values.

---

### Exercise 2: `terraform init` — observe the GCP provider download

```bash
cd terraform
terraform init
```

Expected output (abbreviated):
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/google versions matching "~> 6.0"...
- Installing hashicorp/google v6.x.x...
- Installed hashicorp/google v6.x.x (signed by HashiCorp)

Terraform has been successfully initialized!
```

The GCP provider is a large binary (~100 MB). It is downloaded into `.terraform/providers/`. A `.terraform.lock.hcl` file is created — this pins the exact provider version and should be committed to version control so everyone on the team runs the same provider binary.

---

### Exercise 3: `terraform plan` — read the dependency order

```bash
terraform plan
```

Read the output carefully. Observe the order in which resources will be created:

1. `data.google_compute_image.debian` — read during plan (`<=` symbol)
2. `google_compute_network.main` — no dependencies; can be created immediately
3. `google_compute_subnetwork.public`, `google_compute_firewall.allow_ssh`, `google_compute_firewall.allow_egress` — all depend only on the network; Terraform can create these in parallel
4. `google_compute_instance.main` — depends on the subnet and the data source; created last

Notice that values shown as `(known after apply)` cannot be determined until GCP creates the resource. The `instance_external_ip` output will only be known after the instance is created.

The plan ends with:
```
Plan: 5 to add, 0 to change, 0 to destroy.
```

Count the `+` blocks and verify this matches.

---

### Exercise 4: Note GCP vs AWS differences in the plan

Compare what is in this plan to what an equivalent AWS plan would contain.

Resources that exist in the AWS equivalent but are **absent from this GCP plan**:

- No `aws_internet_gateway` analog — there is no internet gateway resource in GCP
- No `aws_route_table` resource — GCP creates the default `0.0.0.0/0` route automatically
- No `aws_route_table_association` resource — no associations needed
- No `aws_security_group` resource — replaced by `google_compute_firewall`, which belongs to the network, not the instance

The GCP plan has 5 resources. The AWS equivalent has 8. GCP's networking model eliminates three resources that in AWS exist only to wire things together.

---

### Exercise 5: Intentionally break it — sever an implicit dependency

Before applying, observe what happens when you break a resource reference.

In `terraform/main.tf`, change the subnet's `network` argument to a hardcoded fake value:

```hcl
resource "google_compute_subnetwork" "public" {
  network = "projects/fake-project/global/networks/does-not-exist"
  ...
}
```

Run `terraform plan`:

```bash
terraform plan
```

Terraform will succeed at the plan stage for most attributes — type and syntax validation passes. However, the dependency between the subnet and the real network is now severed. Terraform no longer knows the subnet needs the network to exist first.

If you were to apply, GCP's API would reject the subnet creation because the specified network does not exist.

Revert the change before continuing:

```hcl
resource "google_compute_subnetwork" "public" {
  network = google_compute_network.main.id
  ...
}
```

---

### Exercise 6: Apply

```bash
terraform apply -auto-approve
```


Watch the creation output — notice the parallelism: the subnet and both firewall rules are created concurrently after the network is ready, because they all depend only on the network (not on each other).

Expected output (abbreviated):
```
google_compute_network.main: Creating...
google_compute_network.main: Creation complete after 10s
google_compute_subnetwork.public: Creating...
google_compute_firewall.allow_ssh: Creating...
google_compute_firewall.allow_egress: Creating...
google_compute_subnetwork.public: Creation complete after 8s
google_compute_firewall.allow_ssh: Creation complete after 10s
google_compute_firewall.allow_egress: Creation complete after 10s
google_compute_instance.main: Creating...
google_compute_instance.main: Creation complete after 15s

Apply complete! Resources: 5 added, 0 changed, 0 destroyed.

Outputs:

debian_image         = "debian-12-bookworm-v20240101"
instance_external_ip = "34.x.x.x"
instance_name        = "tf-lab04-instance"
instance_self_link   = "https://www.googleapis.com/compute/v1/projects/..."
network_id           = "projects/your-project/global/networks/tf-lab04-network"
subnet_id            = "projects/your-project/regions/us-central1/subnetworks/..."
```

---

### Exercise 7: SSH to the instance

GCP provides a managed SSH mechanism via `gcloud compute ssh`. On first use it generates an SSH key pair at `~/.ssh/google_compute_engine` and injects the public key into the instance's metadata — no key pair resource is needed in your Terraform configuration.

```bash
gcloud compute ssh tf-lab04-instance --zone us-central1-a
```

Type `exit` to leave the SSH session.

You can also SSH manually using the external IP from the Terraform output. **Run `gcloud compute ssh` above first** — it creates `~/.ssh/google_compute_engine` and injects the key. The username must match your local account name (not `debian`), because that is the username `gcloud compute ssh` registers the key under:

```bash
INSTANCE_IP=$(terraform output -raw instance_external_ip)
ssh -i ~/.ssh/google_compute_engine $USER@$INSTANCE_IP
```

If the connection is refused, verify that `my_ip_cidr` in `terraform.tfvars` matches your current public IP (`curl ifconfig.me`). Your ISP may have assigned you a different IP since you set the variable.

---

### Exercise 8: In-place update (`~`) — change a tag

Network tags on a GCE instance can be updated without stopping or recreating the instance.

In `main.tf`, add a second tag to the instance:

```hcl
resource "google_compute_instance" "main" {
  tags = ["ssh-enabled", "lab04"]
  ...
}
```

Run `terraform plan`:

```bash
terraform plan
```

Expected output (abbreviated):
```
  ~ resource "google_compute_instance" "main" {
      ~ tags = [
            "ssh-enabled",
          + "lab04",
        ]
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

The `~` symbol indicates an in-place update. GCP can apply this change without stopping the VM. Apply it and confirm the instance keeps running:

```bash
terraform apply -auto-approve
```

Then revert the change — remove `"lab04"` from the tags list — and re-apply to restore the original state:

```bash
terraform apply -auto-approve
```

---

### Exercise 9: Stop-and-update (`~`) — change machine_type

Changing `machine_type` requires GCP to stop the VM, change the type, and restart it. With the google provider v6+, Terraform handles this as an in-place update (`~`) rather than a destroy-then-recreate — the resource is not replaced, but there is downtime while the VM cycles.

In `main.tf`, change `machine_type`:

```hcl
resource "google_compute_instance" "main" {
  machine_type = "e2-small"
  ...
}
```

Run `terraform plan`:

```bash
terraform plan
```

Expected output (abbreviated):
```
  ~ resource "google_compute_instance" "main" {
      ~ machine_type = "e2-micro" -> "e2-small"

Plan: 0 to add, 1 to change, 0 to destroy.
```

The `~` indicates an in-place update. Unlike the tag change in Exercise 8, this one requires a VM stop/start — the external IP is preserved because the resource is not recreated, but the instance is unavailable for 30–60 seconds during the change.

Examples of changes that do force full replacement (`-/+`) in the GCP provider: changing the instance `name`, modifying `boot_disk` image, or changing `zone`.

**Do not apply this change.** Restore `machine_type = "e2-micro"` and verify the plan shows no changes:

```bash
terraform plan
# No changes. Your infrastructure matches the configuration.
```

---

### Exercise 10: Explicit `depends_on` on the instance

The `google_compute_firewall.allow_ssh` rule is attached to the network, not to the instance. This means there is no attribute reference from the instance resource to the firewall resource — Terraform will not automatically wait for the firewall to be created before creating the instance.

In practice, both the firewall and the instance depend on the network, and firewall creation is fast, so the race condition rarely matters. But you can make the intent explicit:

```hcl
resource "google_compute_instance" "main" {
  depends_on = [google_compute_firewall.allow_ssh]
  ...
}
```

Add this to the instance block in `main.tf` and run:

```bash
terraform plan
```

Expected output:
```
No changes. Your infrastructure matches the configuration.
```

`depends_on` affects only ordering — it does not cause recreation of existing resources. The plan shows no changes because the infrastructure already matches the configuration. This is different from Exercise 9, where changing a resource's argument triggered recreation.

This pattern matters when a resource must exist before another can function correctly but there is no attribute reference to express that relationship (for example, an IAM binding that must be in place before a GCE instance can call a GCP API).

Revert the change — remove the `depends_on` line from the instance block — before continuing to Exercise 11.

---

### Exercise 11: `terraform destroy`

```bash
terraform destroy -auto-approve
```

Observe the reverse dependency order in the output:

```
google_compute_instance.main: Destroying...
google_compute_instance.main: Destruction complete after 20s
google_compute_subnetwork.public: Destroying...
google_compute_firewall.allow_ssh: Destroying...
google_compute_firewall.allow_egress: Destroying...
google_compute_subnetwork.public: Destruction complete after 8s
google_compute_firewall.allow_ssh: Destruction complete after 8s
google_compute_firewall.allow_egress: Destruction complete after 8s
google_compute_network.main: Destroying...
google_compute_network.main: Destruction complete after 10s

Destroy complete! Resources: 5 destroyed.
```

The instance is destroyed first (it depends on everything else), then the subnet and firewalls in parallel, then the network last. The dependency graph runs in reverse for destruction.

---

## Key Takeaways

- **GCP networking is simpler than AWS** for basic internet access — no internet gateway resource, no route table resources. An instance with a public IP has internet access automatically.
- **`google_compute_firewall` belongs to the VPC**, not the instance. Rules are applied to instances via `target_tags`. This means a single firewall rule can apply to many instances just by adding the tag.
- **Data sources** (`data "google_compute_image"`) resolve existing GCP resources at plan time without managing them. Always use image families instead of hardcoded names so your config automatically tracks the latest patched image.
- **`machine_type` changes force instance replacement** (`-/+`) in GCP. The external IP changes and local disks are wiped. Plan machine sizing carefully before deploying production instances.
- **`gcloud compute ssh`** handles SSH key injection automatically — no key pair Terraform resource is needed.
- **Implicit dependencies** are expressed through attribute references (`google_compute_subnetwork.public.id`). Use `depends_on` only when a real dependency exists but cannot be expressed through a reference.
