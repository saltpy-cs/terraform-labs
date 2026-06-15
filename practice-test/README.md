# Terraform Certification Practice Test

A timed, hands-on exam simulation covering both the **Terraform Associate (003)** and
**Terraform Authoring and Operations Professional** exam objectives. Questions are weighted
toward Associate (82 of 114 points) with five Professional-level questions at the end.

This test simulates real exam conditions: you write actual Terraform code, run CLI commands,
and verify your results against a live GCP environment. There are no multiple-choice questions.

---

## Format

| Item | Detail |
|------|--------|
| Questions | 14 |
| Total points | 114 |
| Suggested time | 90 minutes |
| Pass mark | 80 points (70%) |
| Distinction | 97 points (85%) |

**Allowed reference material** — you may consult:
- [registry.terraform.io](https://registry.terraform.io) — provider and module documentation
- [developer.hashicorp.com/terraform/language](https://developer.hashicorp.com/terraform/language) — language reference
- [developer.hashicorp.com/terraform/cli](https://developer.hashicorp.com/terraform/cli) — CLI reference

You may **not** use tutorials, blog posts, course materials, AI assistants, or the lab READMEs
from this course.

---

## Difficulty Spread

| Questions | Level | Points each | Subtotal |
|-----------|-------|-------------|----------|
| 1–4 | Associate | 8 | 32 |
| 5–9 | Associate+ | 10 | 50 |
| 10–12 | Professional | 6 | 18 |
| 13 | Professional | 8 | 8 |
| 14 | Professional | 6 | 6 |

---

## Prerequisites

- Terraform >= 1.6 installed (`terraform version`)
- Google Cloud SDK installed and authenticated:
  ```bash
  gcloud auth application-default login
  gcloud config set project <your-project-id>
  ```
- A GCP project with billing enabled and the Compute Engine and Storage APIs active
- The practice environment has been provisioned (see Setup below)
- A working directory at `~/tf-practice/` (created by setup)

---

## Setup

The setup configuration creates a small GCP environment that several questions operate against.
Run it once before starting the timer.

```bash
# From the repo root
cd terraform-labs/practice-test/setup

# Copy the example vars file and set your project ID
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and set gcp_project = "your-project-id"

terraform init
terraform apply -auto-approve

# Verify the output files exist
cat /tmp/practice-bucket-name.txt
cat /tmp/practice-import-bucket.txt
cat /tmp/practice-vpc-selflink.txt
```

The setup provisions:
- A GCS bucket (random suffix) for use as a remote state backend — name written to `/tmp/practice-bucket-name.txt`
- A second GCS bucket for the import exercise — name written to `/tmp/practice-import-bucket.txt`
- A VPC network named `practice-vpc` — self_link written to `/tmp/practice-vpc-selflink.txt`
- Creates the template file for Q7 at `~/tf-practice/q07/startup.sh.tpl`
- Creates the base working directory tree `~/tf-practice/`

Setup takes approximately 60–120 seconds. Do not start the timer until `terraform apply` completes.

---

## Scoring

| Score | Result |
|-------|--------|
| 97–114 | Distinction — ready for both exams |
| 80–96 | Pass — solid Associate readiness, review Professional gaps |
| 63–79 | Near miss — revisit labs covering missed questions |
| < 63 | Needs more practice — review core concepts before testing |

Each question is scored as complete or incomplete — there is no partial credit.

After completing each question, run the verification command listed in `questions.md`.
Mark it complete only when the verification command produces the expected output.

---

## Cleanup

After you have finished and recorded your score, destroy all resources to avoid ongoing charges.

```bash
# Destroy question resources (null_resource and local providers only — free)
# These have no cloud cost but clean up state files:
for q in q01 q02 q04 q05 q06 q07 q08 q10 q11 q12 q13 q14; do
  dir="$HOME/tf-practice/$q"
  if [ -d "$dir" ]; then
    echo "Destroying $q..."
    terraform -chdir="$dir" destroy -auto-approve 2>/dev/null || true
  fi
done

# Q09 and Q03 touch real GCS state — clean up manually if needed
rm -f /tmp/tf-practice.txt

# Destroy the setup infrastructure (removes the GCS buckets and VPC)
cd terraform-labs/practice-test/setup
terraform destroy -auto-approve
```

> The GCS buckets and VPC network created by setup will incur minimal cost if left running.
> Always run `terraform destroy` in the `setup/` directory when you are done.
