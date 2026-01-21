FROM google/cloud-sdk:slim

# Simple demo preprocessing script
RUN apt-get update && apt-get install -y python3 && rm -rf /var/lib/apt/lists/*

COPY process.py /app/process.py
WORKDIR /app

ENTRYPOINT ["python3", "/app/process.py"]
