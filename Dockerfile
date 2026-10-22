FROM python:3.12-slim-bookworm
WORKDIR /app

# залежності окремим шаром до коду: кеш не скидається при зміні коду
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

RUN useradd --system --uid 1001 appuser
USER appuser

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]