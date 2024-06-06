# Data sources para obter informações da conta e região AWS
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Criação de uma tabela no DynamoDB para gerenciamento do estado de pipelines
resource "aws_dynamodb_table" "pipeline_state" {
  name         = "pipelineState"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pipelineName"

  attribute {
    name = "pipelineName"
    type = "S"
  }
  tags = {
    Environment = "production"
    Project     = "pipelineManagement"
    Owner       = "teamName"
  }
}

# Criação de um tópico SNS para notificações de eventos do CodePipeline
resource "aws_sns_topic" "pipeline_notifications" {
  name = "pipeline-notifications"
}

# IAM role para a execução de funções Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com",
      },
    }],
  })
}

# Política IAM para permitir que a função Lambda acesse serviços necessários
resource "aws_iam_policy" "lambda_policy" {
  name        = "LambdaExecutionPolicy"
  description = "Política que permite à função Lambda acessar CloudWatch, DynamoDB, SNS e Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${aws_lambda_function.sns_to_teams_or_google_chat.function_name}:*"
      },
      {
        Effect = "Allow",
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem"
        ],
        Resource = [
          "${aws_dynamodb_table.pipeline_state.arn}"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "sns:Publish"
        ],
        Resource = "${aws_sns_topic.pipeline_notifications.arn}"
      },
      {
        Effect = "Allow",
        Action = "secretsmanager:GetSecretValue",
        Resource = "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.webhook_secret_name}-*"
      }
    ],
  })
}

# Anexação da política IAM à role da função Lambda
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Preparação do arquivo ZIP da função Lambda
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/../lambda/lambda_function.zip"
}

# Configuração da função Lambda para notificações
resource "aws_lambda_function" "sns_to_teams_or_google_chat" {
  function_name    = "SnsToTeamsOrGoogleChat"
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_exec_role.arn
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 10 

  environment {
    variables = {
      NOTIFICATION_SERVICE = var.notification_service
      WEBHOOK_SECRET_NAME  = var.webhook_secret_name
      DYNAMODB_TABLE       = aws_dynamodb_table.pipeline_state.name
    }
  }
}

# Inscrição da função Lambda no tópico SNS
resource "aws_sns_topic_subscription" "lambda_subscription" {
  topic_arn = aws_sns_topic.pipeline_notifications.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.sns_to_teams_or_google_chat.arn
}

# Permissão para que o SNS invoque a função Lambda
resource "aws_lambda_permission" "sns_invoke" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sns_to_teams_or_google_chat.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.pipeline_notifications.arn
}

# Regras do CloudWatch para monitoramento de eventos do CodePipeline
resource "aws_cloudwatch_event_rule" "pipeline_state_change" {
  name        = "pipeline-state-change"
  description = "Monitora mudanças de estado no CodePipeline e encaminha para o tópico SNS."
  event_pattern = jsonencode({
    source: ["aws.codepipeline"],
    "detail-type": ["CodePipeline Pipeline Execution State Change"]
  })
}

resource "aws_cloudwatch_event_target" "state_change_to_sns" {
  rule      = aws_cloudwatch_event_rule.pipeline_state_change.name
  target_id = "stateChangeToSNS"
  arn       = aws_sns_topic.pipeline_notifications.arn
}

# Política do tópico SNS para permitir publicações de eventos do CloudWatch
resource "aws_sns_topic_policy" "sns_topic_policy" {
  arn    = aws_sns_topic.pipeline_notifications.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

# Documentação da política SNS
data "aws_iam_policy_document" "sns_topic_policy" {
  statement {
    actions   = ["SNS:Publish"]
    effect    = "Allow"
    resources = [aws_sns_topic.pipeline_notifications.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}
