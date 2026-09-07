#!/usr/bin/env bash
#
# Adopt the pre-created ECR repository into terraform state.
#
# WHY THIS EXISTS:
# scripts/ensure-ecr-repo.sh creates the repository during image_build_push,
# which runs BEFORE provision. Without this import the first `terraform apply`
# would try to create a repository that already exists and fail with
# RepositoryAlreadyExistsException.
#
# This is NOT a workaround for lost state — the platform's backend key is
# deterministic and state is intact. It is a deliberate adoption of a resource
# that must exist earlier in the run than terraform executes.
#
# Idempotent: if the resource is already in state, or the repository does not
# exist yet, this exits cleanly and lets terraform do the normal thing.
#
# Must run from the infra/ directory, AFTER `terraform init`.

set -euo pipefail

ADDR="aws_ecr_repository.app"
REPO_NAME="${TF_VAR_project_name:?TF_VAR_project_name must be set}"

# Already tracked? Nothing to do.
if terraform state list 2>/dev/null | grep -qx "${ADDR}"; then
  echo "${ADDR} is already in terraform state."
  exit 0
fi

# Not created yet (e.g. a fresh infrastructure-only run)? Let terraform create it.
if ! aws ecr describe-repositories \
       --repository-names "${REPO_NAME}" \
       --region "${AWS_REGION:-us-east-1}" >/dev/null 2>&1; then
  echo "ECR repository '${REPO_NAME}' does not exist yet; terraform will create it."
  exit 0
fi

echo "Importing existing ECR repository '${REPO_NAME}' into ${ADDR}..."
# terraform import reads variables exactly like apply does; the provision
# stage's TF_VAR_* env covers them, so this cannot prompt on stdin.
terraform import -input=false "${ADDR}" "${REPO_NAME}"
echo "Import complete."
