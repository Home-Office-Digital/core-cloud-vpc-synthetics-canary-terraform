import os
import json
import urllib.request
import urllib.error
import logging
import traceback
import boto3
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def _resolve_webhook_url() -> str | None:
    webhook = os.environ.get("SLACK_WEBHOOK_URL")
    if webhook:
        return webhook

    secret_arn = os.environ.get("SLACK_SECRET_ARN")
    if not secret_arn:
        return None

    try:
        sm = boto3.client("secretsmanager")
        resp = sm.get_secret_value(SecretId=secret_arn)
        secret_str = resp.get("SecretString")
        if not secret_str:
            logger.error("SecretString is empty for SLACK_SECRET_ARN")
            return None

        # Support either a raw webhook string or a JSON object containing it.
        if secret_str.startswith("https://"):
            return secret_str

        parsed = json.loads(secret_str)
        return parsed.get("SLACK_WEBHOOK_URL") or parsed.get("webhook_url")
    except Exception:
        logger.error("Failed to resolve Slack webhook from Secrets Manager")
        logger.error(traceback.format_exc())
        return None

# Slack sender
def send_slack(webhook: str, payload: dict):
    try:
        body = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            webhook,
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            status = resp.getcode()
            resp.read()
            if status < 200 or status >= 300:
                logger.error(f"Slack returned non-2xx: {status}")
                return False
            else:
                logger.info("Slack alert sent successfully")
                return True
    except urllib.error.HTTPError as e:
        response_body = e.read().decode("utf-8", errors="ignore")
        logger.error(f"Slack HTTP error: {e.code} {e.reason}; body={response_body}")
        return False
    except Exception:
        logger.error(traceback.format_exc())
        return False

# SNS helpers
def extract_sns_message(record: dict) -> str:
    return record.get("Sns", {}).get("Message", "")

def parse_event_context(record: dict) -> dict:
    context = {
        "region": None,
        "account": None,
        "alarmName": None,
        "stateValue": None,
        "stateReason": None,
        "canaryName": None,
        "eventTime": None,
    }

    sns = record.get("Sns", {})
    context["account"] = sns.get("TopicArn", "").split(":")[4] if "TopicArn" in sns else None

    raw_message = sns.get("Message")
    if not raw_message:
        return context

    try:
        parsed = json.loads(raw_message)

        context["alarmName"] = parsed.get("AlarmName")
        context["stateValue"] = parsed.get("NewStateValue")
        context["stateReason"] = parsed.get("NewStateReason")
        context["eventTime"] = parsed.get("StateChangeTime")
        context["region"] = parsed.get("Region")

        trigger = parsed.get("Trigger", {})
        for dim in trigger.get("Dimensions", []):
            if dim.get("name") == "CanaryName":
                context["canaryName"] = dim.get("value")
                break

    except Exception:
        logger.debug("Failed to parse CloudWatch alarm JSON")

    if not context["region"]:
        context["region"] = os.environ.get("AWS_REGION")

    return context

# Formatting helpers
ALERT_EMOJI = ":rotating_light:"
SUCCESS_EMOJI = ":large_green_circle:"

CANARY_FAILURE_MSG = "CANARY FAILURE DETECTED"
CANARY_RESOLVED_MSG = "CANARY ISSUE RESOLVED"


def get_status_attributes(status_text: str):
    mapping = {
        "ALARM": (ALERT_EMOJI, CANARY_FAILURE_MSG),
        "ERROR": (ALERT_EMOJI, CANARY_FAILURE_MSG),
        "FAILED": (ALERT_EMOJI, CANARY_FAILURE_MSG),
        "OK": (SUCCESS_EMOJI, CANARY_RESOLVED_MSG),
        "RESOLVED": (SUCCESS_EMOJI, CANARY_RESOLVED_MSG),
    }
    return mapping.get(status_text.upper(), (":warning:", "CANARY ALERT"))

def _fmt_ts(iso_ts: str):
    if not iso_ts:
        return "unknown"
    try:
        iso_ts = iso_ts.replace("+0000", "+00:00")
        dt = datetime.fromisoformat(iso_ts)
        return dt.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    except Exception:
        return iso_ts

# Slack message builder (CLEAN)
def format_slack_message(raw: str, ctx: dict) -> dict:
    status = (ctx.get("stateValue") or "ALARM").upper()
    alarm = ctx.get("alarmName") or "Unknown Alarm"
    region = ctx.get("region") or "unknown"
    account = ctx.get("account") or "unknown"
    canary = ctx.get("canaryName") or "unknown"
    reason = ctx.get("stateReason") or "No reason provided"
    time = _fmt_ts(ctx.get("eventTime"))

    emoji, header = get_status_attributes(status)

    blocks = [
        {
            "type": "header",
            "text": {
                "type": "plain_text",
                "text": f"{emoji} {header}",
                "emoji": True
            },
        },
        {"type": "divider"},
        {
            "type": "section",
            "fields": [
                {"type": "mrkdwn", "text": f"*Status:*\n`{status}`"},
                {"type": "mrkdwn", "text": f"*Canary:*\n`{canary}`"},
                {"type": "mrkdwn", "text": f"*Alarm:*\n`{alarm}`"},
                {"type": "mrkdwn", "text": f"*Region:*\n`{region}`"},
                {"type": "mrkdwn", "text": f"*Account:*\n`{account}`"},
                {"type": "mrkdwn", "text": f"*Time:*\n`{time}`"},
            ],
        },
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*Reason:*\n```{reason}```"
            },
        },
    ]

    return {
        "text": "CloudWatch Canary Alert",
        "blocks": blocks,
    }

# Lambda entrypoint
def lambda_handler(event, context):
    logger.info("Received CloudWatch Canary alarm event")

    webhook = _resolve_webhook_url()
    if not webhook:
        logger.error("No Slack webhook configured. Set SLACK_WEBHOOK_URL or SLACK_SECRET_ARN.")
        raise RuntimeError("No Slack webhook configured")

    failed = 0
    for record in event.get("Records", []):
        raw = extract_sns_message(record)
        ctx = parse_event_context(record)
        msg = format_slack_message(raw, ctx)
        ok = send_slack(webhook, msg)
        if not ok:
            failed += 1

    if failed > 0:
        raise RuntimeError(f"Failed to deliver {failed} Slack message(s)")

    return {"status": "ok"}