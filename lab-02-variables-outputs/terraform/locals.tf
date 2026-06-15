locals {
  # Computed name prefix reused across all resources
  name_prefix = "${var.app_name}-${var.environment}"

  # Tags applied to every resource — compute once, use everywhere
  common_tags = {
    Application = var.app_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  # Derive the instance type for this environment from the variable map.
  # Falls back to t3.nano if the environment key is not found.
  instance_type = lookup(var.instance_types, var.environment, "t3.nano")

  # Build a list of resource names by combining the prefix with a count index.
  # [for i in range(var.replica_count) : ...] generates indices 0..N-1
  replica_names = [
    for i in range(var.replica_count) : "${local.name_prefix}-${i}"
  ]

  # A monitoring flag that combines the input variable with an environment rule:
  # monitoring is always forced on in prod, regardless of var.enable_monitoring.
  monitoring_enabled = var.enable_monitoring || var.environment == "prod"

  # Service endpoint string built from the service_config object variable
  service_endpoint = "${var.service_config.protocol}://0.0.0.0:${var.service_config.port}"
}
