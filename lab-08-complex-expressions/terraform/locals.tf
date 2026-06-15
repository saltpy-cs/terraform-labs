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

  # ── Type conversion: list → set → list ────────────────────────────────────
  #
  # toset() removes duplicates and drops ordering. The result has no index —
  # elements are identified only by their value. This is why for_each requires
  # a set or map rather than a list: list indices are fragile (renumber when
  # an item is removed), set/map keys are stable.
  #
  # Use in terraform console to see the effect:
  #   toset(["staging", "dev", "dev", "prod"])  →  {"dev", "prod", "staging"}
  env_set = toset(var.environments)

  # tolist() materialises a set as a list. Sets have no guaranteed order in
  # Terraform's type system; in practice, string sets sort alphabetically.
  # The sort is an implementation detail — do not rely on it in logic.
  env_list_sorted = tolist(toset(var.environments))

  # keys() and values() extract the two sides of a map as lists.
  # Useful when you need only one dimension of a map(object({...})).
  configured_env_names  = keys(var.instance_config)           # ["dev","prod","staging"]
  configured_env_types  = values({ for k, v in var.instance_config : k => v.machine_type })

  # ── Flattening nested structures ───────────────────────────────────────────
  #
  # Problem:
  #   var.vpc_config is map(object({ subnets = list(string) })).
  #   for_each needs a flat map with unique string keys — one entry per subnet.
  #
  # Approach:
  #   1. Outer for: range over the vpc_config map  →  one inner map per VPC
  #   2. Inner for: range over each VPC's subnet list  →  one entry per subnet
  #   3. Build a composite key: "<vpc_name>-subnet-<index>" (must be unique)
  #   4. merge([...]...) collapses the list of per-VPC maps into one flat map
  #
  # The spread operator (...) unpacks a list into individual function arguments.
  # merge() accepts N maps; without ..., you'd pass a list where N maps are
  # expected and Terraform would error.
  #
  # Result shape (with default var.vpc_config):
  #   {
  #     "dev-subnet-0"  = { vpc_name = "dev",  cidr = "10.20.1.0/24", vpc_cidr = "10.20.0.0/16" }
  #     "dev-subnet-1"  = { vpc_name = "dev",  cidr = "10.20.2.0/24", vpc_cidr = "10.20.0.0/16" }
  #     "prod-subnet-0" = { vpc_name = "prod", cidr = "10.30.1.0/24", vpc_cidr = "10.30.0.0/16" }
  #     "prod-subnet-1" = { vpc_name = "prod", cidr = "10.30.2.0/24", vpc_cidr = "10.30.0.0/16" }
  #     "prod-subnet-2" = { vpc_name = "prod", cidr = "10.30.3.0/24", vpc_cidr = "10.30.0.0/16" }
  #   }
  all_subnets = merge([
    for vpc_name, vpc in var.vpc_config : {
      for idx, cidr in vpc.subnets :
        "${vpc_name}-subnet-${idx}" => {
          vpc_name = vpc_name
          cidr     = cidr
          vpc_cidr = vpc.cidr
        }
    }
  ]...)
}
