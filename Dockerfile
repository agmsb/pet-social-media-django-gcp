FROM python:3.8-slim-buster

ENV APP_HOME /app
ENV PORT 8080
ENV PYTHONUNBUFFERED 1

WORKDIR $APP_HOME
COPY requirements.txt .

RUN pip install --upgrade pip -r requirements.txt

COPY . .
CMD PRODUCTION_MODE="production" python3 manage.py runserver 0.0.0.0:8080
