"""
SimpleTimeService
-----------------
Returns a JSON response with the current UTC timestamp and the visitor's IP address.

Endpoints:
  GET /        → {"timestamp": "...", "ip": "..."}
  GET /health  → {"status": "ok"}  (used by ALB health checks)
"""

from fastapi import FastAPI, Request
from datetime import datetime, timezone

app = FastAPI(title="SimpleTimeService")


@app.get("/")
async def root(request: Request) -> dict:
    """
    Return current UTC timestamp and the caller's IP address.
    When deployed behind an ALB, the real client IP is in the
    X-Forwarded-For header; we take the first (leftmost) entry.
    """
    forwarded_for = request.headers.get("x-forwarded-for")
    if forwarded_for:
        # X-Forwarded-For can be a comma-separated list; take the first
        ip = forwarded_for.split(",")[0].strip()
    else:
        ip = request.client.host

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "ip": ip,
    }


@app.get("/health")
async def health() -> dict:
    """
    Lightweight health-check endpoint used by the ALB target group.
    Returns HTTP 200 as long as the process is alive.
    """
    return {"status": "ok"}
