import pymysql
import os
from dotenv import load_dotenv

pymysql.version_info = (1, 4, 2, "final", 0)
pymysql.install_as_MySQLdb()

# Load environment variables from .env file
load_dotenv()
GOOGLE_APPLICATION_CREDENTIALS = 'core/config/credential.json' # change to your path to credentials json
