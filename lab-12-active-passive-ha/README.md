# Lab 12: Active-Passive HA — Cloud SQL & Memorystore

## Objectives

- Understand Active-Passive vs Active-Active HA architectures
- Configure Cloud SQL for PostgreSQL with REGIONAL availability (synchronous standby)
- Configure Memorystore Redis with STANDARD_HA (replica in a separate zone)
- Set up Private Service Access (PSA) so managed services use private IPs
- Understand what Terraform manages (desired state) vs what it does not (operational events)
- Use the `null_resource` + `local-exec` pattern to trigger a planned switchover from `terraform apply`
- Explain the idempotency limitation of this pattern and when to use `gcloud` directly instead

**Certification alignment:** Terraform Authoring and Operations Professional — infrastructure resilience, operational patterns, declarative vs imperative boundaries.

> **Cost warning:** This is the most expensive lab in the course. Estimated costs while the lab is running:
> - Cloud SQL `db-f1-micro` REGIONAL: ~$0.02/hr
> - Memorystore Redis 1GB STANDARD_HA: ~$0.098/hr
> - Bastion VM e2-micro: ~$0.008/hr
> - VPC, PSA: free
>
> **Total: ~$0.13/hr (~$0.26 for a 2-hour lab session).**
> Run `terraform destroy` as soon as you finish. Cloud SQL REGIONAL (HA) provisions a primary and a standby replica with synchronous replication — expect **15–25 minutes** to provision and ~5 minutes to destroy. Redis takes ~5 minutes. The apply in Exercise 3 will feel slow; that's normal.

---

## Concepts

### Active-Passive vs Active-Active

Both terms describe how multiple copies of a service handle availability:

| Pattern | How it works | Trade-off |
|---|---|---|
| **Active-Passive** | One node handles all traffic (primary). A second node is idle but ready (standby). On failure, standby takes over. | Simpler; standby capacity is "wasted" until needed. |
| **Active-Active** | All nodes handle traffic simultaneously. | Higher throughput; more complex consistency model. |

Cloud SQL REGIONAL and Memorystore STANDARD_HA are both **Active-Passive**: one primary handles all reads and writes; the standby (or replica) exists only to take over.

### RTO and RPO

RTO and RPO were introduced in Lab 11. This lab applies them to stateful services
where the numbers look very different — synchronous replication changes the story
significantly:

| Service | Configuration | RPO | RTO |
|---|---|---|---|
| Cloud SQL | ZONAL (no HA) | Since last backup (hours) | Hours (manual restore from backup) |
| Cloud SQL | REGIONAL (HA) | ≈ 0 (synchronous replication) | 30s–2min (automatic failover) |
| Memorystore Redis | BASIC | All in-memory data lost | Minutes (GCP repairs/replaces node) |
| Memorystore Redis | STANDARD_HA | ≈ 0 (sub-ms replication lag) | ~10–30s (automatic promotion) |

### Cloud SQL REGIONAL Availability

When `availability_type = "REGIONAL"`:

```
Region: us-central1
├── Zone us-central1-a  →  PRIMARY (reads + writes, GCP-selected zone)
└── Zone us-central1-b  →  STANDBY (standby, idle, GCP-selected zone)
```

- Replication is **synchronous**: every write is confirmed on both nodes before the client gets an acknowledgement. This is the reason RPO ≈ 0.
- The standby is not reachable by clients — it exists only for automatic failover.
- After failover, the old primary becomes the new standby. GCP re-establishes the standby automatically within 5–10 minutes.
- **Planned switchover** (`gcloud sql instances failover`): operator-initiated, graceful, zero data loss. Used for maintenance.
- **Automatic failover**: triggered by GCP when the primary becomes unresponsive. Same mechanism, but driven by a health check timeout.

Enabling HA roughly doubles the cost of the Cloud SQL instance. `availability_type = "ZONAL"` is for non-critical workloads.

### Memorystore Redis STANDARD_HA

When `tier = "STANDARD_HA"`:

```
Region: us-central1
├── location_id             (us-central1-a)  →  PRIMARY
└── alternative_location_id (us-central1-b)  →  REPLICA
```

- Replication is **asynchronous** but the lag is typically sub-millisecond within a region — effective RPO ≈ 0 for most workloads.
- The replica is **not readable by clients** in STANDARD_HA mode (unlike read replicas).
- On failure, GCP automatically promotes the replica. The connection host and port stay the same; client reconnect handles the transition.
- **Manual failover** (`gcloud redis instances failover`): used for maintenance or to test failover behaviour. Requires choosing a data-protection-mode (see failover.tf).

BASIC tier has no replica. A failed BASIC node causes downtime until GCP repairs or replaces it — no automatic promotion is possible.

### Private Service Access (PSA)

