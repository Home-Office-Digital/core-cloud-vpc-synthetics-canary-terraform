import os
import json
import urllib.request
import urllib.error
import urllib.parse
import logging
import traceback
import boto3
from botocore.config import Config
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)

AWS_CLIENT_CONFIG = Config(connect_timeout=5, read_timeout=10)
SECRETSMANAGER_CLIENT = boto3.client("secretsmanager", config=AWS_CLIENT_CONFIG)


def _resolve_webhook_url() -> str | None:
    webhook = (os.environ.get("SLACK_WEBHOOK_URL") or "").strip()
    if webhook:
        parsed = urllib.parse.urlparse(webhook)
        if parsed.scheme == "https" and parsed.netloc:
            logger.info("Using Slack webhook from SLACK_WEBHOOK_URL")
            return webhook
        logger.error("SLACK_WEBHOOK_URL is set but not a valid https URL")
        return None

    secret_arn = os.environ.get("SLACK_SECRET_ARN")
    if not secret_arn:
        logger.error("Neither SLACK_WEBHOOK_URL nor SLACK_SECRET_ARN is set")
        return None

    try:
        logger.info("Resolving Slack webhook from Secrets Manager")
        resp = SECRETSMANAGER_CLIENT.get_secret_value(SecretId=secret_arn)
        secret_str = resp.get("SecretString")
        if not secret_str:
            logger.error("SecretString is empty for SLACK_SECRET_ARN")
            return None

        secret_str = secret_str.strip()
        if secret_str.startswith("https://"):
            logger.info("Using raw webhook URL from Secrets Manager secret")
            return secret_str

        parsed = json.loads(secret_str)
        webhook = parsed.get("SLACK_WEBHOOK_URL") or parsed.get("webhook_url")
        if webhook:
            logger.info("Using webhook URL from JSON secret")
        else:
            logger.error("Secret JSON did not contain SLACK_WEBHOOK_URL or webhook_url")
        return webhook
    except Exception:
        logger.error("Failed to resolve Slack webhook from Secrets Manager")
        logger.error(traceback.format_exc())
        return None


def send_slack(webhook: str, payload: dict):
    try:
        logger.info("Sending Slack message")
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
            logger.info("Slack alert sent successfully")
            return True
    except urllib.error.HTTPError as e:
        response_body = e.read().decode("utf-8", errors="ignore")
        logger.error(f"Slack HTTP error: {e.code} {e.reason}; body={response_body}")
        return False
    except Exception:
        logger.error("Unexpected error sending Slack message")
        logger.error(traceback.format_exc())
        return False


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
        logger.warning("SNS record did not contain Message")
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
        logger.warning("Failed to parse CloudWatch alarm JSON from SNS message")
        logger.warning(traceback.format_exc())

    if not context["region"]:
        context["region"] = os.environ.get("AWS_REGION")

    return context


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


def format_slack_message(ctx: dict) -> dict:
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


def lambda_handler(event, context):
    logger.info("Received CloudWatch Canary alarm event")
    logger.info(f"Top-level event keys: {list(event.keys()) if isinstance(event, dict) else str(type(event))}")
    logger.info(f"Event payload: {json.dumps(event)}")

    webhook = _resolve_webhook_url()
    if not webhook:
        logger.error("No Slack webhook configured. Set SLACK_WEBHOOK_URL or SLACK_SECRET_ARN.")
        raise RuntimeError("No Slack webhook configured")

    records = event.get("Records", [])
    logger.info(f"Record count: {len(records)}")

    if not records:
        logger.warning("No SNS records found in event payload")
        return {"status": "no_records"}

    failed = 0
    for i, record in enumerate(records, start=1):
        logger.info(f"Processing record {i}")
        logger.info(f"Record payload: {json.dumps(record)}")

        ctx = parse_event_context(record)
        logger.info(f"Parsed context: {json.dumps(ctx)}")

        msg = format_slack_message(ctx)
        ok = send_slack(webhook, msg)
        if not ok:
            failed += 1

    if failed > 0:
        raise RuntimeError(f"Failed to deliver {failed} Slack message(s)")

    return {"status": "ok"}