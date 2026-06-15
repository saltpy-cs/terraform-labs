# Lab 03 — State Management

## Objectives

By the end of this lab you will be able to:

- Explain what Terraform state is, where it lives, and why it exists
- Configure an S3 remote backend with DynamoDB state locking
- Use `terraform state` subcommands: `list`, `show`, `mv`, `rm`
- Use `terraform import` to bring an existing, manually-created resource under Terraform management
- Explain the bootstrapping problem and how a two-phase approach solves it

---

## Concepts

### What is Terraform state?

Terraform needs to map the resources declared in your configuration to real objects in the cloud. It stores this mapping in a **state file** — a JSON document that records every resource it manages, including its full attribute values.

Without state, Terraform would have no way to:
- Know whether a resource already exists (so it can update rather than recreate)
- Track resource IDs assigned by the provider (e.g., `vpc-0a1b2c3d`)
- Calculate a diff between the desired configuration and the current reality

The default state file is `terraform.tfstate` in the working directory (local state). A backup copy is kept in `terraform.tfstate.backup`.

### The state file structure

The state file is JSON with this top-level shape:

```json
{
  "version": 4,
  "terraform_version": "1.9.0",
  "serial": 5,
  "lineage": "a3f1d...",
  "outputs": { ... },
  "resources": [
    {
      "mode": "managed",
      "type": "aws_s3_bucket",
      "name": "app_data",
      "provider": "provider[\"registry.terraform.io/hashicorp/aws\"]",
      "instances": [
        {
          "schema_version": 0,
          "attributes": {
            "bucket": "my-bucket-name",
            "arn": "arn:aws:s3:::my-bucket-name",
            ...
          }
        }
      ]
    }
  ]
}
```

Key fields:
- **`serial`** — incremented on every write; used to detect conflicts
- **`lineage`** — a UUID assigned when state is first created; two states with different lineages are from different workspaces and should never be merged
- **`resources`** — the array of managed objects

### Local state vs remote state

Local state is fine for learning and solo projects, but creates real problems in teams:

| Problem | What goes wrong |
|---|---|
| State lives on one machine | Others can't run `terraform plan` |
| No locking | Two people apply simultaneously → corrupted state |
| No history | Hard to see what changed and when |
| Sensitive values in plaintext | State contains secrets (passwords, tokens) in clear text |

**Remote state** solves all four: a shared backend stores the file, locking prevents concurrent writes, versioning provides history, and encryption protects secrets at rest.

### State backends

A **backend** defines:
1. **Where** state is stored (e.g., S3 bucket)
2. **How** locking works (e.g., DynamoDB)

The backend is configured in the `terraform` block:

```hcl
terraform {
  backend "s3" {
    bucket         = "my-tf-state-bucket"
    key            = "envs/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }
}
```

The `key` is the path within the bucket — think of it as a file path. A common convention is `<project>/<environment>/terraform.tfstate`.

### S3 backend: the standard AWS choice

The S3 backend is the most widely used backend for AWS-based teams:

- **S3** stores the state file. Enable versioning so you can roll back to previous state.
- **Server-side encryption** (SSE-S3 or SSE-KMS) encrypts the state at rest.
- **DynamoDB** provides locking via a single-row item keyed on `LockID`. When Terraform starts an operation that writes state, it puts an item in DynamoDB. When it finishes (or crashes), the item is deleted. If the item already exists, the operation is blocked.

### State locking in detail

When Terraform acquires a lock, it writes a `LockInfo` record to DynamoDB with fields including:
- `ID` — a UUID for this lock
- `Operation` — `plan` or `apply`
- `Who` — the username and hostname
- `Created` — timestamp

If another process holds the lock, you'll see:

```
Error: Error acquiring the state lock

  Error message: ConditionalCheckFailedException
  Lock Info:
    ID:        9a3f...
    Path:      my-bucket/terraform.tfstate
    Operation: OperationTypeApply
    Who:       alice@workstation
    Version:   1.9.0
    Created:   2024-01-15 10:32:11
```

If Terraform crashes or is killed mid-apply, the lock may remain. You can release a stuck lock with:

```
terraform force-unlock <LOCK_ID>
```

### The `terraform state` subcommands

These commands operate on the state file directly without making any cloud API calls (except `import`).

