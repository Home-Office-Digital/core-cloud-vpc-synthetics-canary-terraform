import os
import json
import urllib.request
import urllib.error
import logging
import traceback
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)

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
            else:
                logger.info("Slack alert sent successfully")
    except urllib.error.HTTPError as e:
        logger.error(f"Slack HTTP error: {e.code} {e.reason}")
    except Exception:
        logger.error(traceback.format_exc())

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
def get_status_attributes(status_text: str):
    mapping = {
        "ALARM": (":rotating_light:", "CANARY FAILURE DETECTED"),
        "ERROR": (":rotating_light:", "CANARY FAILURE DETECTED"),
        "FAILED": (":rotating_light:", "CANARY FAILURE DETECTED"),
        "OK": (":large_green_circle:", "CANARY ISSUE RESOLVED"),
        "RESOLVED": (":large_green_circle:", "CANARY ISSUE RESOLVED"),
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

    webhook = os.environ.get("SLACK_WEBHOOK_URL")
    if not webhook:
        logger.error("SLACK_WEBHOOK_URL not set")
        return {"status": "error"}

    for record in event.get("Records", []):
        raw = extract_sns_message(record)
        ctx = parse_event_context(record)
        msg = format_slack_message(raw, ctx)
        send_slack(webhook, msg)

    return {"status": "ok"}