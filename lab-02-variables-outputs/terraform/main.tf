terraform {
  required_version = ">= 1.6"

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.0"
    }
  }
}

# One random_id per replica — demonstrates count and local.replica_names usage
resource "random_id" "replica" {
  count = var.replica_count

  byte_length = 4

  keepers = {
    name = local.replica_names[count.index]
  }
}

# A random_pet to illustrate how locals can be composed
resource "random_pet" "app" {
  prefix    = local.name_prefix
  separator = "-"
  length    = 1
}

# An optional monitoring resource — only created when monitoring is enabled.
# Demonstrates count-based conditional resource creation (lab 08 covers this
# in more depth with the ternary operator).
resource "random_string" "monitoring_id" {
  count = local.monitoring_enabled ? 1 : 0

  length  = 12
  upper   = false
  special = false
}

# data "external" calls an external program and reads its JSON output.
# Here it calls a simple shell command to simulate reading dynamic config.
# The program must return a JSON object.
data "external" "info" {
  program = ["sh", "-c", "echo '{\"region\": \"us-east-1\", \"account\": \"123456789012\"}'"]
}
