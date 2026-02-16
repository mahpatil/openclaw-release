variable "project_id" {
  description = "GCP Project ID"
  type        = string
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
  description = "Telegram Bot Token from @BotFather. Required."
  type        = string
  sensitive   = true
}

variable "allowed_user_ids" {
  description = "Comma-separated list of Telegram user IDs allowed to use the bot (get from @userinfobot)"
  type        = string
  # Example: "123456789,987654321,456789123"
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
