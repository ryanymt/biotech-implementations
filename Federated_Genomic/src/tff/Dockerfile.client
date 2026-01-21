FROM python:3.10-slim
WORKDIR /app
RUN pip install --no-cache-dir google-cloud-pubsub google-cloud-bigquery
COPY client.py .
ENTRYPOINT ["python3", "client.py"]
