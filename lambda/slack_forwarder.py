import os
import json
import boto3
import urllib.request

def get_webhook(secret_arn):
    sm = boto3.client("secretsmanager")
    resp = sm.get_secret_value(SecretId=secret_arn)
    if "SecretString" in resp:
        try:
            data = json.loads(resp["SecretString"])
            return data.get("webhook", resp["SecretString"])
        except:
            return resp["SecretString"]
    return None

def send_slack(webhook, text):
    body = json.dumps({"text": text}).encode("utf-8")
    req = urllib.request.Request(
        webhook,
        data=body,
        headers={"Content-Type": "application/json"}
    )
    urllib.request.urlopen(req)

def lambda_handler(event, context):
    secret_arn = os.environ.get("SLACK_SECRET_ARN")
    webhook = get_webhook(secret_arn) if secret_arn else os.environ.get("SLACK_WEBHOOK_URL")

    sns = event["Records"][0]["Sns"]
    message = sns["Message"]

    text = f":rotating_light: *CANARY FAILED*\n```\n{message}\n```"
    send_slack(webhook, text)

    return {"status": "ok"}