Cloud SQL with a private IP and Memorystore both require **Private Service Access**. Without it, managed services can only be reached via a public IP.

PSA works by establishing a VPC peering connection between your VPC and Google's managed services network. Two resources are required:

```hcl
# 1. Reserve a CIDR block for Google to allocate to managed service instances
resource "google_compute_global_address" "private_ip_alloc" {
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16           # /16 = 65 536 addresses, enough for both services
  network       = google_compute_network.main.id
}

# 2. Create the VPC peering connection to servicenetworking.googleapis.com
resource "google_service_networking_connection" "private_vpc" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_alloc.name]
}
```

Once this connection exists:
- Cloud SQL uses the VPC network reference in `ip_configuration.private_network`
- Memorystore uses `connect_mode = "PRIVATE_SERVICE_ACCESS"` and `reserved_ip_range = <address_name>`

Both services then receive private IP addresses from the allocated range and are reachable from any subnet in your VPC.

### Terraform's Role: Configuration vs Operations

This is the most important concept in this lab.

Terraform is **declarative**: you describe desired state, and Terraform reconciles reality to match. This is powerful for infrastructure — create a VPC, provision a Cloud SQL instance, configure HA.

A planned switchover is an **imperative event**: "do this now." It is not a state you want to persist. After the switchover, the Cloud SQL instance is in its new desired state (primary in a different zone) — but Terraform already knows about both zones; nothing in the Terraform resource needs to change.

This creates a conceptual mismatch. The three practical options are:

| Approach | When to use |
|---|---|
| `gcloud` CLI directly | Best for operational runbooks, incident response. Clear, simple, auditable in shell history or runbook docs. |
| `null_resource` + `local-exec` (this lab) | Useful when you want a single `terraform apply` invocation to both provision infrastructure AND trigger an immediate operational action. Has idempotency limitations — see below. |
| Cloud Workflows / Cloud Run job | Best for teams that want operational runbooks as code with retries, audit logs, and orchestration. Terraform invokes the workflow; the workflow runs the operational steps. |

### The `null_resource` Failover Pattern

`null_resource` has no associated GCP resource. Its only purpose is to run provisioners. Terraform tracks it via its `triggers` map in state.

```hcl
resource "null_resource" "cloud_sql_switchover" {
  count = var.failover_timestamp != "" ? 1 : 0

  triggers = {
    timestamp = var.failover_timestamp  # changes → Terraform replaces resource → provisioner re-runs
    instance  = google_sql_database_instance.primary.name
  }

  provisioner "local-exec" {
    command = "gcloud sql instances failover ..."
  }
}
```

**The idempotency limitation:** if `failover_timestamp` is the same on two consecutive applies, Terraform sees the triggers map as unchanged and does NOT re-run the provisioner. Using `$(date +%s)` as the value ensures a new timestamp every time, forcing a replace.

```bash
# First switchover:
terraform apply -auto-approve -var="failover_timestamp=$(date +%s)"

# Clear (destroy the null_resource, no provisioner):
terraform apply -auto-approve   # failover_timestamp = "" → count = 0 → resource destroyed

# Second switchover (new timestamp → resource recreated → provisioner runs):
terraform apply -auto-approve -var="failover_timestamp=$(date +%s)"
```

### Switchover vs Failover

These terms are often used interchangeably but have a precise distinction:

| Term | Trigger | Data loss risk | Use case |
|---|---|---|---|
| **Planned switchover** | Operator-initiated | None (RPO = 0) | Scheduled maintenance, zone evacuation |
| **Automatic failover** | GCP health check timeout | Near-zero (synchronous replication) | Unplanned primary failure |
| **Forced failover** (`force-data-loss`) | Operator-initiated | Possible (recent writes) | Testing; last resort when limited-data-loss stalls |

For Cloud SQL, `gcloud sql instances failover` performs a *planned switchover* — despite the name. Both the primary and standby are healthy; this is a graceful handoff.

---

## Setup

### 1. Enable required APIs

```bash
gcloud services enable \
  sqladmin.googleapis.com \
  redis.googleapis.com \
  servicenetworking.googleapis.com \
  --project=$(gcloud config get-value project)
```

API activation takes ~1 minute. You only need to do this once per project.

### 2. Authenticate

```bash
gcloud auth application-default login
```

### 3. Prepare variables

```bash
cd lab-12-active-passive-ha/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set gcp_project and my_ip_cidr (run: curl ifconfig.me)
```

---

## Exercises

### Exercise 1 — Init

```bash
terraform init
```

Note the providers being installed: `hashicorp/google`, `hashicorp/random`, `hashicorp/null`.

### Exercise 2 — Plan and review the dependency graph

```bash
terraform plan
```

Observe the planned resources. Pay attention to the order:

