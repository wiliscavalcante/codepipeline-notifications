import os
import json
import boto3
import requests
from datetime import datetime, timezone, timedelta

# Inicialização dos clientes AWS para DynamoDB e Secrets Manager
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])
secrets_manager = boto3.client('secretsmanager')

def get_webhook_url():
    """Obtém a URL do webhook a partir do AWS Secrets Manager, usando a variável de ambiente para o nome do segredo."""
    secret_name = os.getenv("WEBHOOK_SECRET_NAME")
    try:
        get_secret_value_response = secrets_manager.get_secret_value(SecretId=secret_name)
        secret = get_secret_value_response['SecretString']
        return json.loads(secret)['WEBHOOK_URL']
    except Exception as e:
        print(f"Erro ao recuperar o webhook URL: {e}")
        raise e

def send_notification(bot_message, webhook_url):
    """Envia uma notificação JSON para o webhook configurado via POST request."""
    headers = {'Content-Type': 'application/json'}
    response = requests.post(webhook_url, headers=headers, json=bot_message)
    if response.status_code not in [200, 204]:
        print(f"Erro ao enviar notificação: {response.text}")
    else:
        print("Notificação enviada com sucesso.")

def lambda_handler(event, context):
    """Função principal do Lambda para processar eventos do SNS e enviar notificações com informações relevantes."""
    region = boto3.session.Session().region_name  # Obtenção dinâmica da região
    webhook_url = get_webhook_url()
    aws_account_id = boto3.client('sts').get_caller_identity().get('Account')
    brazil_timezone = timezone(timedelta(hours=-3))  # Define o fuso horário de Brasília (UTC-3)

    for record in event['Records']:
        sns_message = json.loads(record['Sns']['Message'])
        detail = sns_message['detail']
        pipeline_name = detail['pipeline']
        state = detail['state']
        local_time = datetime.now(timezone.utc).astimezone(brazil_timezone)
        formatted_time = local_time.strftime('%d-%m-%Y %H:%M:%S')

        # Construção do URL do pipeline baseado na região dinâmica
        view_pipeline_url = f"https://console.aws.amazon.com/codesuite/codepipeline/pipelines/{pipeline_name}/view?region={region}"

        # Verifica o estado anterior do pipeline no DynamoDB
        response = table.get_item(Key={'pipelineName': pipeline_name})
        item = response.get('Item', {})
        last_state = item.get('state') if item else 'UNKNOWN'

        # Condicional para atualizar o DynamoDB e enviar notificações apenas em mudanças de estado significativas
        if state == "FAILED" or (state == "SUCCEEDED" and last_state == "FAILED"):
            print(f"Updating DynamoDB for pipeline {pipeline_name} to state {state}")
            table.put_item(Item={
                'pipelineName': pipeline_name,
                'state': state,
                'lastUpdateTime': formatted_time
            })

            emoji = "🚨" if state == "FAILED" else "✅"
            notification_type = "Falha" if state == "FAILED" else "Recuperação"
            card_title = f"{emoji} Notificação de {notification_type} do AWS CodePipeline"

            # Montagem da mensagem de notificação para Microsoft Teams
            bot_message = {
                "@type": "MessageCard",
                "@context": "http://schema.org/extensions",
                "summary": card_title,
                "themeColor": "FF0000" if state == "FAILED" else "00FF00",
                "title": card_title,
                "sections": [{
                    "activityTitle": f"Pipeline: {pipeline_name}",
                    "facts": [
                        {"name": "Status", "value": state},
                        {"name": "Executado em", "value": formatted_time},
                        {"name": "ID da Conta AWS", "value": aws_account_id},
                        {"name": "Região AWS", "value": region}
                    ]
                }],
                "potentialAction": [{
                    "@type": "OpenUri",
                    "name": "Visualizar Pipeline",
                    "targets": [{"os": "default", "uri": view_pipeline_url}]
                }]
            }

            send_notification(bot_message, webhook_url)
        else:
            print(f"No update to DynamoDB needed for pipeline {pipeline_name} with state {state}")

    return {
        'statusCode': 200,
        'body': json.dumps('Event processed successfully.')
    }
