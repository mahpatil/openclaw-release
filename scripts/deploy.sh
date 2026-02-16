#!/usr/bin/env bash
# deploy.sh — Full deploy: enable APIs, terraform apply, register Telegram webhook
# Usage: ./scripts/deploy.sh <project-id>
#
# Prerequisites:
#   - gcloud CLI installed and authenticated (`gcloud auth login`)
#   - terraform CLI installed
#   - TELEGRAM_BOT_TOKEN exported in the environment
#   - terraform.tfvars configured (see .env.example for guidance)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

# ── Args ──────────────────────────────────────
PROJECT_ID="${1:-}"
if [[ -z "${PROJECT_ID}" ]]; then
  echo "Usage: $0 <project-id>"
  echo "  Example: $0 my-gcp-project-123"
  exit 1
fi

echo "=== OpenClaw Family Bot — Deploy ==="
echo "Project: ${PROJECT_ID}"
echo ""

# ── Set GCP project ───────────────────────────
gcloud config set project "${PROJECT_ID}"

# ── Enable required APIs ──────────────────────
echo "Enabling GCP APIs (this may take a minute)..."
gcloud services enable \
  run.googleapis.com \
  secretmanager.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  --quiet

echo "APIs enabled."
echo ""

# ── Terraform ─────────────────────────────────
echo "Running Terraform..."
cd "${TERRAFORM_DIR}"

terraform init -upgrade

terraform apply -auto-approve \
  -var="project_id=${PROJECT_ID}"

echo ""
echo "Terraform apply complete."

# ── Show outputs ──────────────────────────────
SERVICE_URL=$(terraform output -raw service_url)
GATEWAY_WS_URL=$(terraform output -raw gateway_ws_url)
WORKSPACE_BUCKET=$(terraform output -raw workspace_bucket)

echo ""
echo "=== Deployment Summary ==="
echo "  Service URL:      ${SERVICE_URL}"
echo "  Gateway WS URL:   ${GATEWAY_WS_URL}"
echo "  Workspace bucket: gs://${WORKSPACE_BUCKET}/"
echo ""
echo "=== Done! ==="
echo ""
echo "Next steps:"
echo "  1. In Claude Code, run: /gateway connect ${GATEWAY_WS_URL}"
echo "  2. Check logs: gcloud run logs read --service openclaw-family --region us-central1"
echo "  3. Browse workspace: gsutil ls gs://${WORKSPACE_BUCKET}/"
echo ""
