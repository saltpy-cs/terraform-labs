terraform {
  required_version = ">= 1.6"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# The random provider generates stable random values stored in state.
# This generates a two-word pet name like "vocal-hawk".
resource "random_pet" "name" {
  length    = 2
  separator = "-"
}

# The null_resource does nothing by itself. Its value is in the provisioner
# and in demonstrating how triggers create implicit dependencies.
resource "null_resource" "hello" {
  # triggers: when any value here changes, the null_resource is replaced.
  # This creates an implicit dependency on random_pet.name.
  triggers = {
    name = random_pet.name.id
  }

  provisioner "local-exec" {
    command = "echo 'Hello, ${random_pet.name.id}!'"
  }
}

# A random string — demonstrates another resource type and shows
# how multiple resources coexist in state.
resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

output "pet_name" {
  description = "The generated pet name"
  value       = random_pet.name.id
}

output "suffix" {
  description = "The random suffix string"
  value       = random_string.suffix.result
}

output "combined" {
  description = "Pet name combined with suffix — shows expression syntax"
  value       = "${random_pet.name.id}-${random_string.suffix.result}"
}
