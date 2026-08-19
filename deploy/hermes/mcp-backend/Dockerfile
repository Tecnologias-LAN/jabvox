# Servidor MCP backend (FastMCP) con las MCPs por defecto por cuenta de Jabvox.
# Requiere Python 3.11+ (por eso va en contenedor; el host puede tener 3.9).
FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY server.py .

EXPOSE 9000
CMD ["python", "server.py"]
