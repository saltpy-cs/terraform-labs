# Lab 11 — Resilient Multi-Zone Architecture

## Objectives

- Understand RTO (Recovery Time Objective) and RPO (Recovery Point Objective) and
  how infrastructure design choices trade one off against the other
- Deploy a Regional Managed Instance Group (MIG) spanning multiple GCP zones
- Configure auto-healing so failed instances are replaced automatically
- Provision an external Network Load Balancer that routes only to healthy instances
- Observe live zone distribution: different zones serve different requests
- Simulate a zone failure and watch the MIG self-heal
- Understand how Terraform state resilience fits into a disaster recovery plan

## Concepts

### RTO and RPO

Every resilience design starts with two questions:

**RTO — Recovery Time Objective**: how long can your service be unavailable before
the outage becomes unacceptable? Thirty seconds? Two minutes? Four hours?

**RPO — Recovery Point Objective**: how much data can you afford to lose, expressed as a time window? An RPO of 10 minutes means recovery must restore state from no more than 10 minutes before the failure — anything written in that window is gone. If you restore from last night's backup, your RPO is however many hours have passed since then.

These are business decisions, not technical ones. But the decisions directly
determine which infrastructure patterns you need:

| Architecture | RTO | RPO | Monthly cost signal |
|---|---|---|---|
| Single instance, no redundancy | Hours (manual fix) | Since last backup | Cheapest |
| Single-zone MIG + auto-healing | 3–10 min | 0 (stateless) | Low |
| **Regional MIG + LB (this lab)** | **30s–2 min** | **0 (stateless)** | **Low–medium** |
| Multi-region active-passive | 10–30 min | Minutes (replication lag) | High |
| Multi-region active-active | < 30s | 0 | Highest |

"Stateless" means the instance holds no data — sessions and files live elsewhere
(a database, GCS, Memorystore). Stateless RTO is near-zero; the running instance
just serves requests, and any replacement is identical.

### GCP Zones and Regions

A **zone** is a single data centre within a region (`us-central1-a`, `us-central1-b`,
`us-central1-c`). A **region** is a geographic cluster of zones (`us-central1`).

A zone failure is rare but real — power, cooling, networking faults can take one down.
If all your instances are in one zone, that failure takes down your service. Spreading
across zones means a single zone failure leaves you running.

### Regional Managed Instance Groups

A **Managed Instance Group** (MIG) keeps N identical instances running, using an
**instance template** to define what each instance looks like.

A **Regional MIG** spans multiple zones. You specify:

```hcl
distribution_policy_zones = ["us-central1-a", "us-central1-b", "us-central1-c"]
target_size               = 3  # Terraform tries to spread evenly: 1 per zone
```

GCP distributes instances as evenly as possible. If a zone fails, GCP recreates those
instances in the remaining healthy zones.

### Auto-Healing

`auto_healing_policies` tells the MIG what a healthy instance looks like and what to
do when one isn't:

```hcl
auto_healing_policies {
  health_check      = google_compute_region_health_check.app.id
  initial_delay_sec = 300
}
```

- `health_check`: the MIG polls `GET /health` on each instance every 10 seconds
- After 3 consecutive failures, the instance is marked unhealthy and **replaced**
- `initial_delay_sec`: waits this long after instance creation before starting
  health checks — gives the startup script time to finish installing nginx

### The Update Policy and Zero-Downtime Deploys

```hcl
update_policy {
  type                  = "PROACTIVE"
  minimal_action        = "REPLACE"
  max_surge_fixed       = 3   # create up to 3 extra instances during a rollout
  max_unavailable_fixed = 0   # never reduce below target_size during a rollout
}
```

`max_unavailable_fixed = 0` is the key: Terraform will never destroy an old instance
before the new one is healthy and serving traffic. This is the infrastructure
equivalent of a rolling deploy.

### External Network Load Balancer

This lab uses a **regional external passthrough NLB** (Network Load Balancer):

```
Client → Forwarding Rule (external IP:80)
           ↓
         Regional Backend Service
           ↓  ↓  ↓
       [us-central1-a] [us-central1-b] [us-central1-c]
```

Key properties:
- **Passthrough**: GCP does not proxy the connection. Backend instances see the real
  client IP. The LB distributes TCP connections, not HTTP requests.
