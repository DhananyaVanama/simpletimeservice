import json
from fastapi import FastAPI, Request
from fastapi.responses import Response
from datetime import datetime, timezone

app = FastAPI(title="SimpleTimeService")

@app.get("/")
async def root(request: Request):
    forwarded_for = request.headers.get("x-forwarded-for")
    if forwarded_for:
        ip = forwarded_for.split(",")[0].strip()
    else:
        ip = request.client.host

    data = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f"),
        "ip": ip,
    }

    return Response(
        content=json.dumps(data, indent=2),
        media_type="application/json"
    )