1. `google_compute_network.main` and `google_compute_global_address.private_ip_alloc` can be created in parallel (no dependency between them)
2. `google_service_networking_connection.private_vpc` depends on both — it must wait
3. `google_sql_database_instance.primary` and `google_redis_instance.primary` both depend on the PSA connection

Terraform infers this order from resource references in `depends_on` and attribute references (e.g. `google_service_networking_connection.private_vpc` references `google_compute_network.main.id`).

```bash
# Optionally visualise the graph (requires graphviz):
terraform graph | dot -Tpng -o graph.png
```

### Exercise 3 — Apply (expect 5–10 minutes)

```bash
terraform apply -auto-approve
```

Cloud SQL provisioning is slow (~5–10 minutes). This is normal — GCP is provisioning two instances (primary + standby) across two zones. While it's running:

- Watch the Cloud Console: **SQL → Instances**
- Watch Memorystore: **Memorystore → Redis**
- Note that Terraform streams resource creation in real time

### Exercise 4 — Inspect Cloud SQL HA status

After apply completes, inspect the Cloud SQL instance:

```bash
gcloud sql instances describe $(terraform output -raw cloud_sql_instance_name) \
  --format="table(name,gceZone,secondaryGceZone,settings.availabilityType)"
```

Or use the generated inspect commands:
```bash
terraform output inspect_commands
```

You should see:
- `gceZone`: the current primary zone (e.g. `us-central1-a`)
- `secondaryGceZone`: the standby zone (e.g. `us-central1-b`)
- `availabilityType`: `REGIONAL`

### Exercise 5 — Inspect Memorystore HA status

```bash
gcloud redis instances describe $(terraform output -raw redis_host | xargs -I {} bash -c 'echo tf-lab12-redis') \
  --region=us-central1 --format="table(name,currentLocationId,tier,readReplicasMode)"
```

Alternatively:
```bash
terraform output redis_current_location
terraform output redis_tier
```

You should see `currentLocationId` matching `var.primary_zone` and `tier = STANDARD_HA`.

### Exercise 6 — Understand what changing availability_type does

Without applying, change `availability_type = "REGIONAL"` to `"ZONAL"` in `main.tf` and run:

```bash
terraform plan
```

You should see an **in-place update** — the provider modifies `availability_type`
without recreating the instance. This means no data loss, but it does carry
operational risk:

- While transitioning from `REGIONAL` to `ZONAL`, the standby is removed. If the
  primary fails during this window, there is no automatic failover.
- Going the other direction (`ZONAL` → `REGIONAL`) provisions a new standby, which
  takes 5–10 minutes. During that window HA is not yet active.

Revert the change before continuing:
```bash
git checkout terraform/main.tf
```

In production, treat `availability_type` changes as a maintenance operation:
schedule them in a low-traffic window, alert on-call, and verify the standby
is healthy before considering the change complete.

### Exercise 7 — Trigger a Cloud SQL planned switchover

```bash
terraform apply -auto-approve -var="failover_timestamp=$(date +%s)"
```

Terraform will create `null_resource.cloud_sql_switchover[0]` and run the `local-exec` provisioner, which calls `gcloud sql instances failover`. The command returns as soon as GCP accepts the request — the actual promotion takes 30s–2min.

Poll until the zone changes (Ctrl+C when you see a new zone):

```bash
watch -n5 'gcloud sql instances describe tf-lab12-pg --format="value(gceZone,secondaryGceZone)"'
```

The primary zone should differ from where it was before once the switchover completes.

### Exercise 8 — Test null_resource idempotency

Apply again WITHOUT the timestamp variable:

```bash
terraform apply -auto-approve
```

You will see `null_resource.cloud_sql_switchover` being **destroyed** — this is
expected and intentional. `failover_timestamp` defaults back to `""`, which sets
`count = 0` on the null_resource, so Terraform removes it. No switchover runs.

After a switchover Cloud SQL takes 5–10 minutes to re-establish the standby in
the old primary's zone. A second switchover will fail if the standby isn't ready.
Wait until `secondaryGceZone` is populated before continuing:

```bash
watch -n10 'gcloud sql instances describe tf-lab12-pg --format="value(gceZone,secondaryGceZone)"'
```

Once both zones are shown, note the primary zone and apply with a fixed timestamp:

```bash
gcloud sql instances describe tf-lab12-pg --format="value(gceZone)"

terraform apply -auto-approve -var="failover_timestamp=1000000000"
# null_resource is created → provisioner runs → switchover triggered
```

The switchover is asynchronous — wait for the zone to change (Ctrl+C when done):

```bash
watch -n5 'gcloud sql instances describe tf-lab12-pg --format="value(gceZone)"'
```

Now apply with the **same** timestamp:

