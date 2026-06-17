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
cat ../q03/bucket-name.txt
cat ../q09/import-bucket.txt
cat ../q04/vpc-selflink.txt
```

The setup provisions:
- A GCS bucket (random suffix) for use as a remote state backend — name written to `q03/bucket-name.txt`
- A second GCS bucket for the import exercise — name written to `q09/import-bucket.txt`
- A VPC network named `practice-vpc` — self_link written to `q04/vpc-selflink.txt`
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

After you have finished and recorded your score, run the cleanup script from the repo root:

```bash
./terraform-labs/practice-test/cleanup.sh
```

The script handles everything in order:

1. **Destroys resources** in each question directory (handling edge cases such as the Q03 remote backend, Q09's imported bucket, and Q10's workspaces).
2. **Removes all `q*/` directories** from `practice-test/`.
3. **Prompts before destroying setup infrastructure** (GCS buckets and VPC) — the only resources that incur ongoing cost.

> The GCS buckets and VPC network created by setup will incur minimal cost if left running.
> Always confirm the setup destroy prompt (or run `terraform destroy` in `practice-test/setup/` manually) when you are done.
