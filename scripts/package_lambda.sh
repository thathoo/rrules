#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/.build/lambda"
ZIP_PATH="${ROOT_DIR}/.build/rrules-api.zip"
RUBY_IMAGE="${RUBY_IMAGE:-public.ecr.aws/lambda/ruby:3.4}"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required to build Lambda dependencies for Amazon Linux." >&2
  exit 1
fi

if ! command -v zip >/dev/null 2>&1; then
  echo "zip is required to create the Lambda deployment package." >&2
  exit 1
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

cp "${ROOT_DIR}/handler.rb" "${BUILD_DIR}/"
cp "${ROOT_DIR}/Gemfile" "${BUILD_DIR}/"
cp "${ROOT_DIR}/Gemfile.lock" "${BUILD_DIR}/"

docker run --rm \
  --platform linux/amd64 \
  -v "${BUILD_DIR}:/var/task" \
  -w /var/task \
  "${RUBY_IMAGE}" \
  /bin/bash -lc "dnf install -y gcc gcc-c++ make && bundle config set --local path vendor/bundle && bundle config set --local without test && bundle install && rm -rf vendor/bundle/ruby/*/cache"

rm -f "${ZIP_PATH}"
(cd "${BUILD_DIR}" && zip -qr "${ZIP_PATH}" .)

echo "${ZIP_PATH}"
