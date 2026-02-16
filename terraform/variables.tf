variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "container_image" {
  description = "Container image to deploy (defaults to the official alpine/openclaw image on Docker Hub)"
  type        = string
  default     = "docker.io/alpine/openclaw:latest"
}

variable "region" {
  description = "GCP region for all resources"
  type        = string
  default     = "us-central1"
}

# ──────────────────────────────────────────────
# Telegram
# ──────────────────────────────────────────────
variable "telegram_bot_token" {
  description = "Telegram Bot Token from @BotFather. Required for Telegram channel support."
  type        = string
  sensitive   = true
}

variable "allowed_user_ids" {
  description = "Comma-separated Telegram user IDs allowed to DM the bot (get from @userinfobot)"
  type        = string
}

# ──────────────────────────────────────────────
# OpenClaw Gateway
# ──────────────────────────────────────────────
variable "gateway_token" {
  description = "Shared token that clients must present to connect to the gateway (OPENCLAW_GATEWAY_TOKEN). Choose any strong random string."
  type        = string
  sensitive   = true
}

# ──────────────────────────────────────────────
# LLM API Keys (at least one required)
# ──────────────────────────────────────────────
variable "groq_api_key" {
  description = "Groq API key (free tier: 6000 tokens/min, Llama 3.3 70B). Recommended starting point."
  type        = string
  sensitive   = true
  default     = ""
}

variable "gemini_api_key" {
  description = "Google Gemini API key (free tier: 15 RPM, 1M tokens/day with gemini-2.0-flash)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "anthropic_api_key" {
  description = "Anthropic API key for Claude models (pay-per-use, no free tier)."
  type        = string
  sensitive   = true
  default     = ""
}
