FROM python:3.8-slim-buster

ENV APP_HOME /app
ENV PORT 8080
ENV PYTHONUNBUFFERED 1
ENV GOOGLE_APPLICATION_CREDENTIALS=core/config/credential.json

WORKDIR $APP_HOME
COPY requirements.txt .

RUN pip install --upgrade pip -r requirements.txt
RUN export GOOGLE_APPLICATION_CREDENTIALS="core/config/credential.json"

COPY . .
CMD PRODUCTION_MODE="production" python3 manage.py runserver 0.0.0.0:8080