```bash
terraform apply -auto-approve -var="failover_timestamp=1000000000"
# triggers map unchanged → Terraform sees no diff → provisioner does NOT re-run
```

Check the zone a third time — it should be unchanged, confirming the provisioner did not fire:

```bash
gcloud sql instances describe tf-lab12-pg --format="value(gceZone)"
```

This demonstrates why the pattern uses a unique timestamp: the triggers map must change to force re-execution.

### Exercise 9 — Trigger a Redis failover

Check the primary zone before and after:

```bash
# Before (note current primary zone):
gcloud redis instances describe tf-lab12-redis --region=us-central1 \
  --format="value(currentLocationId)"

terraform apply -auto-approve -var="redis_failover_timestamp=$(date +%s)"

# After (primary zone should have changed):
gcloud redis instances describe tf-lab12-redis --region=us-central1 \
  --format="value(currentLocationId)"
```

### Exercise 10 — Simulate an application connection

Both Cloud SQL and Memorystore Redis use private IPs only — unreachable from your
laptop. The bastion VM lives in the same VPC subnet and can reach both services
directly, simulating how an application tier connects in production.

SSH to the bastion (wait ~1 minute after apply for the startup script to install the tools):

```bash
$(terraform output -raw bastion_ssh)
```

From the bastion, connect to **Cloud SQL** using the private IP:

```bash
# Get the private IP and password (run on your laptop first, copy the values):
terraform output -raw cloud_sql_private_ip
terraform output -raw cloud_sql_db_password
# Note: zsh may show a trailing % after -raw output — do not include it in the password

# On the bastion:
PGPASSWORD=<password> psql -h <private_ip> -U appuser -d appdb
```

Run a quick query to confirm connectivity:

```sql
SELECT version();
\q
```

From the bastion, connect to **Redis**:

```bash
# Get the Redis host (run on your laptop first, copy the value):
terraform output -raw redis_host

# On the bastion:
redis-cli -h <redis_host> -p 6379 ping
```

Expected output: `PONG`

The key point: **both endpoints survive a failover**. The private IP for Cloud SQL and
the Redis host do not change when zones switch — your application reconnects to the
same address and finds the new primary there. Exit the bastion with `exit`.

### Exercise 11 — Cleanup

```bash
terraform destroy -auto-approve
```

Cloud SQL takes ~3–5 minutes to destroy.

> The destroy will pause for 120 seconds on `time_sleep.wait_before_psa_delete` — this is intentional. GCP's internal state for the PSA connection lags ~60–120s after Cloud SQL and Redis are deleted; the sleep prevents a `Producer services are still using this connection` error.

Confirm all resources are removed:

```bash
gcloud sql instances list | grep tf-lab12 || echo "OK: no Cloud SQL instances"
gcloud redis instances list --region=us-central1 | grep tf-lab12 || echo "OK: no Redis instances"
```

---

## Key Takeaways

- **Active-Passive HA** pairs a primary that serves all traffic with a standby that exists only for failover. Both Cloud SQL REGIONAL and Memorystore STANDARD_HA implement this pattern.
- **RPO ≈ 0** for both services because replication is synchronous (Cloud SQL) or near-synchronous (Redis) within a region. No committed data is lost on failover.
- **RTO 10s–2min** for automatic failover. Plan your application's reconnect logic (retry with exponential back-off) to tolerate this window.
- **Private Service Access (PSA)** is required for private IP connectivity to managed services. Two resources: an allocated IP range + a service networking connection.
- **Terraform manages configuration, not events.** HA-enabled/disabled is configuration. Triggering a switchover is an event. The `null_resource` pattern bridges the gap pragmatically but breaks Terraform's declarative model — use it knowingly.
- **The timestamp trigger pattern** (`triggers = { timestamp = var.failover_timestamp }`) is the correct way to make a `null_resource` provisioner re-run on demand. A boolean trigger cannot be re-triggered without taint.
- **Planned switchover ≠ automatic failover**. The operator controls a planned switchover; GCP controls automatic failover. Both result in the same zone swap, but planned switchovers have no data loss because the operator initiates them at a safe moment.
- **Secrets in state** — the database password is stored in Terraform state. For production, use Secret Manager and reference the secret version from Terraform (`google_secret_manager_secret_version` data source) rather than generating and storing credentials directly.

---

## Further Reading

- [Cloud SQL high availability overview](https://cloud.google.com/sql/docs/postgres/high-availability)
- [Cloud SQL planned switchover](https://cloud.google.com/sql/docs/postgres/replication/manage-failover-replica#performing_a_manual_failover)
- [Memorystore for Redis high availability](https://cloud.google.com/memorystore/docs/redis/high-availability)
- [Private Service Access](https://cloud.google.com/vpc/docs/private-services-access)
- [Terraform null_resource](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource)
