# OpenClaw on GCP Cloud Run — Family Telegram Bot

Self-host [alpine/openclaw](https://github.com/alpine-chat/openclaw) as a Telegram bot for your family, running on GCP Cloud Run with **zero idle cost** and automatic HTTPS.

## Architecture

```
Family → Telegram → [Webhook POST] → Cloud Run (OpenClaw) → LLM API
                                             ↓
                                    GCS Bucket (memory files)
                                    per-user persistent context
```

**Why Cloud Run over a VM:**

| | e2-micro VM | Cloud Run |
|---|---|---|
| Cost idle | $0 (free tier) | $0 (scales to zero) |
| Cost active | $0 (free tier) | ~$0–$3/mo |
| Cold start | None | 2–5 sec after idle |
| Memory persistence | Local disk | GCS bucket |
| Telegram mode | Long polling | Webhook |
| HTTPS | Manual | Auto (managed) |

---

## Prerequisites

- GCP project with billing enabled
- [`gcloud` CLI](https://cloud.google.com/sdk/docs/install) installed and authenticated (`gcloud auth login`)
- [`terraform`](https://developer.hashicorp.com/terraform/install) >= 1.0
- A Telegram bot token (see Phase 1 below)
- At least one LLM API key (see Phase 2 below)

---

## Setup

### Phase 1 — Create a Telegram Bot (5 min)

1. Open Telegram and message **@BotFather**
2. Send `/newbot` and follow the prompts — choose a name and username
3. Copy the **bot token** (format: `1234567890:AABBCCDDEEFFaabbccddeeff...`)
4. Each family member messages **@userinfobot** to get their numeric **user ID**
5. Optional: in BotFather → `/mybots` → Bot Settings → Group Privacy → **OFF** (needed for group chats)

### Phase 2 — Get an LLM API Key (5 min)

| Provider | Sign-up | Free Tier | Recommended for |
|---|---|---|---|
| **Groq** | [console.groq.com](https://console.groq.com) | 6 000 tokens/min, Llama 3.3 70B | Starting point — fast & free |
| **Google Gemini** | [aistudio.google.com](https://aistudio.google.com/app/apikey) | 15 RPM, 1M tokens/day | High volume use |
| **Anthropic** | [console.anthropic.com](https://console.anthropic.com) | Pay-per-use | Best quality (Claude) |

You only need one. Groq is the recommended starting point — free and very capable.

### Phase 3 — Configure Terraform

```bash
cd openclaw-gcp
cp .env.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars`:

```hcl
project_id         = "your-gcp-project-id"
telegram_bot_token = "1234567890:AABBCCDDEEFFaabbccddeeff..."
allowed_user_ids   = "123456789,987654321"   # comma-separated family IDs
groq_api_key       = "gsk_..."               # at least one LLM key
```

> `terraform.tfvars` is in `.gitignore` — it will never be committed.

### Phase 4 — Deploy

```bash
export TELEGRAM_BOT_TOKEN="1234567890:AABBCCDDEEFFaabbccddeeff..."
./scripts/deploy.sh your-gcp-project-id
```

The script:
1. Enables Cloud Run, Secret Manager, Storage, and IAM APIs
2. Runs `terraform apply` (creates all GCP resources)
3. Registers the Cloud Run URL as the Telegram webhook automatically

**Expected output:**
```
=== Deployment Summary ===
  Service URL:    https://openclaw-family-abc123-uc.a.run.app
  Webhook URL:    https://openclaw-family-abc123-uc.a.run.app/telegram/webhook
  Memory bucket:  gs://your-project-openclaw-memory/

Webhook registered successfully!
```

### Phase 5 — Verify

```bash
# Check webhook is registered
curl "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo" | python3 -m json.tool

# Send a test message to your bot on Telegram
# First response may take 2–5 seconds (cold start) — subsequent messages are instant

# Check Cloud Run logs
gcloud run logs read --service openclaw-family --region us-central1 --limit 30

# Browse memory files (appear after first conversation)
gsutil ls gs://YOUR_PROJECT-openclaw-memory/
```

---

## Usage

Once deployed, family members can message the bot directly or in a group chat.

### Adding a New Family Member

1. They message **@userinfobot** to get their user ID
2. Update `allowed_user_ids` in `terraform/terraform.tfvars`
3. Apply the change:
   ```bash
   cd terraform && terraform apply
   ```

Or update without Terraform:
```bash
gcloud run services update openclaw-family \
  --region us-central1 \
  --update-env-vars ALLOWED_USER_IDS="id1,id2,id3,new_id"
```

### Memory

Each family member gets **isolated persistent memory** stored in the GCS bucket, keyed by their Telegram user ID. The bot remembers context across conversations automatically.

Browse memory files:
```bash
gsutil ls gs://YOUR_PROJECT-openclaw-memory/
```

Clear a specific user's memory:
```bash
gsutil rm gs://YOUR_PROJECT-openclaw-memory/USER_ID/**
```

---

## Operations

### Update the OpenClaw Image

```bash
gcloud run deploy openclaw-family \
  --image alpine/openclaw:latest \
  --region us-central1
```

### View Logs

```bash
# Last 50 log lines
gcloud run logs read --service openclaw-family --region us-central1 --limit 50

# Stream live logs
gcloud beta run services logs tail openclaw-family --region us-central1
```

### Update an Environment Variable

```bash
gcloud run services update openclaw-family \
  --region us-central1 \
  --update-env-vars ALLOWED_USER_IDS="id1,id2,id3"
```

### Rotate an API Key

```bash
# Add a new secret version
echo -n "new-key-value" | gcloud secrets versions add openclaw-groq-api-key --data-file=-

# Cloud Run will pick it up on next cold start (or redeploy to force it)
gcloud run deploy openclaw-family --image alpine/openclaw:latest --region us-central1
```

### Re-register the Webhook

If the Cloud Run URL ever changes (rare):
```bash
export TELEGRAM_BOT_TOKEN="..."
./scripts/register_webhook.sh
```

### Tear Down

```bash
cd terraform && terraform destroy
```

---

## Cost

| Resource | Free Tier | Family Usage | Cost |
|---|---|---|---|
| Cloud Run requests | 2M/month | ~3K/month | $0 |
| Cloud Run compute (512Mi) | 360K GB-s/month | ~10K GB-s/month | $0 |
| GCS memory storage | 5 GB free | <10 MB | $0 |
| GCS operations | 5K ops free | ~1K/month | $0 |
| Secret Manager | 6 secrets free | 4 secrets | $0 |
| **Total** | | | **$0/month** |

Heavy use (10+ family members active daily) may reach $1–3/month on compute. LLM costs remain $0 with Groq or Gemini free tiers.

---

## Project Structure

```
openclaw-gcp/
├── .env.example                  # Template for terraform/terraform.tfvars
├── .gitignore                    # Excludes tfstate, tfvars, .env files
├── terraform/
│   ├── main.tf                   # All GCP resources (Cloud Run, GCS, IAM, secrets)
│   ├── variables.tf              # Input variables (project, keys, allowed user IDs)
│   └── outputs.tf                # service_url, webhook_url, memory_bucket
└── scripts/
    ├── deploy.sh                 # Full deploy: APIs → terraform → webhook registration
    └── register_webhook.sh       # Register Cloud Run URL with Telegram setWebhook
```

### GCP Resources Created

| Resource | Name | Purpose |
|---|---|---|
| Cloud Run service | `openclaw-family` | Runs the OpenClaw container |
| GCS bucket | `PROJECT-openclaw-memory` | Persistent per-user memory |
| Service account | `openclaw-family@...` | Least-privilege identity for Cloud Run |
| Secret | `openclaw-telegram-bot-token` | Telegram bot token |
| Secret | `openclaw-groq-api-key` | Groq API key |
| Secret | `openclaw-gemini-api-key` | Gemini API key (if provided) |
| Secret | `openclaw-anthropic-api-key` | Anthropic API key (if provided) |

---

## Troubleshooting

**Bot doesn't respond after first deploy**
- Check webhook: `curl "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo"`
- Check logs: `gcloud run logs read --service openclaw-family --region us-central1`
- First response after idle takes 2–5 seconds (cold start) — send a second message if the first gets no reply

**`Forbidden` error in logs**
- The user's Telegram ID is not in `ALLOWED_USER_IDS`
- Add their ID and run `terraform apply` or update via `gcloud run services update`

**`Secret not found` error**
- The secret version may not have been created (empty API key variable)
- Add the key to `terraform.tfvars` and run `terraform apply`

**Memory not persisting**
- Check the GCS bucket: `gsutil ls gs://YOUR_PROJECT-openclaw-memory/`
- Verify the service account has `storage.objectAdmin` on the bucket: `gcloud projects get-iam-policy PROJECT_ID`

**Webhook returns `{"ok":false}`**
- The Cloud Run service may still be deploying — wait 30 seconds and re-run `register_webhook.sh`
- Ensure the service URL is publicly reachable (the `allUsers` IAM binding must be applied)
