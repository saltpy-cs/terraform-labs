locals {
  # ── enabled_envs ──────────────────────────────────────────────────────────
  # Filter var.environments: include an env if it is NOT "prod",
  # OR if it IS "prod" and var.enable_production is true.
  # When enable_production=false the prod entry is excluded.
  enabled_envs = [
    for env in var.environments : env
    if env != "prod" || var.enable_production
  ]

  # ── instance_names ────────────────────────────────────────────────────────
  # Build a list of "<project_name>-<env>" strings for all enabled environments.
  # Result (all envs enabled): ["tf-lab08-dev", "tf-lab08-staging", "tf-lab08-prod"]
  instance_names = [
    for env in local.enabled_envs : "${var.project_name}-${env}"
  ]

  # ── env_map ───────────────────────────────────────────────────────────────
  # Build a map from environment name to its instance configuration.
  # Only includes enabled environments.
  # Result shape: { "dev" = { machine_type = "e2-micro", ... }, ... }
  env_map = {
    for env in local.enabled_envs : env => var.instance_config[env]
  }

  # ── common_labels ─────────────────────────────────────────────────────────
  # merge() combines N maps; later maps win on key conflicts.
  # These labels are applied to every resource via the for_each instances.
  common_labels = merge(
    {
      managed_by = "terraform"
      project    = var.project_name
      lab        = "08-complex-expressions"
    }
  )

  # ── firewall_allow_rules ──────────────────────────────────────────────────
  # Transform var.allowed_ports (list of strings) into a list of objects
  # suitable for use in a dynamic "allow" block inside google_compute_firewall.
  # Each element has a port string and a fixed protocol.
  firewall_allow_rules = [
    for port in var.allowed_ports : {
      port     = port
      protocol = "tcp"
    }
  ]
}
