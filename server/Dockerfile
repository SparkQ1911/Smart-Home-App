FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY smart_home_server.py mqtt_bridge.py ./

USER nobody
EXPOSE 8080

CMD ["python", "smart_home_server.py"]
