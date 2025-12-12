
import os
import json
import re
import urllib.request
import urllib.error
import logging
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)

MAX_RAW_LENGTH = 4000  # Slack block safe character limit

# Slack sender

def send_slack(webhook: str, payload: dict):
    """Send Slack message with support for block payloads."""
    try:
        body = json.dumps(payload).encode("utf-8")
        logger.debug(f"Sending Slack payload: {json.dumps(payload, indent=2)}")

        req = urllib.request.Request(
            webhook,
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            status = resp.getcode()
            data = resp.read().decode("utf-8") if resp.readable() else ""
            if status < 200 or status >= 300:
                logger.error(f"Slack returned non-2xx: {status} body={data}")
            else:
                logger.info(f"Slack sent successfully: {status}")
    except urllib.error.HTTPError as e:
        logger.error(f"Slack HTTP error: {e.code} {e.reason}")
    except Exception as e:
        logger.error(f"Slack send failed: {e}")

# Event helpers

def parse_event_context(record: dict) -> dict:
    """
    Attempt to derive useful context (region, account) from SNS, and structured fields if EventBridge pushed JSON.
    Returns a dict with possible keys: region, account, alarmName, stateValue, stateReason, canaryName, eventTime.
    """
    context = {
        "region": None,
        "account": None,
        "alarmName": None,
        "stateValue": None,
        "stateReason": None,
        "canaryName": None,
        "eventTime": None,
    }

    # SNS envelope hints
    sns = record.get("Sns", {})
    context["eventTime"] = sns.get("Timestamp")
    context["account"] = sns.get("TopicArn", "").split(":")[4] if "TopicArn" in sns else None

    # If SNS Message is JSON (EventBridge CloudWatch Alarm), parse it
    raw_message = sns.get("Message")
    if raw_message:
        try:
            parsed = json.loads(raw_message)
            # EventBridge alarm format
            if isinstance(parsed, dict) and parsed.get("detail-type") == "CloudWatch Alarm State Change":
                context["region"] = parsed.get("region")
                context["account"] = parsed.get("account", context["account"])
                detail = parsed.get("detail", {})
                context["alarmName"] = detail.get("alarmName")
                state = detail.get("state", {})
                context["stateValue"] = state.get("value")
                context["stateReason"] = state.get("reason")

                # Attempt canary name from metric dimensions
                try:
                    metrics = detail.get("configuration", {}).get("metrics", [])
                    for mdq in metrics:
                        dims = mdq.get("metricStat", {}).get("metric", {}).get("dimensions", [])
                        for dim in dims:
                            if dim.get("name") == "CanaryName":
                                context["canaryName"] = dim.get("value")
                                break
                except Exception:
                    pass

                # EventBridge "time"
                context["eventTime"] = parsed.get("time", context["eventTime"])

            # If it's a CloudWatch notification JSON (rare), we can parse known fields as needed
        } except Exception:
            # Not JSON, continue with regex parsing below
            pass

    # Fallback region from Lambda env when EventBridge didn't provide region
    if not context["region"]:
        context["region"] = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION")

    return context

# Slack formatting

def get_status_attributes(status_text: str):
    """Return emoji and header based on status."""
    mapping = {
        "FAILED": (":rotating_light:", "CANARY FAILURE DETECTED"),
        "ERROR": (":rotating_light:", "CANARY FAILURE DETECTED"),
        "ALARM": (":rotating_light:", "CANARY FAILURE DETECTED"),
        "RESOLVED": (":large_green_circle:", "CANARY ISSUE RESOLVED"),
        "OK": (":large_green_circle:", "CANARY ISSUE RESOLVED"),
    }
    return mapping.get(status_text.upper(), (":warning:", "CANARY ALERT"))

def _fmt_ts(iso_ts: str):
    """Format ISO timestamp to readable UTC, or return as-is if unknown."""
    if not iso_ts:
        return "unknown"
    try:
        dt = datetime.fromisoformat(iso_ts.replace("Z", "+00:00"))
        return dt.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    except Exception:
        return iso_ts

def extract_from_raw_text(raw: str) -> dict:
    """
    Parse typical CloudWatch alarm email/SNS text body for fields:
    Status, Problem Title, Region, Alarm Name, Link.
    Also try to find CanaryName.
    """
    find = lambda pat: (re.search(pat, raw) or re.search(pat.replace(":", " :"), raw))
    get = lambda pat: (find(pat).group(1).strip() if find(pat) else None)

    status_text = (get(r"Status:\s*(.*)") or "FAILED").upper()
    title_text  = get(r"Problem Title:\s*(.*)") or get(r"Alarm Name:\s*(.*)") or "CloudWatch Canary Failure"
   
    region_text = get(r"Region:\s*(.*)")
    alarm_name  = get(r"Alarm Name:\s*(.*)") or title_text
    more_link   = get(r"For more information see:\s*(.*)") or get(r"View in Console:\s*(.*)")

    # Guess canary name from explicit label or from ARN in text
    canary_name = get(r"CanaryName:\s*(.*)")
    if not canary_name:
        m_arn = re.search(r"arn:aws:synthetics:[\w-]+:\d{12}:canary/([\w\.\-_/]+)", raw)
        if m_arn:
            canary_name = m_arn.group(1)

    return {
        "status_text": status_text,
        "title_text": title_text,
        "region_text": region_text,
        "alarm_name": alarm_name,
        "more_link": more_link,
        "canary_name": canary_name,
    }

