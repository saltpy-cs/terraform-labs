output "count_instance_names" {
  description = "Names of the count-based GCE instances. Splat expression collects all [*].name values."
  # The [*] splat operator is shorthand for [for i in google_compute_instance.web : i.name].
  # It only works on count-managed resources (not for_each).
  value = google_compute_instance.web[*].name
}

output "foreach_instance_names" {
  description = "Map of environment name to instance name for the for_each-based instances."
  # For for_each resources you must use a for expression — splat [*] does not work.
  # This produces: { "dev" = "tf-lab06-dev", "staging" = "tf-lab06-staging" }
  value = { for k, v in google_compute_instance.env : k => v.name }
}

output "network_id" {
  description = "ID of the main VPC network."
  value       = google_compute_network.main.id
}
