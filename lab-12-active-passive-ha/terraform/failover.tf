# ─── Failover Triggers ─────────────────────────────────────────────────────────
#
# IMPORTANT — read before using in production:
#
# Terraform is DECLARATIVE: it reconciles desired state with actual state.
# A planned switchover is an IMPERATIVE EVENT, not a state transition. Once
# Cloud SQL has switched over, the instance's new zone IS its desired state —
# Terraform has nothing to reconcile.
#
# The null_resource pattern below is a pragmatic escape hatch. It works, but
# it has a critical limitation: Terraform tracks whether it ran the provisioner
# by storing the `triggers` map in state. If triggers don't change, Terraform
# considers the resource up-to-date and skips the provisioner.
#
# This is why we use a TIMESTAMP as the trigger, not a boolean:
#
#   # First switchover:
#   terraform apply -var="failover_timestamp=$(date +%s)"
#   # → null_resource created, provisioner runs (Cloud SQL switches zones)
#
#   terraform apply -var="failover_timestamp=$(date +%s)"
#   # → triggers changed (new timestamp), null_resource REPLACED, provisioner runs again
#
#   terraform apply
#   # → failover_timestamp = "" → count = 0 → null_resource DESTROYED (no provisioner)
#
# The alternative: run the gcloud command directly and leave Terraform out of
# operational actions entirely. This is the purist position and is often the
# right call in production runbooks.
#
# A third option for teams that want everything-as-code: Cloud Workflows or
# a Cloud Run job can be invoked by Terraform via google_workflows_execution or
# a REST call, keeping the operational logic outside the Terraform graph.

# ─── Cloud SQL planned switchover ─────────────────────────────────────────────
#
# `gcloud sql instances failover` is a PLANNED switchover (despite the name).
# The standby is promoted to primary. The old primary becomes the new standby.
# This is a graceful operation with RPO ≈ 0 — no data loss.
#
# Cloud SQL automatically re-establishes a new standby within ~5–10 minutes.

resource "null_resource" "cloud_sql_switchover" {
  count = var.failover_timestamp != "" ? 1 : 0

  triggers = {
    # timestamp change forces resource replacement → provisioner re-runs
    timestamp = var.failover_timestamp
    instance  = google_sql_database_instance.primary.name
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Triggering Cloud SQL planned switchover for ${google_sql_database_instance.primary.name}..."
      gcloud sql instances failover ${google_sql_database_instance.primary.name} \
        --project=${var.gcp_project} \
        --quiet
      echo "Switchover initiated. Run 'gcloud sql instances describe ${google_sql_database_instance.primary.name} --project=${var.gcp_project}' to check the new primary zone."
    EOT
  }

  depends_on = [google_sql_database_instance.primary]
}

# ─── Memorystore Redis failover ────────────────────────────────────────────────
#
# Redis failover promotes the replica to primary. The data-protection-mode
# controls the safety trade-off:
#
#   "limited-data-loss"  — GCP waits until the replica has consumed all
#                          replication backlog before promoting. Slower but
#                          preserves all acknowledged writes.
#
#   "force-data-loss"    — Immediate promotion regardless of backlog.
#                          Faster, but recent writes (post-last-sync) may be lost.
#
# Redis failover is useful for:
#   - Scheduled maintenance on the primary zone
#   - Testing your application's reconnect behaviour
#   - Validating your HA configuration before you need it

resource "null_resource" "redis_failover" {
  count = var.redis_failover_timestamp != "" ? 1 : 0

  triggers = {
    timestamp = var.redis_failover_timestamp
    instance  = google_redis_instance.primary.name
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Triggering Memorystore Redis failover for ${google_redis_instance.primary.name}..."
      gcloud redis instances failover ${google_redis_instance.primary.name} \
        --region=${var.gcp_region} \
        --project=${var.gcp_project} \
        --data-protection-mode=${var.redis_data_protection_mode} \
        --quiet
      echo "Failover complete. Run 'gcloud redis instances describe ${google_redis_instance.primary.name} --region=${var.gcp_region} --project=${var.gcp_project}' to check the new primary zone."
    EOT
  }

  depends_on = [google_redis_instance.primary]
}
