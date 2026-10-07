import json
import logging
import os
import uuid
from dotenv import load_dotenv
import boto3
from botocore.config import Config

from lambdas.common.db import get_connection
load_dotenv()
logger = logging.getLogger()
logger.setLevel(logging.INFO)

REGION = os.environ.get("AWS_REGION", "ap-south-1")
s3 = boto3.client(
    "s3",
    region_name=REGION,
    endpoint_url=f"https://s3.{REGION}.amazonaws.com",
    config=Config(signature_version="s3v4", s3={"addressing_style": "virtual"}),
)

BUCKET = os.environ.get("UPLOAD_BUCKET")
URL_EXPIRY_SECONDS = 300

ALLOWED_ORIGINS = os.environ.get("ALLOWED_ORIGIN", "*")
CONTENT_TYPE = "text/csv"

def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": ALLOWED_ORIGINS,
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
        },
        "body": json.dumps(body),
    }

def handler(event, context):
    conn = None
    try:
        batch_id = str(uuid.uuid4())
        key = f"uploads/{batch_id}.csv"
        conn = get_connection()

        with conn, conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO upload_batches (batch_id, s3_key, status) VALUES (%s, %s, 'uploaded')", (batch_id,key)
                )
        upload_url = s3.generate_presigned_url(
            "put_object",
            Params={"Bucket": BUCKET, "Key": key, "ContentType": CONTENT_TYPE},
            ExpiresIn=URL_EXPIRY_SECONDS,
        )

        logger.info("Created batch %s", batch_id)
        return _response(
            200,
            {
                "upload_url": upload_url,
                "batch_id": batch_id,
                "key": key,
                "content_type": CONTENT_TYPE,
                "expires_in": URL_EXPIRY_SECONDS,
            }
        )
    except Exception:
        logger.exception("Failed to create upload URL")
        return _response(500, {"error": "Could not create upload URL"})
    finally:
        if conn is not None:
            conn.close()