- **Health-check driven**: only healthy instances receive traffic. During auto-healing,
  the replacement instance doesn't get traffic until it passes health checks.
- **Regional**: the forwarding rule and backend service are in one region. Use a
  global HTTP(S) LB for multi-region active-active (beyond this lab's scope).

### GCP Health Checker IP Ranges

GCP sends health check probes from two fixed IP ranges: `35.191.0.0/16` and
`130.211.0.0/22`. Your firewall must explicitly allow these, otherwise all instances
appear unhealthy and receive no traffic:

```hcl
resource "google_compute_firewall" "allow_health_checks" {
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  ...
}
```

This is a common misconfiguration — if your LB shows all backends as `UNHEALTHY`,
check this firewall rule first.

### Terraform State as a DR Artefact

Terraform state is not just a bookkeeping file — it is a recovery asset.

**Why state matters for DR:**
- State records every resource Terraform manages, including IDs, ARNs, and computed
  attributes that took time to provision
- If you need to rebuild infrastructure after a disaster, state + code = exact rebuild
- Without state, `terraform plan` thinks everything needs to be created from scratch,
  and `terraform apply` will conflict with any resources still running

**State resilience strategy:**
1. **Remote state in GCS** (Lab 03): state lives in a GCS bucket, not a laptop
2. **GCS bucket versioning**: keeps a history of every state file write. If someone
   accidentally runs `terraform destroy` on prod, you can restore the previous state
   version and then `terraform apply` to recreate resources.
3. **GCS multi-regional location**: state bucket in `location = "US"` survives a
   regional GCP outage

```bash
# Verify state bucket versioning is on
gcloud storage buckets describe gs://<your-state-bucket> --format="value(versioning)"

# List all state versions (see the history)
gcloud storage ls --all-versions gs://<your-state-bucket>/lab11/

# Restore a previous state version (use the #N generation suffix)
gcloud storage cp "gs://<bucket>/lab11/default.tfstate#<generation>" ./terraform.tfstate
```

**State and RTO**: if your disaster recovery procedure requires re-running Terraform,
the time to locate and restore state is part of your RTO. Version-controlled state in
GCS with a documented restore procedure can reduce that to minutes.

## Setup

```bash
# Enable required APIs
gcloud services enable compute.googleapis.com storage.googleapis.com

# Authenticate
gcloud auth application-default login
gcloud config set project <your-project-id>

# Create a state bucket (or reuse from a previous lab)
STATE_BUCKET="tf-lab11-state-$(gcloud config get-value project)"
gcloud storage buckets create gs://$STATE_BUCKET --location=us-central1
```

Copy the example vars file and fill in your values:

```bash
cd lab-11-multi-zone-resilience/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set gcp_project and my_ip_cidr
```

> **Cost warning**: This lab creates an external forwarding rule (~$0.025/hr),
> 3× e2-micro instances (free tier covers one; the others are ~$0.01/hr combined),
> and a GCS bucket (~$0.00). Total for a 1–2 hour lab: ~$0.05–0.10. Destroy promptly.

## Exercises

### Exercise 1 — Initialise and plan

The backend uses partial configuration — pass the bucket name at init time:

```bash
STATE_BUCKET="tf-lab11-state-$(gcloud config get-value project)"
terraform init -backend-config="bucket=${STATE_BUCKET}"
terraform plan
```

In the plan, find the `google_compute_region_instance_group_manager` resource.
Note the `distribution_policy_zones` — three zones are explicitly configured.

Find the `auto_healing_policies` block. What is `initial_delay_sec` set to and why?

> `initial_delay_sec = 300`. The startup script installs nginx via `apt-get`, which
> can take 2–4 minutes. Without this delay, the MIG would start health-checking
> immediately, see a failing instance, and replace it before nginx is ready — causing
> a replacement loop. 300 seconds gives the script time to finish before the first
> health check fires.

Find the `update_policy` block. What does `max_unavailable_fixed = 0` guarantee
during a rolling update?

> During a rolling update, the MIG will never reduce below `target_size`. It creates
> a new instance and waits for it to pass health checks before removing the old one.
> The LB always has at least the full complement of healthy instances serving traffic.

### Exercise 2 — Apply

```bash
terraform apply -auto-approve
```

The apply takes 3–5 minutes. The longest wait is instance startup (nginx installing
and the health check's `initial_delay_sec` expiring before the MIG marks them healthy).

Watch instance creation in a second terminal:

```bash
watch -n5 'gcloud compute instance-groups managed list-instances tf-lab11-mig \
  --region=us-central1 --format="table(instance,currentAction,instanceStatus,zone)"'
```

You'll see instances move through: `CREATING` → `VERIFYING` → `RUNNING`.

### Exercise 3 — Verify zone distribution

Once all instances are `RUNNING`:

```bash
terraform output list_instances_command
# Run that command to see one instance per zone
```

```bash
gcloud compute instance-groups managed list-instances tf-lab11-mig \
  --region=us-central1
```

Confirm you have instances in at least two different zones (ideally all three).

### Exercise 4 — Wait for the LB to become healthy

The LB takes 1–2 minutes to detect that backends are healthy after apply.

```bash
# Poll until all backends show HEALTHY
watch -n10 'gcloud compute backend-services get-health tf-lab11-backend \
  --region=us-central1'
```

You're looking for `healthState: HEALTHY` for each instance.

### Exercise 5 — Test zone distribution through the LB

```bash
LB_IP=$(terraform output -raw load_balancer_ip)
echo "Load balancer IP: $LB_IP"

# Hit the LB 9 times — you should see all three zones appear
for i in $(seq 1 9); do
  curl -s http://$LB_IP | grep -oP 'Zone.*?<'
done
```

Each response shows the zone of the instance that served it. With 3 instances across
3 zones and 9 requests, you should see each zone appear 3 times (approximately).

You can also hit instances directly by their public IP to compare:

```bash
gcloud compute instances list --filter="name~tf-lab11" \
  --format="table(name,zone,networkInterfaces[0].accessConfigs[0].natIP)"
```

### Exercise 6 — Simulate instance failure (auto-healing)

Pick one instance name from the MIG list and delete it manually:

```bash
# Find an instance in zone -a
INSTANCE=$(gcloud compute instance-groups managed list-instances tf-lab11-mig \
  --region=us-central1 --format="value(instance)" | head -1)
ZONE=$(gcloud compute instance-groups managed list-instances tf-lab11-mig \
  --region=us-central1 --format="value(zone)" | head -1 | cut -d'/' -f9)

echo "Deleting: $INSTANCE in $ZONE"
gcloud compute instances delete $INSTANCE --zone=$ZONE --quiet
```

Immediately start watching the MIG:

```bash
watch -n5 'gcloud compute instance-groups managed list-instances tf-lab11-mig \
  --region=us-central1 --format="table(instance,currentAction,instanceStatus,zone)"'
```

Observe:
1. The deleted instance disappears
2. Within ~30 seconds the MIG detects the missing instance and starts creating a replacement
3. The replacement appears with `currentAction: CREATING`, then `VERIFYING`, then `RUNNING`

While this is happening, the LB continues routing to the two surviving instances.
The service is degraded (one fewer instance) but not down:

```bash
# Keep hitting the LB — it should keep responding during the recovery
while true; do curl -s http://$LB_IP | grep -oP 'Zone.*?<'; sleep 1; done
```

This is the difference between **availability** (service is up) and **capacity**
(service is running at full spec). During auto-healing, availability is maintained
even though capacity is temporarily reduced.

### Exercise 7 — Observe RTO in practice

Time how long from deletion to the replacement instance being `RUNNING`:

```bash
# In one terminal — delete an instance (as above)
time gcloud compute instances delete $INSTANCE --zone=$ZONE --quiet

# In another — watch until new instance is RUNNING
watch -n5 'gcloud compute instance-groups managed list-instances tf-lab11-mig \
  --region=us-central1 --format="table(instance,currentAction,instanceStatus)"'
```

Note the time. With `initial_delay_sec = 300` and a health check `check_interval_sec`
of 10, expect 5–8 minutes from deletion to healthy. This is your **RTO** for a single
instance failure with this configuration.

To reduce RTO:
- Lower `initial_delay_sec` (risky: health checks start before nginx is ready → premature
  replacement loop)
- Use a faster machine type and startup script
- Pre-bake a VM image with nginx already installed (eliminate apt-get from startup time)

### Exercise 8 — Terraform state resilience

Verify that your state bucket has versioning enabled:

```bash
STATE_BUCKET="tf-lab11-state-$(gcloud config get-value project)"
gcloud storage buckets describe gs://$STATE_BUCKET --format="value(versioning)"
```

Expected output: `{'enabled': True}`

List all state versions written so far:

```bash
gcloud storage ls --all-versions gs://$STATE_BUCKET/lab11/
```

You'll see entries like `default.tfstate#1234567890` — each `#` suffix is a generation
number (version). GCS keeps all of them.

Simulate accidental state corruption — remove a resource from state without destroying it:

```bash
# Remove the firewall rule from state (the actual GCP resource still exists)
terraform state rm google_compute_firewall.allow_http

# Plan now shows it as a new resource to create (state drift)
terraform plan
```

The plan wants to create a firewall rule that already exists. This demonstrates why
state is critical: Terraform has lost track of that resource.

Restore by re-syncing state from GCP:

```bash
# Re-import the resource back into state
PROJECT=$(grep gcp_project terraform.tfvars | cut -d'"' -f2)
terraform import google_compute_firewall.allow_http $PROJECT/tf-lab11-allow-http

# Plan should now show no changes
terraform plan
```

### Exercise 9 — Zero-downtime rolling update

Trigger a rolling update by changing a resource attribute. Add a label to the instance
template in `main.tf`:

```hcl
resource "google_compute_instance_template" "app" {
  ...
  labels = {
    version = "v2"
  }
  ...
}
```

```bash
terraform plan
```

Read the plan carefully. You should see:
- `google_compute_instance_template.app` will be **replaced** (creates a new template,
  destroys the old one after — because of `create_before_destroy`)
- `google_compute_region_instance_group_manager.app` will be **updated in-place** to
  reference the new template

```bash
terraform apply -auto-approve
```

Watch the rolling update:

```bash
watch -n5 'gcloud compute instance-groups managed list-instances tf-lab11-mig \
  --region=us-central1 --format="table(instance,currentAction,instanceStatus,version)"'
```

Instances are replaced one at a time. Because `max_unavailable_fixed = 0`, the MIG
creates the new instance and waits for it to pass health checks before removing the
old one. The LB continues serving traffic throughout.

### Exercise 10 — Explore autoscaling

The autoscaler targets 60% CPU. With e2-micro and low load, it will scale down to
`min_replicas`. You can observe its decisions:

```bash
gcloud compute instance-groups managed describe tf-lab11-mig \
  --region=us-central1 \
  --format="yaml(autoscaler)"
```

To understand what autoscaling means for RTO/RPO: when load increases and new instances
are being added, new instances go through the same `initial_delay_sec` and health check
cycle. Your LB only routes to healthy instances, so scaling events don't introduce bad
traffic — they just add capacity.

## Key Takeaways

- **RTO and RPO are business requirements** that translate directly into architecture
  decisions — build to your SLA, not to the theoretical maximum
- **Regional MIGs + auto-healing** provide zone resilience automatically — a zone failure
  triggers auto-healing in surviving zones with no manual intervention
- **`initial_delay_sec` governs your auto-healing RTO** — set it just above your startup
  script's worst-case runtime to avoid premature replacement loops
- **`max_unavailable_fixed = 0` enables zero-downtime rolling updates** — never take an
  instance out of service until its replacement is healthy
- **Health checker IP ranges must be explicitly allowed** — `35.191.0.0/16` and
  `130.211.0.0/22` are non-obvious and often the root cause of "all backends unhealthy"
- **Terraform state with GCS versioning is part of your DR plan** — document the state
  restore procedure alongside your infrastructure runbook
- **Stateless apps have RPO = 0** with multi-zone MIGs. For stateful workloads, RPO is
  set by your replication strategy (Cloud SQL HA, Cloud Spanner, replicated GCS)

## Cleanup

```bash
terraform destroy -auto-approve
```

This destroys all resources including the load balancer forwarding rule (the main cost
driver). Verify cleanup:

```bash
gcloud compute forwarding-rules list --region=us-central1 | grep tf-lab11
gcloud compute instance-groups managed list --region=us-central1 | grep tf-lab11
```

Both commands should return no output.
