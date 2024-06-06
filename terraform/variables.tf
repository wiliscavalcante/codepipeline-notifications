variable "aws_region" {
  description = "AWS region to deploy resources."
  type        = string
  default     = "us-east-1" # Exemplo de valor padrão, ajuste conforme necessário.
}

variable "notification_service" {
  description = "The notification service to use (Teams or GoogleChat)."
  type        = string
  default = "GoogleChat"
  # Nenhum valor padrão definido aqui; considere definir via variáveis de ambiente ou input do usuário.
}

variable "webhook_secret_name" {
  type = string
  default = "codepipeline_notifications_webhook_url_google_chat"
}