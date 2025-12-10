import os
import json
import urllib.request
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def send_slack(webhook: str, text: str):
    """Send Slack message with error handling."""
    try:
        body = json.dumps({"text": text}).encode("utf-8")
        req = urllib.request.Request(
            webhook,
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        urllib.request.urlopen(req, timeout=5)
    except Exception as e:
        logger.error(f"Slack send failed: {e}")


def extract_canary_message(event: dict) -> str:
    """Extract SNS > Canary message safely."""
    try:
        sns = event["Records"][0]["Sns"]
        return sns.get("Message", "")
    except Exception as e:
        logger.warning(f"Unexpected SNS event format: {e}")
        return json.dumps(event, indent=2)


def format_slack_message(raw: str) -> str:
    """Readable Slack alert message."""
    return (
        ":rotating_light: *CANARY FAILURE DETECTED*\n"
        "> A CloudWatch Synthetics Canary has failed.\n\n"
        "*Details:*\n```json\n"
        f"{raw}\n```"
    )


def lambda_handler(event, context):
    logger.info("Event received for Canary failure alert")

    webhook = os.environ.get("SLACK_WEBHOOK_URL")

    if not webhook:
        logger.error("Missing SLACK_WEBHOOK_URL env variable")
        return {"status": "error", "reason": "missing webhook"}

    # Extract message from SNS
    raw = extract_canary_message(event)

    # Format message for Slack
    slack_msg = format_slack_message(raw)

    # Send
    send_slack(webhook, slack_msg)

    return {"status": "ok"}