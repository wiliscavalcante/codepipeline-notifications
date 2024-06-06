from diagrams import Diagram, Cluster
from diagrams.aws.devtools import Codepipeline
from diagrams.aws.database import Dynamodb, DynamodbTable
from diagrams.aws.integration import SNS, SimpleNotificationServiceSnsTopic
from diagrams.aws.management import Cloudwatch
from diagrams.aws.security import IAM, IAMRole, IAMPermissions, SecretsManager
from diagrams.aws.compute import Lambda
from diagrams.aws.integration import Eventbridge
from diagrams.saas.chat import Teams
from diagrams.custom import Custom  # Usando Custom para representar o webhook

with Diagram("AWS Infrastructure with CodePipeline Events and Teams Notifications", show=True, direction="LR"):
    with Cluster("Database Services"):
        dynamo_service = Dynamodb("DynamoDB")
        dynamo_table = DynamodbTable("DynamoDBTable")
        dynamo_service >> dynamo_table

    with Cluster("Messaging"):
        sns_service = SNS("SNS Service")
        sns_topic = SimpleNotificationServiceSnsTopic("SNS Topic")
        sns_service >> sns_topic

    with Cluster("Compute"):
        lambda_function = Lambda("Lambda")

    with Cluster("Monitoring"):
        cloudwatch = Cloudwatch("CloudWatch")
        log_group = Custom("Log Group", "./aws_logs.png")
        cloudwatch >> log_group

    with Cluster("Event Orchestration"):
        event_bridge = Eventbridge("EventBridge")
        code_pipeline = Codepipeline("CodePipeline")
        code_pipeline >> event_bridge
        event_bridge >> sns_topic  

    with Cluster("Security"):
        iam_service = IAM("IAM Service")
        iam_role = IAMRole("Role")
        iam_policy = IAMPermissions("Policy")
        secrets_manager = SecretsManager("Secrets")
        
        iam_service >> iam_role
        iam_role >> iam_policy
        iam_policy >> [secrets_manager, dynamo_service, cloudwatch]

    lambda_function >> iam_role
    lambda_function >> cloudwatch  # A função Lambda grava logs no CloudWatch
    sns_topic >> lambda_function  # O tópico SNS aciona a função Lambda

    webhook = Custom("Webhook", "./webhook.png")  # Usando um ícone personalizado para Webhook
    teams_service = Teams("Microsoft Teams")
    lambda_function >> webhook >> teams_service  # Lambda envia notificações via Webhook para o Microsoft Teams

    lambda_function >> dynamo_table  # A função Lambda acessa a tabela DynamoDB
