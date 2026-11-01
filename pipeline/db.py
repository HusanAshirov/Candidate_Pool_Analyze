"""PostgreSQL connection and raw-layer writes."""
import os

import psycopg
from dotenv import load_dotenv
from psycopg.types.json import Jsonb

load_dotenv()

INSERT_RAW = """
    INSERT INTO raw.records (source, record_type, source_record_id, payload)
    VALUES (%s, %s, %s, %s)
    ON CONFLICT (source, source_record_id, snapshot_date) DO NOTHING
"""


def connect():
    return psycopg.connect(
        host=os.environ["PG_HOST"],
        port=os.environ["PG_PORT"],
        dbname=os.environ["PG_DB"],
        user=os.environ["PG_USER"],
        password=os.environ["PG_PASSWORD"],
    )


def save_raw_records(conn, source, record_type, records):
    """Insert (source_record_id, payload) pairs; return how many were new in this snapshot.

    The caller owns the transaction.
    """
    inserted = 0
    with conn.cursor() as cur:
        for source_record_id, payload in records:
            cur.execute(INSERT_RAW, (source, record_type, str(source_record_id), Jsonb(payload)))
            inserted += cur.rowcount
    return inserted
