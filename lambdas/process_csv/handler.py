import codecs
import csv
import json
import logging
import os
import re
import urllib.request
import uuid
from urllib.parse import unquote_plus

import boto3
from psycopg2.extras import execute_values
from urllib3.util import url

from lambdas.common.db import get_connection

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")

CHUNK_SIZE = 1000
REQUIRED_COLUMNS = {"user_id", "email","name", "monthly_income", "credit_score", "employment_status", "age"}
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
N8N_WEBHOOK_URL = os.environ.get("N8N_WEBHOOK_URL")

def validate_row(row):
    """Return (clean_tuple, None) if valid, or (None, reason) if not."""
    try:
        user_id = (row.get("user_id") or "").strip()
        email = (row.get("email") or "").strip().lower()
        name = (row.get("name") or "").strip().lower()
        employment = (row.get("employment_status") or "").strip().lower()
        income = float(row["monthly_income"])
        score = int(float(row["credit_score"]))
        age = int(float(row["age"]))
    except (ValueError, TypeError, KeyError):
        return None, "bad or missing number"

    if not user_id:
        return None, "missing user_id"
    if not EMAIL_RE.match(email):
        return None, "invalid email"
    if not name:
        return None, "missing name"
    if not employment:
        return None, "missing employment_status"
    if income < 0:
        return None, "negative income"
    if not 300 <= score <= 900:
        return None, "credit_score out of range"
    if not 18 <= age <= 100:
        return None, "age out of range"

    return (user_id, email, name, income, score, employment, age), None


def claim_batch(conn, batch_id):
    with conn, conn.cursor() as cur:
        cur.execute(
            """UPDATE upload_batches
               SET status = 'processing', updated_at = now()
               WHERE batch_id = %s AND status = 'uploaded'
            """,
            (batch_id,),
        )
        return cur.rowcount == 1

def finish_batch(conn, batch_id, status, total, valid, invalid, error=None):
    with conn, conn.cursor() as cur:
        cur.execute(
            """UPDATE upload_batches
               SET status = %s, total_rows = %s, inserted_rows = %s, skipped_rows = %s, error_message = %s, updated_at = now()
               WHERE batch_id = %s
            """,
            (status, total, valid, invalid, error, batch_id)
        )

def insert_chunk(conn, rows, batch_id):
    unique = ({r[0]: r for r in rows})
    values = [r + (batch_id,) for r in unique.values()]
    with conn, conn.cursor() as cur:
        execute_values(
            cur,
            """INSERT INTO users
               (user_id, email, name, monthly_income, credit_score, employment_status, age, batch_id)
               VALUES %s
               ON CONFLICT (user_id) DO UPDATE SET
                 email = EXCLUDED.email,
                 name = EXCLUDED.name,
                 monthly_income = EXCLUDED.monthly_income,
                 credit_score = EXCLUDED.credit_score,
                 employment_status = EXCLUDED.employment_status,
                 age = EXCLUDED.age,
                 batch_id = EXCLUDED.batch_id
            """,
            values
        )

def trigger_n8n(batch_id, valid_rows):
    if not N8N_WEBHOOK_URL:
        logger.warning("N8N_WEBHOOK_URL not set, skipping webhook")
        return
    payload = json.dumps({"batch_id": batch_id, "valid_rows": valid_rows}).encode()
    req = urllib.request.Request(
        N8N_WEBHOOK_URL, data=payload, headers={"Content-Type": "application/json"}, method="POST"
    )

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            logger.info("n8n responded %s", resp.status)
            return
    except Exception as e:
        logger.info("n8n webhook failed: %s", e)
        return f"webhook failed: {e}"


def process_object(bucket, key):
    batch_id = os.path.splitext(os.path.basename(key))[0]
    try:
        uuid.UUID(batch_id)
    except ValueError:
        logger.warning("Ignoring object with non-batch key: %s", key)
        return

    conn = get_connection()
    total = valid = invalid = 0
    error_samples = []

    try:
        if not claim_batch(conn, batch_id):
            logger.info("Batch %s already claimed, skipping", batch_id)
            return

        body = s3.get_object(Bucket=bucket, Key=key)["Body"]
        reader = csv.DictReader(codecs.getreader("utf-8-sig")(body))

        header = {h.strip().lower() for h in (reader.fieldnames or [])}
        missing = REQUIRED_COLUMNS - header
        if missing:
            raise ValueError(f"CSV missing columns: {sorted(missing)}")
        reader.fieldnames = [h.strip().lower() for h in reader.fieldnames]

        chunk = []
        for row in reader:
            total += 1
            clean, reason = validate_row(row)
            if clean is None:
                invalid += 1
                if len(error_samples) < 5:
                    error_samples.append(f"row {total + 1}: {reason}")
                continue
            chunk.append(clean)
            valid += 1
            if len(chunk) >= CHUNK_SIZE:
                insert_chunk(conn, chunk, batch_id)
                chunk = []
        if chunk:
            insert_chunk(conn, chunk, batch_id)

        note = "; ".join(error_samples) or None
        finish_batch(conn, batch_id, "done", total, valid, invalid, note)
        logger.info("Batch %s done: %d valid, %d invalid", batch_id, valid, invalid)

        if valid > 0:
            webhook_error = trigger_n8n(batch_id, valid)
            if webhook_error:
                finish_batch(conn, batch_id, "done", total, valid, invalid, f"{note + ";" if note else ''}{webhook_error}")
    except Exception as exc:
            logger.exception("Batch %s failed", batch_id)
            conn.rollback()
            finish_batch(conn, batch_id, "failed", total, valid, invalid, str(exc)[:500])
            raise
    finally:
            conn.close()

def handler(event, context):
    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = unquote_plus(record["s3"]["object"]["key"])
        process_object(bucket, key)
    return {"status": "ok"}
