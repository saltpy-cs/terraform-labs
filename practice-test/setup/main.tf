terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ---------------------------------------------------------------------------
# Random suffixes — keeps bucket names globally unique
# ---------------------------------------------------------------------------

resource "random_id" "state_bucket" {
  byte_length = 4
}

resource "random_id" "import_bucket" {
  byte_length = 4
}

# ---------------------------------------------------------------------------
# S3 bucket for remote state backend (Q3)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "state" {
  bucket        = "tf-practice-state-${random_id.state_bucket.hex}"
  force_destroy = true

  tags = {
    Purpose = "TerraformPracticeTest"
    Role    = "state-backend"
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# S3 bucket for import exercise (Q9)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "import_target" {
  bucket        = "tf-practice-import-${random_id.import_bucket.hex}"
  force_destroy = true

  tags = {
    Purpose = "TerraformPracticeTest"
    Role    = "import-exercise"
  }
}

resource "aws_s3_bucket_public_access_block" "import_target" {
  bucket = aws_s3_bucket.import_target.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# Default VPC lookup (Q4)
# ---------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

# ---------------------------------------------------------------------------
# Write environment information to well-known files
# These files are read by the practice questions at test time.
# ---------------------------------------------------------------------------

# Create the working directory tree up front so learners don't need to
resource "null_resource" "create_work_dirs" {
  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ~/tf-practice/q01
      mkdir -p ~/tf-practice/q02
      mkdir -p ~/tf-practice/q03
      mkdir -p ~/tf-practice/q04
      mkdir -p ~/tf-practice/q05/modules/tagger
      mkdir -p ~/tf-practice/q06
      mkdir -p ~/tf-practice/q07
      mkdir -p ~/tf-practice/q08
      mkdir -p ~/tf-practice/q09
      mkdir -p ~/tf-practice/q10
      mkdir -p ~/tf-practice/q11/modules/namer
      mkdir -p ~/tf-practice/q11/tests
      mkdir -p ~/tf-practice/q12
    EOT
  }
}

# Write the state bucket name for Q3
resource "null_resource" "write_state_bucket_name" {
  depends_on = [aws_s3_bucket.state, null_resource.create_work_dirs]

  triggers = {
    bucket_name = aws_s3_bucket.state.bucket
  }

  provisioner "local-exec" {
    command = "printf '%s' '${aws_s3_bucket.state.bucket}' > /tmp/practice-bucket-name.txt"
  }
}

# Write the import bucket name for Q9
resource "null_resource" "write_import_bucket_name" {
  depends_on = [aws_s3_bucket.import_target, null_resource.create_work_dirs]

  triggers = {
    bucket_name = aws_s3_bucket.import_target.bucket
  }

  provisioner "local-exec" {
    command = "printf '%s' '${aws_s3_bucket.import_target.bucket}' > /tmp/practice-import-bucket.txt"
  }
}

# Write the default VPC ID for Q4
resource "null_resource" "write_vpc_id" {
  depends_on = [null_resource.create_work_dirs]

  triggers = {
    vpc_id = data.aws_vpc.default.id
  }

  provisioner "local-exec" {
    command = "printf '%s' '${data.aws_vpc.default.id}' > /tmp/practice-vpc-id.txt"
  }
}

# Write the Q7 template file to the working directory
resource "local_file" "q07_template" {
  depends_on = [null_resource.create_work_dirs]

  filename = pathexpand("~/tf-practice/q07/template.txt.tpl")
  content  = "Hello, $${name}! You are in $${region}.\n"

  # Note: $${} is the HCL escape for a literal ${ in the content string.
  # The file written to disk will contain: Hello, ${name}! You are in ${region}.
  # which is the correct templatefile() syntax.
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "state_bucket_name" {
  description = "Name of the S3 bucket to use as the remote state backend (Q3)"
  value       = aws_s3_bucket.state.bucket
}

output "import_bucket_name" {
  description = "Name of the S3 bucket to import in Q9"
  value       = aws_s3_bucket.import_target.bucket
}

output "default_vpc_id" {
  description = "ID of the default VPC (Q4)"
  value       = data.aws_vpc.default.id
}

output "default_vpc_cidr" {
  description = "CIDR block of the default VPC — expected answer for Q4"
  value       = data.aws_vpc.default.cidr_block
}

output "q07_template_path" {
  description = "Path to the template file created for Q7"
  value       = pathexpand("~/tf-practice/q07/template.txt.tpl")
}

output "setup_complete" {
  description = "Reminder of the files written for the test"
  value = {
    state_bucket_file  = "/tmp/practice-bucket-name.txt"
    import_bucket_file = "/tmp/practice-import-bucket.txt"
    vpc_id_file        = "/tmp/practice-vpc-id.txt"
    q07_template       = "~/tf-practice/q07/template.txt.tpl"
  }
}