| Command | When to use it |
|---|---|
| `terraform state list` | List all resources in state |
| `terraform state show <addr>` | Print all attributes of one resource |
| `terraform state mv <src> <dst>` | Rename or move a resource in state (without destroying it) |
| `terraform state rm <addr>` | Remove a resource from state (without destroying it) |
| `terraform state pull` | Print the raw state JSON to stdout |
| `terraform state push` | Overwrite remote state with a local file (dangerous) |

**`state mv`** is essential when refactoring. If you rename a resource block from `aws_s3_bucket.old` to `aws_s3_bucket.new` without using `state mv`, Terraform will destroy the old bucket and create a new one. With `state mv`, it just updates the pointer in state.

**`state rm`** is used when you want Terraform to stop managing a resource but do not want it destroyed. After `state rm`, the resource still exists in AWS but Terraform no longer tracks it.

### `terraform import`

`terraform import` is the inverse of normal Terraform workflow. Instead of Terraform creating a resource from your config, you're telling Terraform "this real resource already exists — start tracking it."

Workflow:
1. Write the resource block in your `.tf` files (attributes can be approximate at first)
2. Run `terraform import <resource_address> <provider_id>`
3. Run `terraform plan` — Terraform shows what config changes are needed to match reality
4. Update your config to match
5. Run `terraform plan` — should show no changes

Example:
```bash
terraform import aws_s3_bucket.manual my-existing-bucket-name
```

The provider ID format varies by resource type — always check the Terraform Registry docs for the "Import" section.

### The bootstrapping problem

Here is the chicken-and-egg problem with remote state:

- You want Terraform to store its state in S3 + DynamoDB
- But S3 and DynamoDB are AWS resources
- You could manage them with Terraform
- But that Terraform config also needs somewhere to store *its* state

**Solution: two-phase bootstrap**

1. **`bootstrap/`** — a minimal Terraform config that creates the S3 bucket and DynamoDB table. This config uses *local* state (acceptable because it manages only these two infrastructure resources, which rarely change).
2. **`app/`** — your main config that uses the S3 bucket and DynamoDB table from step 1 as its remote backend.

This is a standard pattern in production. Some teams go further and manage the bootstrap resources with a separate tool (e.g., CloudFormation or the AWS CLI) to avoid state entirely.

---

## Setup

### Prerequisites

- AWS CLI configured with credentials (`aws configure` or environment variables)
- Terraform >= 1.5 installed
- Your AWS credentials need permissions for: S3, DynamoDB, IAM (to create/delete these resources)

### Verify AWS access

```bash
aws sts get-caller-identity
```

Expected output:
```json
{
    "UserId": "AKIAIOSFODNN7EXAMPLE",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/your-user"
}
```

---

## Exercises

### Exercise 1: Bootstrap — create the state backend infrastructure

The `bootstrap/` directory creates the S3 bucket and DynamoDB table that will store your remote state.

```bash
cd terraform/bootstrap
terraform init
```

Expected output (abbreviated):
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Finding hashicorp/random versions matching "~> 3.0"...
- Installing hashicorp/aws v5.x.x...
- Installing hashicorp/random v3.x.x...

Terraform has been successfully initialized!
```

```bash
terraform apply
```

Review the plan. You should see:
- `aws_s3_bucket.state` — will be created
- `aws_s3_bucket_versioning.state` — will be created
- `aws_s3_bucket_server_side_encryption_configuration.state` — will be created
- `aws_dynamodb_table.locks` — will be created
- `random_id.suffix` — will be created

Type `yes` to confirm.

Expected output (abbreviated):
```
Apply complete! Resources: 5 added, 0 changed, 0 destroyed.

Outputs:

