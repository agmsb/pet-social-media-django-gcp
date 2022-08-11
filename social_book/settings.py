# Copyright 2022 Google Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


"""
Django settings.

Generated by 'django-admin startproject' using Django 3.2.6.

For more information on this file, see
https://docs.djangoproject.com/en/3.2/topics/settings/

For the full list of settings and their values, see
https://docs.djangoproject.com/en/3.2/ref/settings/
"""

from pathlib import Path
import os
from django.core.management.utils import get_random_secret_key
from google.cloud import secretmanager
secret_client = secretmanager.SecretManagerServiceClient()

# Build paths inside the project like this: BASE_DIR / 'subdir'.
BASE_DIR = Path(__file__).resolve().parent.parent

# Quick-start development settings - unsuitable for production
# See https://docs.djangoproject.com/en/3.2/howto/deploymepnt/checklist/

# SECURITY WARNING: keep the secret key used in production secret!
SECRET_KEY = get_random_secret_key()
PROJECT_ID = os.environ.get('PROJECT_ID')
if not PROJECT_ID: 
    print("PROJECT_ID not set. Please try again")

def get_secret(secret_name, project_id):
    name = f"projects/{project_id}/secrets/{secret_name}/versions/latest"
    response = secret_client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")

# SECURITY WARNING: don't run with debug turned on in production!
DEBUG = True # TODO: Change this to False in production
PORT = 8080
LOCAL_HOST_1 = '127.0.0.1'
LOCAL_HOST_2 = '0.0.0.0'

WEBISTE_URL_US_CENTRAL1 = 'https://petsocialmedia-356303--us-central1-j2ys2raxoq-uc.a.run.app' # TODO: change to your website url in us-central1
WEBISTE_URL_US_WEST1 = 'https://petsocialmedia-356303--us-west1-j2ys2raxoq-uw.a.run.app' # TODO: change to your website url in us-west1
WEBISTE_URL_US_EAST1 = 'https://petsocialmedia-356303--us-east1-j2ys2raxoq-ue.a.run.app' # TODO: change to your website url in us-east1
WEBSITE_GLOBAL_HOST = '34.117.109.248' # TODO: change to your website global host (eg, 123.456.789.123)

LOCAL_WEBSITE_URL = 'https://{LOCAL_HOST_2}:{PORT}/'

WEBISTE_HOST_US_CENTRAL1 = WEBISTE_URL_US_CENTRAL1.replace("https://", "") 
WEBISTE_HOST_US_WEST1 = WEBISTE_URL_US_WEST1.replace("https://", "")
WEBISTE_HOST_US_EAST1 = WEBISTE_URL_US_EAST1.replace("https://", "")

CSRF_TRUSTED_ORIGINS = [
    WEBISTE_URL_US_CENTRAL1,
    WEBISTE_URL_US_WEST1, 
    WEBISTE_URL_US_EAST1,
    LOCAL_WEBSITE_URL,
]

ALLOWED_HOSTS = [
    LOCAL_HOST_1,
    LOCAL_HOST_2,
    WEBISTE_HOST_US_CENTRAL1, 
    WEBISTE_HOST_US_EAST1, 
    WEBISTE_HOST_US_WEST1,
    WEBSITE_GLOBAL_HOST,
    'localhost'
]

# Application definition

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'core'
]

MIDDLEWARE = [
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'social_book.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [os.path.join(BASE_DIR, 'templates')],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'social_book.wsgi.application'

# Database
# https://docs.djangoproject.com/en/3.2/ref/settings/#databases

DATABASE_NAME = get_secret("DATABASE_NAME", PROJECT_ID) 
DATABASE_USER = get_secret("DATABASE_USER", PROJECT_ID) 
DATABASE_PASSWORD = get_secret("DATABASE_PASSWORD", PROJECT_ID)
DATABASE_HOST_PROD = get_secret("DATABASE_HOST_PROD", PROJECT_ID) 
DATABASE_PORT_PROD = get_secret("DATABASE_PORT_PROD", PROJECT_ID) 
DATABASE_HOST_LOCAL = '0.0.0.0' 
DATABASE_PORT_LOCAL = '8002'

if os.environ.get("PRODUCTION_MODE") == "production":
    DATABASES = {
        # Production
        'default': {
            'ENGINE': 'django.db.backends.mysql',
            'NAME': DATABASE_NAME,
            'USER': DATABASE_USER,
            'PASSWORD': DATABASE_PASSWORD,
            'HOST': DATABASE_HOST_PROD,
            'PORT': DATABASE_PORT_PROD,
        }
    }
elif os.environ.get("PRODUCTION_MODE") == "local":
     DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.mysql',
            'NAME': DATABASE_NAME,
            'USER': DATABASE_USER,
            'PASSWORD': DATABASE_PASSWORD,
            'HOST': DATABASE_HOST_LOCAL,
            'PORT': DATABASE_PORT_LOCAL,
        }
    }

else: 
     DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.sqlite3',
            'NAME': BASE_DIR / 'db.sqlite3',
        }
    }


# Password validation
# https://docs.djangoproject.com/en/3.2/ref/settings/#auth-password-validators

AUTH_PASSWORD_VALIDATORS = [
    {
        'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator',
    },
]


# Internationalization
# https://docs.djangoproject.com/en/3.2/topics/i18n/

LANGUAGE_CODE = 'en-us'

TIME_ZONE = 'UTC'

USE_I18N = True

USE_L10N = True

USE_TZ = True


# Static files (CSS, JavaScript, Images)
# https://docs.djangoproject.com/en/3.2/howto/static-files/

STATIC_URL = '/static/'
STATIC_ROOT = os.path.join(BASE_DIR, 'staticfiles')
STATICFILES_DIRS = (os.path.join(BASE_DIR, 'static'),)

# Default primary key field type
# https://docs.djangoproject.com/en/3.2/ref/settings/#default-auto-field

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

MEDIA_URL = '/media/'
MEDIA_ROOT = os.path.join(BASE_DIR, 'media')
