import os
import psycopg2
from dotenv import load_dotenv

load_dotenv()
def get_connection():
    """Open a new Postgres connection from environment variables.

    connect_timeout is short on purpose: if the network or security group is misconfigured, we fail in 5 seconds with a clear error instead of hanging until the lambda times out.
    """
    return psycopg2.connect(
        host=os.environ["DB_HOST"],
        port=os.environ.get("DB_PORT", "5432"),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        connect_timeout=5,
        )