bucket_name = "tf-lab03-state-a1b2c3d4"
table_name  = "tf-lab03-locks"
```

**Note the bucket name and table name — you will need them in Exercise 3.**

---

### Exercise 2: Inspect the local state file

The bootstrap config uses local state. Examine it:

```bash
cat terraform.tfstate | python3 -m json.tool | head -80
```

Expected output (abbreviated):
```json
{
    "version": 4,
    "terraform_version": "1.x.x",
    "serial": 1,
    "lineage": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "outputs": {
        "bucket_name": {
            "value": "tf-lab03-state-a1b2c3d4",
            "type": "string"
        }
    },
    "resources": [
        {
            "mode": "managed",
            "type": "aws_s3_bucket",
            "name": "state",
            ...
            "instances": [
                {
                    "attributes": {
                        "bucket": "tf-lab03-state-a1b2c3d4",
                        "arn": "arn:aws:s3:::tf-lab03-state-a1b2c3d4",
                        ...
                    }
                }
            ]
        }
    ]
}
```

Notice:
- `serial` is 1 — this is the first write
- `lineage` is a UUID assigned at init time — it uniquely identifies this state chain
- The `resources` array contains every attribute of every resource

```bash
# Count how many resources are tracked
cat terraform.tfstate | python3 -c "import json,sys; s=json.load(sys.stdin); print(f'{len(s[\"resources\"])} resources')"
```

---

### Exercise 3: Configure the remote backend in `app/`

Open `terraform/app/main.tf`. Find the backend configuration block. It currently has placeholder values.

Replace the placeholder bucket name and table name with the values from Exercise 1:

```hcl
terraform {
  backend "s3" {
    bucket         = "tf-lab03-state-a1b2c3d4"   # replace with your bucket_name output
    key            = "lab03/app/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tf-lab03-locks"             # replace with your table_name output
    encrypt        = true
  }
}
```

Save the file.

---

### Exercise 4: Initialize the app with the remote backend

```bash
cd ../app
terraform init
```

Because you've configured a remote backend, Terraform prompts you to migrate any existing local state. Since this is a fresh directory there is nothing to migrate, but note the message:

```
Initializing the backend...

Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.

Initializing provider plugins...
...

Terraform has been successfully initialized!
```

```bash
terraform plan
```

You should see one resource to create: `aws_s3_bucket.app_data`.

```bash
terraform apply
```

Type `yes`. Expected:
```
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

app_bucket_arn  = "arn:aws:s3:::tf-lab03-app-dev-xxxx"
app_bucket_name = "tf-lab03-app-dev-xxxx"
```

---

### Exercise 5: Verify state is stored in S3

```bash
aws s3 ls s3://<your-bucket-name>/
```

Expected output:
```
                           PRE lab03/
```

```bash
aws s3 ls s3://<your-bucket-name>/lab03/app/
```

Expected output:
```
2024-01-15 10:45:23        123 terraform.tfstate
```

You can even download and read the state file from S3 directly:

```bash
aws s3 cp s3://<your-bucket-name>/lab03/app/terraform.tfstate - | python3 -m json.tool
```

---

### Exercise 6: Verify the DynamoDB lock table

```bash
aws dynamodb describe-table --table-name tf-lab03-locks --query 'Table.{Status:TableStatus,Items:ItemCount}'
```

Expected output:
```json
{
    "Status": "ACTIVE",
    "Items": 0
}
```

The table is empty because no lock is held right now. Start an apply in one terminal and check again in another to see the lock item appear.

---

### Exercise 7: `terraform state list` — see all managed resources

From the `app/` directory:

```bash
terraform state list
```

Expected output:
```
aws_s3_bucket.app_data
```

This lists every resource address in state. Resource addresses take the form `<type>.<name>` for root-level resources, or `module.<module_name>.<type>.<name>` for resources inside modules.

---

### Exercise 8: `terraform state show` — inspect a resource

```bash
terraform state show aws_s3_bucket.app_data
```

Expected output (abbreviated):
```
# aws_s3_bucket.app_data:
resource "aws_s3_bucket" "app_data" {
    arn                         = "arn:aws:s3:::tf-lab03-app-dev-xxxx"
    bucket                      = "tf-lab03-app-dev-xxxx"
    bucket_domain_name          = "tf-lab03-app-dev-xxxx.s3.amazonaws.com"
    hosted_zone_id              = "Z3AQBSTGFYJSTF"
    id                          = "tf-lab03-app-dev-xxxx"
    object_lock_enabled         = false
    region                      = "us-east-1"
    request_payer               = "BucketOwner"
    tags                        = {}
    tags_all                    = {}

    grant { ... }
    versioning { ... }
}
```

This is the full attribute map Terraform has recorded for this resource. Note that this is what Terraform *last saw*, not necessarily what is in AWS right now — that is what the next exercise is about.

---

### Exercise 9: Observe state drift

State drift occurs when the real infrastructure diverges from what Terraform has recorded.

1. In the AWS Console (or via the CLI), add a tag to the S3 bucket:

```bash
aws s3api put-bucket-tagging \
  --bucket <your-app-bucket-name> \
  --tagging 'TagSet=[{Key=manual,Value=true}]'
```

2. Now run `terraform state show` again — you will NOT see the new tag. State still shows the old snapshot.

3. Run `terraform plan` — this is where drift is detected:

```bash
terraform plan
```

Expected output:
```
~ aws_s3_bucket.app_data
  ~ tags     = {} -> null
  ~ tags_all = {
      + "manual" = "true"
    } -> {}
