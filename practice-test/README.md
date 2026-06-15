# Terraform Certification Practice Test

A timed, hands-on exam simulation covering both the **Terraform Associate (003)** and
**Terraform Authoring and Operations Professional** exam objectives. Questions are weighted
toward Associate (82 of 100 points) with three Professional-level questions at the end.

This test simulates real exam conditions: you write actual Terraform code, run CLI commands,
and verify your results against a live AWS environment. There are no multiple-choice questions.

---

## Format

| Item | Detail |
|------|--------|
| Questions | 12 |
| Total points | 100 |
| Suggested time | 90 minutes |
| Pass mark | 70 points |
| Distinction | 85 points |

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

---

## Prerequisites

- Terraform >= 1.6 installed (`terraform version`)
- AWS CLI configured with credentials for `us-east-1` (`aws sts get-caller-identity`)
- The practice environment has been provisioned (see Setup below)
- A working directory at `~/tf-practice/` (created by setup)

---

## Setup

The setup configuration creates a small AWS environment that several questions operate against.
Run it once before starting the timer.

```bash
# From the repo root
cd terraform-labs/practice-test/setup

terraform init
terraform apply -auto-approve

# Verify the output files exist
cat /tmp/practice-bucket-name.txt
cat /tmp/practice-import-bucket.txt
cat /tmp/practice-vpc-id.txt
```

The setup provisions:
- An S3 bucket (random suffix) for use as a remote state backend — name written to `/tmp/practice-bucket-name.txt`
- A second S3 bucket for the import exercise — name written to `/tmp/practice-import-bucket.txt`
- Looks up the default VPC and writes its ID to `/tmp/practice-vpc-id.txt`
- Creates the template file for Q7 at `~/tf-practice/q07/template.txt.tpl`
- Creates the base working directory `~/tf-practice/`

Setup takes approximately 30–60 seconds. Do not start the timer until `terraform apply` completes.

---

## Scoring

| Score | Result |
|-------|--------|
| 85–100 | Distinction — ready for both exams |
| 70–84 | Pass — solid Associate readiness, review Professional gaps |
| 55–69 | Near miss — revisit labs covering missed questions |
| < 55 | Needs more practice — review core concepts before testing |

Each question is scored as complete or incomplete — there is no partial credit.

After completing each question, run the verification command listed in `questions.md`.
Mark it complete only when the verification command produces the expected output.

---

## Cleanup

After you have finished and recorded your score, destroy all resources to avoid ongoing charges.

```bash
# Destroy question resources (null_resource and local providers only — free)
# These have no cloud cost but clean up state files:
for q in q01 q02 q04 q05 q06 q07 q08 q10 q11 q12; do
  dir="$HOME/tf-practice/$q"
  if [ -d "$dir" ]; then
    echo "Destroying $q..."
    terraform -chdir="$dir" destroy -auto-approve 2>/dev/null || true
  fi
done

# Q09 and Q03 touch real S3 state — clean up manually if needed
rm -f /tmp/tf-practice.txt

# Destroy the setup infrastructure (removes the S3 buckets)
cd terraform-labs/practice-test/setup
terraform destroy -auto-approve
```

> The S3 buckets created by setup will incur minimal cost (a few cents at most) if left running.
> Always run `terraform destroy` in the `setup/` directory when you are done.
