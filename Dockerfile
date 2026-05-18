FROM python:3.12-slim

WORKDIR /app

# Install deps first (layer cache)
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy app source and migrations
COPY backend/ .

# Copy static web pages (landing page, menu, assets)
COPY web/public/ /app/static/

# Railway injects PORT; default to 8000 for local Docker runs
ENV PORT=8000

# WEB_CONCURRENCY: Railway sets this automatically based on plan CPU;
# default 2 for smaller plans.
CMD uvicorn app.main:app --host 0.0.0.0 --port ${PORT} --workers ${WEB_CONCURRENCY:-2} --loop uvloop