```

Terraform detects the drift by calling the AWS API and comparing the live attributes to the state file. The plan shows it will remove the manual tag.

4. Apply to reconcile (bring reality back in line with config):

```bash
terraform apply
```

---

### Exercise 10: `terraform state mv` — rename a resource without recreating it

Suppose you want to rename `aws_s3_bucket.app_data` to `aws_s3_bucket.primary`. Normally renaming the HCL block would cause Terraform to destroy the old bucket and create a new one.

`state mv` lets you rename the pointer in state before you rename the block in code.

**Step 1:** Move the resource in state:

```bash
terraform state mv aws_s3_bucket.app_data aws_s3_bucket.primary
```

Expected output:
```
Move "aws_s3_bucket.app_data" to "aws_s3_bucket.primary"
Successfully moved 1 object(s).
```

**Step 2:** Update `main.tf` — rename the resource block from `app_data` to `primary` (and update any references to it in `outputs.tf`).

**Step 3:** Verify no destroy/recreate:

```bash
terraform plan
```

Expected output:
```
No changes. Your infrastructure matches the configuration.
```

**Step 4:** Move it back for the rest of the exercises:

```bash
terraform state mv aws_s3_bucket.primary aws_s3_bucket.app_data
```

And revert the name change in `main.tf` and `outputs.tf`.

---

### Exercise 11: `terraform import` — adopt a manually-created resource

This exercise simulates a common real-world scenario: a colleague created a resource by hand (or via the console) and you need to bring it under Terraform management.

**Step 1:** Create an S3 bucket manually (outside Terraform):

```bash
# Use a unique name — S3 bucket names are globally unique
MANUAL_BUCKET="tf-lab03-manual-$(date +%s)"
echo "Manual bucket name: $MANUAL_BUCKET"

aws s3 mb s3://$MANUAL_BUCKET
```

Expected output:
```
make_bucket: tf-lab03-manual-1705315200
```

**Step 2:** Add a resource block for this bucket to `terraform/app/main.tf`:

```hcl
resource "aws_s3_bucket" "manual" {
  bucket = "tf-lab03-manual-XXXXXXXXXX"   # replace with your actual bucket name
}
```

**Step 3:** Without importing, run `terraform plan`:

```bash
terraform plan
```

Terraform will propose to *create* the bucket (it doesn't know about it yet). If you applied, it would fail because the bucket already exists.

**Step 4:** Import the bucket:

```bash
terraform import aws_s3_bucket.manual tf-lab03-manual-XXXXXXXXXX
```

Expected output:
```
aws_s3_bucket.manual: Importing from ID "tf-lab03-manual-XXXXXXXXXX"...
aws_s3_bucket.manual: Import prepared!
  Prepared aws_s3_bucket for import
aws_s3_bucket.manual: Refreshing state... [id=tf-lab03-manual-XXXXXXXXXX]

Import successful!

The resources that were imported are shown above. These resources are now in
your Terraform state and will henceforth be managed by Terraform.
```

**Step 5:** Run `terraform plan`:

```bash
terraform plan
```

You should see only minor differences (Terraform fills in computed attributes). Update your config to match and the plan should eventually show no changes.

---

### Exercise 12: Cleanup

Always destroy in the reverse order of creation — `app/` first, then `bootstrap/`.

**Destroy the app resources:**

```bash
cd terraform/app
terraform destroy
```

Type `yes`. This destroys the app S3 bucket.

**Destroy the bootstrap resources:**

```bash
cd ../bootstrap
terraform destroy
```

Type `yes`. This destroys the state S3 bucket and DynamoDB table.

> **Note:** After destroying the state bucket, the `app/` backend no longer has a home. That is fine — both configs are destroyed. If you want to rerun the lab, start from Exercise 1.

---

## Key Takeaways

- **Terraform state** is a JSON mapping between your configuration and real cloud resources. It is the source of truth for Terraform's view of the world.
- **Remote state** (S3 + DynamoDB) is the standard pattern for AWS-based teams. It solves: shared access, locking, versioning, and encryption.
- **State locking** via DynamoDB prevents two operators from corrupting state during concurrent applies.
- **`terraform state mv`** is the safe way to refactor resource names — it updates the state pointer without touching the real resource.
- **`terraform import`** is the escape hatch for manually-created resources. Write the config block first, import second, then reconcile the plan.
- **The bootstrapping problem** is real: solve it by using local state for the backend infrastructure itself, and remote state for everything else.
