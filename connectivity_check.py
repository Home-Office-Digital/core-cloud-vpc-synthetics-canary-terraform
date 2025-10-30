import os
import socket
import logging

def handler(event, context):
    logger = logging.getLogger()
    logger.setLevel(logging.INFO)

    ip_list = os.getenv("TARGET_IPS", "")
    allowed_ports = os.getenv("ALLOWED_PORTS", "")
    denied_ports = os.getenv("DENIED_PORTS", "")

    ips = [ip.strip() for ip in ip_list.split(",") if ip.strip()]
    allowed = [int(p.strip()) for p in allowed_ports.split(",") if p.strip().isdigit()]
    denied = [int(p.strip()) for p in denied_ports.split(",") if p.strip().isdigit()]

    def check_port(ip, port):
        try:
            with socket.create_connection((ip, port), timeout=3):
                return True
        except Exception:
            return False

    for ip in ips:
        logger.info(f"Scanning IP: {ip}")

        if allowed:
            for port in allowed:
                if check_port(ip, port):
                    logger.info(f"[✓] {ip}:{port} is reachable (allowed)")
                else:
                    logger.warning(f"[✗] {ip}:{port} is NOT reachable (allowed)")
        else:
            logger.info("No allowed ports specified. Skipping allowed port checks.")

        if denied:
            for port in denied:
                if check_port(ip, port):
                    logger.warning(f"[!] {ip}:{port} is reachable (denied)")
                else:
                    logger.info(f"[✓] {ip}:{port} is blocked (denied)")
        else:
            logger.info("No denied ports specified. Skipping denied port checks.")

    return {
        "statusCode": 200,
        "body": "Connectivity scan completed"
    }