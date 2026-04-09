# =============================================================================
# Stage 1 — builder
# Install dependencies into an isolated directory so we can copy only what
# the runtime image needs (no pip, no setuptools, no compiler toolchain).
# =============================================================================
FROM python:3.12-slim AS builder

WORKDIR /build

# Copy only the dependency manifest first — this layer is cached unless
# requirements.txt changes, so repeated builds are fast.
COPY requirements.txt .

RUN pip install --no-cache-dir --target=/build/packages -r requirements.txt


# =============================================================================
# Stage 2 — runtime
# Start from the same slim base to keep the image small (~80 MB total).
# The builder stage is discarded; pip and its cache never appear in the
# final image.
# =============================================================================
FROM python:3.12-slim

WORKDIR /app

# ---------------------------------------------------------------------------
# Security: create a dedicated non-root system user.
# The container will run as "appuser"; PID 1 has no root privileges.
# ---------------------------------------------------------------------------
RUN addgroup --system appgroup \
 && adduser  --system --ingroup appgroup --no-create-home appuser

# Copy installed packages from the builder stage
COPY --from=builder /build/packages /app/packages

# Copy application source
COPY main.py .

# Tell Python where to find the packages we copied
ENV PYTHONPATH=/app/packages \
    PYTHONUNBUFFERED=1

# Drop to non-root before the process starts
USER appuser

# Expose the port the app listens on (documentation only; mapping is done
# in docker run / ECS task definition)
EXPOSE 8080

# Use exec form so signals (SIGTERM from ECS drain) reach the Python process
# directly, enabling graceful shutdown.
CMD ["python", "-m", "uvicorn", "main:app", \
     "--host", "0.0.0.0", \
     "--port", "8080", \
     "--workers", "1"]
