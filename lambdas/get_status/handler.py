import json
import logging
import os
import uuid
from dotenv import load_dotenv

from lambdas.common.db import get_connection

load_dotenv()
logger = logging.getLogger()
logger.setLevel(logging.INFO)

ALLOWED_ORIGINS = os.environ.get("ALLOWED_ORIGIN", "*")


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
        params = (event or {}).get("pathParameters") or {}
        batch_id = params.get("batch_id") or ""
        try:
            uuid.UUID(batch_id)
        except ValueError:
            return _response(400, {"error": "Invalid batch_id"})

        conn = get_connection()
        with conn, conn.cursor() as cur:
            cur.execute(
                """SELECT status, total_rows, inserted_rows, skipped_rows,
                          error_message, updated_at
                   FROM upload_batches WHERE batch_id = %s""",
                (batch_id,),
            )
            row = cur.fetchone()

        if row is None:
            return _response(404, {"error": "Batch not found"})

        status, total, inserted, skipped, error, updated = row
        return _response(
            200,
            {
                "batch_id": batch_id,
                "status": status,
                "total_rows": total,
                "inserted_rows": inserted,
                "skipped_rows": skipped,
                "error_message": error,
                "updated_at": updated.isoformat() if updated else None,
            },
        )
    except Exception:
        logger.exception("Failed to fetch batch status")
        return _response(500, {"error": "Could not fetch batch status"})
    finally:
        if conn is not None:
            conn.close()
