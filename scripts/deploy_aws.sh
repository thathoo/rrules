#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_NAME="${STACK_NAME:-rrules-api-prod}"
SERVICE_NAME="${SERVICE_NAME:-rrules-api}"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-prod}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-west-2}}"
ARTIFACT_BUCKET="${ARTIFACT_BUCKET:-}"
LAMBDA_RESERVED_CONCURRENCY="${LAMBDA_RESERVED_CONCURRENCY:-5}"
API_THROTTLE_BURST_LIMIT="${API_THROTTLE_BURST_LIMIT:-10}"
API_THROTTLE_RATE_LIMIT="${API_THROTTLE_RATE_LIMIT:-5}"

if [[ -z "${ARTIFACT_BUCKET}" ]]; then
  echo "ARTIFACT_BUCKET is required. Example: ARTIFACT_BUCKET=my-lambda-artifacts-${AWS_REGION} scripts/deploy_aws.sh" >&2
  exit 1
fi

ZIP_PATH="$("${ROOT_DIR}/scripts/package_lambda.sh")"
ZIP_KEY="${SERVICE_NAME}/${ENVIRONMENT_NAME}/rrules-api-$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}').zip"

if ! aws s3api head-bucket --bucket "${ARTIFACT_BUCKET}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  if [[ "${AWS_REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${ARTIFACT_BUCKET}" --region "${AWS_REGION}"
  else
    aws s3api create-bucket \
      --bucket "${ARTIFACT_BUCKET}" \
      --region "${AWS_REGION}" \
      --create-bucket-configuration "LocationConstraint=${AWS_REGION}"
  fi
fi

aws s3 cp "${ZIP_PATH}" "s3://${ARTIFACT_BUCKET}/${ZIP_KEY}" --region "${AWS_REGION}"

aws cloudformation deploy \
  --region "${AWS_REGION}" \
  --stack-name "${STACK_NAME}" \
  --template-file "${ROOT_DIR}/infrastructure/cloudformation.yml" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    ServiceName="${SERVICE_NAME}" \
    EnvironmentName="${ENVIRONMENT_NAME}" \
    CodeS3Bucket="${ARTIFACT_BUCKET}" \
    CodeS3Key="${ZIP_KEY}" \
    LambdaReservedConcurrentExecutions="${LAMBDA_RESERVED_CONCURRENCY}" \
    ApiThrottleBurstLimit="${API_THROTTLE_BURST_LIMIT}" \
    ApiThrottleRateLimit="${API_THROTTLE_RATE_LIMIT}"

aws cloudformation describe-stacks \
  --region "${AWS_REGION}" \
  --stack-name "${STACK_NAME}" \
  --query 'Stacks[0].Outputs' \
  --output table
