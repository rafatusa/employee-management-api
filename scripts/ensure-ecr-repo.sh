#!/usr/bin/env bash
#
# Ensure the ECR repository exists before the image is pushed.
#
# WHY THIS EXISTS:
# The pipeline backbone runs image_build_push BEFORE provision, so at push time
# terraform has not yet created anything. Rather than reorder the backbone (the
# platform mandates provision -> configure -> verify) the repository is created
# here, idempotently, and then ADOPTED into terraform state by
# scripts/import-ecr-repo.sh on the next provision run.
#
# The settings below intentionally mirror infra/ecr.tf so that terraform sees no
# drift after the import. If you change one, change the other.

set -euo pipefail

REPO_NAME="${ECR_REPOSITORY:?ECR_REPOSITORY must be set}"
REGION="${AWS_REGION:-us-east-1}"

if aws ecr describe-repositories \
     --repository-names "${REPO_NAME}" \
     --region "${REGION}" >/dev/null 2>&1; then
  echo "ECR repository '${REPO_NAME}' already exists in ${REGION}."
  exit 0
fi

echo "Creating ECR repository '${REPO_NAME}' in ${REGION}..."
aws ecr create-repository \
  --repository-name "${REPO_NAME}" \
  --region "${REGION}" \
  --image-tag-mutability MUTABLE \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=AES256 \
  --tags "Key=Project,Value=${REPO_NAME}" "Key=ManagedBy,Value=udap" \
  >/dev/null

echo "Created ECR repository '${REPO_NAME}'."