def build_console_links(region: str, canary_name: str, alarm_name: str) -> dict:
    """Build AWS Console deep links."""
    if not region:
        return {"canary_link": None, "alarm_link": None}
    canary_link = (
        f"https://{region}.console.aws.amazon.com/cloudwatch/home"
        f"?region={region}#synthetics:canaryDetail/{canary_name or ''}"
    )
    alarm_link = (
        f"https://{region}.console.aws.amazon.com/cloudwatch/home"
        f"?region={region}#alarmsV2:alarm/{alarm_name or ''}"
    )
    return {"canary_link": canary_link, "alarm_link": alarm_link}

def format_slack_message(raw: str, ctx: dict) -> dict:
    """Format Canary alert into Slack Block Kit payload."""
    parsed = extract_from_raw_text(raw)

    # Prefer structured values from ctx if present, fallback to parsed text
    status_text = (ctx.get("stateValue") or parsed["status_text"]).upper()
    alarm_name  = ctx.get("alarmName") or parsed["alarm_name"]
    region      = ctx.get("region") or parsed["region_text"] or "unknown"
    account     = ctx.get("account") or "unknown"
    canary_name = ctx.get("canaryName") or parsed["canary_name"] or "unknown"
    reason      = ctx.get("stateReason") or parsed["title_text"]
    event_time  = _fmt_ts(ctx.get("eventTime"))
    links       = build_console_links(region, canary_name, alarm_name)

    emoji, header = get_status_attributes(status_text)

    # Truncate raw JSON if too long
    raw_display = raw if len(raw) <= MAX_RAW_LENGTH else raw[:MAX_RAW_LENGTH] + "\n...truncated..."

    blocks = [
        {"type": "header", "text": {"type": "plain_text", "text": f"{emoji} {header}", "emoji": True}},
        {"type": "divider"},
        {
            "type": "section",
            "fields": [
                {"type": "mrkdwn", "text": f"*Status:*\n`{status_text}`"},
                {"type": "mrkdwn", "text": f"*Canary:*\n`{canary_name}`"},
                {"type": "mrkdwn", "text": f"*Alarm:*\n`{alarm_name}`"},
                {"type": "mrkdwn", "text": f"*Region:*\n`{region}`"},
                {"type": "mrkdwn", "text": f"*Account:*\n`{account}`"},
                {"type": "mrkdwn", "text": f"*Time:*\n`{event_time}`"},
            ],
        },
        {
            "type": "section",
            "text": {"type": "mrkdwn", "text": f"*Reason:*\n```{reason}```"}
        },
    ]

    # Add quick-action buttons when we have links
    action_elements = []
    if links.get("canary_link"):
        action_elements.append({
            "type": "button", "style": "primary",
            "text": {"type": "plain_text", "text": "View Canary"},
            "url": links["canary_link"]
        })
    if links.get("alarm_link"):
        action_elements.append({
            "type": "button",
            "text": {"type": "plain_text", "text": "View Alarm"},
            "url": links["alarm_link"]
        })
    if action_elements:
        blocks.append({"type": "actions", "elements": action_elements})

    # Optional: add any "More Info" link found in raw text
    if parsed.get("more_link"):
        blocks.append({"type": "section", "text": {"type": "mrkdwn", "text": f"*More Info:* <{parsed['more_link']}>"}})

    # Raw event for debugging
    blocks.extend([
        {"type": "divider"},
        {"type": "section", "text": {"type": "mrkdwn", "text": f"*Raw Event:*\n```json\n{raw_display}\n```"}}
    ])

    return {"text": "CloudWatch Canary Alert", "blocks": blocks}

# Lambda entrypoint

def lambda_handler(event, context):
    logger.info("Event received for Canary failure alert")

    webhook = os.environ.get("SLACK_WEBHOOK_URL")
    if not webhook:
        logger.error("Missing SLACK_WEBHOOK_URL env variable")
        return {"status": "error", "reason": "missing webhook"}

    records = event.get("Records", [])
    if not records:
        logger.warning("No SNS records found in event")
        return {"status": "error", "reason": "no SNS records"}

    for record in records:
        raw = extract_sns_message(record)
        ctx = parse_event_context(record)
        slack_msg = format_slack_message(raw, ctx)
        send_slack(webhook, slack_msg)

    return {"status": "ok"}
