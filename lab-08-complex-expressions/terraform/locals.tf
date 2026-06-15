locals {
  # ── enabled_envs ──────────────────────────────────────────────────────────
  # Filter var.environments: include an env if it is NOT "prod",
  # OR if it IS "prod" and var.enable_production is true.
  # When enable_production=false, "prod" is excluded.
  enabled_envs = [
    for env in var.environments : env
    if env != "prod" || var.enable_production
  ]

  # ── instance_names ────────────────────────────────────────────────────────
  # Build a list of "<project>-<env>" strings for all enabled environments.
  instance_names = [
    for env in local.enabled_envs : "${var.project_name}-${env}"
  ]

  # ── env_map ───────────────────────────────────────────────────────────────
  # Build a map from environment name to its instance configuration.
  # Only includes enabled environments.
  # Result shape: { "dev" = { instance_type = "t3.nano", ... }, ... }
  env_map = {
    for env in local.enabled_envs : env => var.instance_config[env]
  }

  # ── common_tags ───────────────────────────────────────────────────────────
  # merge() takes N maps and combines them. Later maps win on key conflicts.
  # Here we add Terraform management metadata to every resource.
  common_tags = merge(
    {
      managed_by  = "terraform"
      project     = var.project_name
      lab         = "08-complex-expressions"
    }
  )

  # ── security_group_rules ──────────────────────────────────────────────────
  # Transform var.allowed_ports (list of numbers) into a list of objects
  # suitable for use in a dynamic "ingress" block.
  security_group_rules = [
    for port in var.allowed_ports : {
      port        = port
      description = "Allow TCP ${port}"
      cidr_blocks = port == 22 ? [var.my_ip_cidr] : ["0.0.0.0/0"]
    }
  ]
}
