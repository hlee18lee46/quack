import os
from typing import List, Optional

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel
import snowflake.connector
import os
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend
import snowflake.connector
from gradient_text_tool import (
    GradientChatInput,
    gradient_chat,
    GradientConfigError,
    GradientRequestError,
)
from mongo_api import router as mongo_router

import math

import json
import base58
from pydantic import BaseModel, Field
from fastapi import HTTPException

from solana.rpc.api import Client
from solders.keypair import Keypair
from solders.pubkey import Pubkey
from solders.instruction import Instruction, AccountMeta
from solders.message import MessageV0
from solders.transaction import VersionedTransaction
from solders.hash import Hash

from solana.rpc.commitment import Finalized

from solders.signature import Signature
from pydantic import BaseModel
from typing import Optional

from typing import Optional, List
from pydantic import BaseModel
from fastapi import Query
from fastapi.middleware.cors import CORSMiddleware
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.image import MIMEImage
import os

from fastapi.staticfiles import StaticFiles

app = FastAPI(title="Snowflake Events API")

app.mount("/static", StaticFiles(directory="static"), name="static")

# Add this block:
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allows all origins
    allow_credentials=True,
    allow_methods=["*"],  # Allows all methods (GET, POST, etc.)
    allow_headers=["*"],  # Allows all headers
)

app.include_router(mongo_router)


def send_graph_email(recipient_email: str, graph_path: str):
    sender_email = os.getenv("SENDER_EMAIL")
    password = os.getenv("SENDER_PASSWORD")
    
    msg = MIMEMultipart()
    msg['From'] = sender_email
    msg['To'] = recipient_email
    msg['Subject'] = "Your Quack Vitals Graph"
    
    msg.attach(MIMEText("Attached is your vitals graph from the Quack App.", 'plain'))
    
    # Attach the graph image
    with open(graph_path, 'rb') as f:
        img_data = f.read()
        image = MIMEImage(img_data, name=os.path.basename(graph_path))
        msg.attach(image)
    
    # Connect to the SMTP server (example uses Gmail)
    with smtplib.SMTP("smtp.gmail.com", 587) as server:
        server.starttls() # Secure the connection
        server.login(sender_email, password)
        server.send_message(msg)

def get_private_key_bytes():
    path = os.getenv("SNOWFLAKE_PRIVATE_KEY_PATH")
    if not path:
        raise RuntimeError("Missing SNOWFLAKE_PRIVATE_KEY_PATH")

    passphrase = os.getenv("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE") or None
    if passphrase:
        passphrase = passphrase.encode()

    with open(path, "rb") as f:
        p_key = serialization.load_pem_private_key(
            f.read(),
            password=passphrase,
            backend=default_backend()
        )

    # Snowflake connector expects DER bytes
    return p_key.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption()
    )

def get_conn():
    return snowflake.connector.connect(
        account=os.getenv("SNOWFLAKE_ACCOUNT"),
        user=os.getenv("SNOWFLAKE_USER"),
        private_key=get_private_key_bytes(),
        warehouse=os.getenv("SNOWFLAKE_WAREHOUSE"),
        database=os.getenv("SNOWFLAKE_DATABASE"),
        schema=os.getenv("SNOWFLAKE_SCHEMA"),
        role=os.getenv("SNOWFLAKE_ROLE"),
    )

def publish_any_memo(memo_obj: dict) -> str:
    client = get_solana_client()
    kp = get_solana_keypair()
    payer = kp.pubkey()

    memo_str = json.dumps(memo_obj, separators=(",", ":"), ensure_ascii=False)
    
    ix = Instruction(
        program_id=MEMO_PROGRAM_ID,
        accounts=[],
        data=memo_str.encode("utf-8"),
    )

    latest = client.get_latest_blockhash()
    if not latest.value:
        raise RuntimeError("Failed to fetch latest blockhash")

    msg = MessageV0.try_compile(
        payer=payer,
        instructions=[ix],
        address_lookup_table_accounts=[],
        recent_blockhash=latest.value.blockhash,
    )

    tx = VersionedTransaction(msg, [kp])
    res = client.send_transaction(tx)
    
    if not res.value:
        raise RuntimeError(f"send_transaction failed: {res}")

    return str(res.value)



class EventIn(BaseModel):
    id: str
    title: str
    starts_at: str  # 'YYYY-MM-DD HH:MM:SS'
    venue: Optional[str] = None
    city: Optional[str] = None

class EventOut(BaseModel):
    id: str
    title: str
    starts_at: str
    venue: Optional[str] = None
    city: Optional[str] = None
    created_at: str

class VitalsIn(BaseModel):
    wallet: str
    ts_ms: int
    hr_bpm: float
    br_rpm: float
    mode: Optional[str] = "continuous"


class VitalsRow(BaseModel):
    wallet: str
    ts_ms: int
    hr_bpm: float
    br_rpm: float
    mode: Optional[str] = None
    created_at: Optional[str] = None

class VitalsInsightIn(BaseModel):
    wallet: str
    limit: int = 120  # ~4 minutes if uploading every 2s

class CortexInsightIn(BaseModel):
    wallet: str
    limit: int = 120

class ChatIn(BaseModel):
    wallet: str
    message: str
    engine: Optional[str] = "cortex"  # "cortex" or "gradient"
    limit: int = 120                 # vitals lookback samples

load_dotenv()

@app.get("/health")
def health():
    try:
        conn = get_conn()
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
                cur.fetchone()
            return {"ok": True}
        finally:
            conn.close()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/events", response_model=dict)
def insert_event(e: EventIn):
    sql = """
        INSERT INTO EVENTS (id, title, starts_at, venue, city)
        VALUES (%s, %s, %s, %s, %s)
    """
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, (e.id, e.title, e.starts_at, e.venue, e.city))
        conn.commit()
        return {"ok": True, "inserted_id": e.id}
    except Exception as ex:
        raise HTTPException(status_code=500, detail=str(ex))
    finally:
        conn.close()

@app.post("/events/bulk", response_model=dict)
def insert_events_bulk(events: List[EventIn]):
    if not events:
        raise HTTPException(status_code=400, detail="events is empty")

    sql = """
        INSERT INTO EVENTS (id, title, starts_at, venue, city)
        VALUES (%s, %s, %s, %s, %s)
    """
    rows = [(e.id, e.title, e.starts_at, e.venue, e.city) for e in events]

    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.executemany(sql, rows)
        conn.commit()
        return {"ok": True, "inserted": len(events)}
    except Exception as ex:
        raise HTTPException(status_code=500, detail=str(ex))
    finally:
        conn.close()

@app.get("/events", response_model=dict)
def read_events(limit: int = Query(50, ge=1, le=1000)):
    sql = """
        SELECT id, title, TO_VARCHAR(starts_at), venue, city, TO_VARCHAR(created_at)
        FROM EVENTS
        ORDER BY created_at DESC
        LIMIT %s
    """
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, (limit,))
            rows = cur.fetchall()

        # rows are tuples in the same order as SELECT
        data = [
            {
                "id": r[0],
                "title": r[1],
                "starts_at": r[2],
                "venue": r[3],
                "city": r[4],
                "created_at": r[5],
            }
            for r in rows
        ]
        return {"ok": True, "events": data}
    except Exception as ex:
        raise HTTPException(status_code=500, detail=str(ex))
    finally:
        conn.close()

@app.post("/ai/chat", response_model=dict)
async def ai_chat(payload: GradientChatInput):
    try:
        text = await gradient_chat(
            prompt=payload.prompt,
            system=payload.system,
            model=payload.model,
            max_tokens=payload.max_tokens,
            temperature=payload.temperature,
        )
        return {"ok": True, "text": text}
    except GradientConfigError as e:
        raise HTTPException(status_code=500, detail=str(e))
    except GradientRequestError as e:
        raise HTTPException(
            status_code=e.status_code or 502,
            detail={"message": str(e), "body": e.body},
        )


MEMO_PROGRAM_ID = Pubkey.from_string("MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr")


def get_solana_client() -> Client:
    rpc = os.getenv("SOLANA_RPC_URL", "https://api.devnet.solana.com")
    return Client(rpc)


def get_solana_keypair() -> Keypair:
    b58 = os.getenv("SOLANA_PRIVATE_KEY_BASE58")
    if not b58:
        raise RuntimeError("Missing SOLANA_PRIVATE_KEY_BASE58 in .env")
    secret = base58.b58decode(b58)

    # solders Keypair.from_bytes expects 64-byte secret key (ed25519)
    # Many exports are 64 bytes; if you have 32 bytes, it’s a seed and needs conversion.
    if len(secret) != 64:
        raise RuntimeError(f"SOLANA_PRIVATE_KEY_BASE58 decoded length must be 64 bytes, got {len(secret)}")
    return Keypair.from_bytes(secret)


class SongMetadataIn(BaseModel):
    name: str = Field(..., examples=["Midnight Lofi #12"])
    artist: str = Field(..., examples=["Han"])
    bpm: int = Field(92, ge=40, le=220)
    key: str = Field("C minor")
    audio_url: str = Field(..., examples=["https://yourcdn.com/song.wav"])
    cover_url: Optional[str] = Field(None, examples=["https://yourcdn.com/cover.png"])

    # optional: hash of the audio bytes for integrity
    audio_sha256: Optional[str] = None


@app.post("/solana/devnet/publish-metadata", response_model=dict)
def publish_metadata_to_solana_devnet(payload: SongMetadataIn):
    try:
        client = get_solana_client()
        kp = get_solana_keypair()
        payer = kp.pubkey()

        # We'll map the incoming payload to a Vitals Proof Memo
        memo_obj = {
            "type": "vitals_anchor_v1",
            "wallet": payload.artist, # The iOS app sends solanaPublicKey here
            "avg_bpm": payload.bpm,
            "avg_rpm": payload.key,    # The iOS app sends RPM info here
            "timestamp": int(time.time())
        }
        
        memo_str = json.dumps(memo_obj, separators=(",", ":"), ensure_ascii=False)

        ix = Instruction(
            program_id=MEMO_PROGRAM_ID,
            accounts=[],
            data=memo_str.encode("utf-8"),
        )

        latest = client.get_latest_blockhash()
        if not latest.value:
            raise RuntimeError("Failed to fetch latest blockhash")

        msg = MessageV0.try_compile(
            payer=payer,
            instructions=[ix],
            address_lookup_table_accounts=[],
            recent_blockhash=latest.value.blockhash,
        )

        tx = VersionedTransaction(msg, [kp])
        res = client.send_transaction(tx)
        
        if not res.value:
            raise RuntimeError(f"Solana Tx Failed: {res}")

        return {
            "ok": True,
            "network": "devnet",
            "signature": str(res.value),
            "memo_preview": memo_obj
        }

    except Exception as e:
        print(f"❌ Solana Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


from solders.signature import Signature
import json
from fastapi import HTTPException

@app.get("/solana/devnet/memo/{signature}", response_model=dict)
def get_memo_from_signature(signature: str):
    """
    Fetch a devnet transaction by signature and extract Memo text.
    Works across solana-py/solders versions by trying multiple object paths.
    """
    try:
        client = get_solana_client()
        sig = Signature.from_string(signature)

        resp = client.get_transaction(
            sig,
            encoding="jsonParsed",
            max_supported_transaction_version=0,
        )

        if not resp.value:
            raise HTTPException(status_code=404, detail="Transaction not found (or not available yet).")

        v = resp.value

        # --- Try multiple known shapes to get log messages ---
        logs = None
        tried = []

        def try_get_logs(obj, path_name: str):
            nonlocal logs
            tried.append(path_name)
            if obj is None:
                return
            # solders uses snake_case: log_messages
            lm = getattr(obj, "log_messages", None)
            if isinstance(lm, list):
                logs = lm

        # Shape A: value.transaction.meta.log_messages
        tx = getattr(v, "transaction", None)
        try_get_logs(getattr(tx, "meta", None), "value.transaction.meta.log_messages")

        # Shape B: value.meta.log_messages
        if logs is None:
            try_get_logs(getattr(v, "meta", None), "value.meta.log_messages")

        # Shape C: value.transaction_status_meta.log_messages (some wrappers)
        if logs is None:
            try_get_logs(getattr(v, "transaction_status_meta", None), "value.transaction_status_meta.log_messages")

        # If still none, use JSON text if available (many solders objects expose to_json())
        logs_found = 0
        memos = []

        if logs is None:
            # Try to_json() on value (best chance to preserve structure)
            to_json = getattr(v, "to_json", None)
            if callable(to_json):
                import json as _json
                obj = _json.loads(to_json())
                # common JSON-RPC key
                logs = (((obj.get("meta") or {}).get("logMessages")) or [])
                tried.append("value.to_json()->meta.logMessages")
            else:
                logs = []
                tried.append("no logs path matched + no to_json()")

        logs_found = len(logs) if isinstance(logs, list) else 0

        if isinstance(logs, list):
            for line in logs:
                marker = "Program log: Memo"
                if marker in line and "): " in line:
                    memo_text = line.split("): ", 1)[1].strip()

                    # logs usually wrap memo in quotes
                    if memo_text.startswith('"') and memo_text.endswith('"'):
                        memo_text = memo_text[1:-1]

                    # unescape \" etc
                    try:
                        memo_text = memo_text.encode("utf-8").decode("unicode_escape")
                    except Exception:
                        pass

                    parsed = None
                    try:
                        parsed = json.loads(memo_text)
                    except Exception:
                        parsed = None

                    memos.append({"memo": memo_text, "json": parsed})

        return {
            "ok": True,
            "network": "devnet",
            "signature": signature,
            "memos": memos,
            "log_lines_found": logs_found,
            "paths_tried": tried,
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


def get_memo_from_signature(signature: str):
    """
    Fetch a devnet transaction by signature and extract Memo text from log messages.
    Version-proof: we convert the RPC response to a JSON-able dict and search for logMessages.
    """
    try:
        client = get_solana_client()
        sig = Signature.from_string(signature)

        resp = client.get_transaction(
            sig,
            encoding="json",  # keep generic; shape varies by version
            max_supported_transaction_version=0,
        )

        if not resp.value:
            raise HTTPException(status_code=404, detail="Transaction not found (or not available yet).")

        # Convert response object -> json-friendly dict (handles solders types)
        obj = json.loads(json.dumps(resp, default=str))

        # The logs can appear under:
        # resp["result"]["meta"]["logMessages"] (classic)
        # or other nesting depending on encoding wrapper.
        # We'll search for logMessages anywhere in the structure.

        def find_logs(x):
            if isinstance(x, dict):
                # common key in Solana JSON RPC
                if "logMessages" in x and isinstance(x["logMessages"], list):
                    return x["logMessages"]
                # sometimes snake_case
                if "log_messages" in x and isinstance(x["log_messages"], list):
                    return x["log_messages"]
                for v in x.values():
                    got = find_logs(v)
                    if got:
                        return got
            elif isinstance(x, list):
                for v in x:
                    got = find_logs(v)
                    if got:
                        return got
            return None

        logs = find_logs(obj) or []

        memos = []
        for line in logs:
            marker = "Program log: Memo"
            if marker in line and "): " in line:
                memo_text = line.split("): ", 1)[1].strip()

                # logs often wrap in quotes
                if memo_text.startswith('"') and memo_text.endswith('"'):
                    memo_text = memo_text[1:-1]

                # unescape \" etc.
                try:
                    memo_text = memo_text.encode("utf-8").decode("unicode_escape")
                except Exception:
                    pass

                parsed = None
                try:
                    parsed = json.loads(memo_text)
                except Exception:
                    parsed = None

                memos.append({"memo": memo_text, "json": parsed})

        return {
            "ok": True,
            "network": "devnet",
            "signature": signature,
            "memos": memos,
            "log_lines_found": len(logs),
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/vitals", response_model=dict)
def insert_vitals(v: VitalsIn):
    wallet = (v.wallet or "").strip()
    if not wallet:
        raise HTTPException(status_code=400, detail="wallet is required")

    sql = """
        INSERT INTO VITALS (wallet, ts_ms, hr_bpm, br_rpm, mode)
        VALUES (%s, %s, %s, %s, %s)
    """

    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, (wallet, v.ts_ms, v.hr_bpm, v.br_rpm, v.mode))
        conn.commit()
        return {"ok": True}
    except Exception as ex:
        raise HTTPException(status_code=500, detail=str(ex))
    finally:
        conn.close()

@app.get("/api/vitals", response_model=dict)
def read_vitals(
    wallet: Optional[str] = None,
    limit: int = Query(200, ge=1, le=2000)
):
    # If wallet is provided, filter by wallet; else show latest overall.
    if wallet:
        sql = """
            SELECT wallet, ts_ms, hr_bpm, br_rpm, mode, TO_VARCHAR(created_at)
            FROM VITALS
            WHERE wallet = %s
            ORDER BY ts_ms DESC
            LIMIT %s
        """
        params = (wallet, limit)
    else:
        sql = """
            SELECT wallet, ts_ms, hr_bpm, br_rpm, mode, TO_VARCHAR(created_at)
            FROM VITALS
            ORDER BY ts_ms DESC
            LIMIT %s
        """
        params = (limit,)

    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            rows = cur.fetchall()

        data = [
            {
                "wallet": r[0],
                "ts_ms": int(r[1]),
                "hr_bpm": float(r[2]),
                "br_rpm": float(r[3]),
                "mode": r[4],
                "created_at": r[5],
            }
            for r in rows
        ]
        return {"ok": True, "vitals": data}
    except Exception as ex:
        raise HTTPException(status_code=500, detail=str(ex))
    finally:
        conn.close()


@app.post("/ai/vitals-insight", response_model=dict)
async def vitals_insight(payload: VitalsInsightIn):
    wallet = (payload.wallet or "").strip()
    if not wallet:
        raise HTTPException(status_code=400, detail="wallet is required")

    limit = max(20, min(int(payload.limit), 600))

    sql = """
        SELECT ts_ms, hr_bpm, br_rpm
        FROM VITALS
        WHERE wallet = %s
        ORDER BY ts_ms DESC
        LIMIT %s
    """

    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, (wallet, limit))
            rows = cur.fetchall()
    except Exception as ex:
        raise HTTPException(status_code=500, detail=f"Snowflake query failed: {ex}")
    finally:
        conn.close()

    if not rows:
        raise HTTPException(status_code=404, detail="No vitals found for this wallet")

    # newest-first -> oldest-first
    rows = list(reversed(rows))

    ts = [int(r[0]) for r in rows]
    hr = [float(r[1]) for r in rows]
    br = [float(r[2]) for r in rows]

    def mean(x): return sum(x) / len(x)
    def mn(x): return min(x)
    def mx(x): return max(x)

    def trend_delta(x):
        k = max(5, len(x) // 3)
        return (sum(x[-k:]) / k) - (sum(x[:k]) / k)

    summary = {
        "wallet": wallet,
        "points": len(rows),
        "t0_ms": ts[0],
        "t1_ms": ts[-1],
        "hr": {"last": hr[-1], "avg": mean(hr), "min": mn(hr), "max": mx(hr), "trend": trend_delta(hr)},
        "br": {"last": br[-1], "avg": mean(br), "min": mn(br), "max": mx(br), "trend": trend_delta(br)},
    }

    system = (
        "You are Quack, a friendly wellness coach for a hackathon demo. "
        "Use the vitals summary to give a short, practical, non-alarming insight. "
        "No medical diagnosis. Keep it under 5 bullet points. "
        "If HR is trending up or high, suggest a simple breathing tip."
    )

    prompt = (
        "Vitals summary (JSON):\n"
        f"{json.dumps(summary, separators=(',', ':'), ensure_ascii=False)}\n\n"
        "Write:\n"
        "1) A 1-sentence summary\n"
        "2) 2-4 bullet insights\n"
        "3) One breathing tip"
    )

    try:
        text = await gradient_chat(
            prompt=prompt,
            system=system,
            model=None,         # uses GRADIENT_TEXT_MODEL default (llama3-8b-instruct)
            max_tokens=220,
            temperature=0.5,
        )
        return {"ok": True, "summary": summary, "insight": text}
    except GradientConfigError as e:
        raise HTTPException(status_code=500, detail=str(e))
    except GradientRequestError as e:
        raise HTTPException(
            status_code=e.status_code or 502,
            detail={"message": str(e), "body": e.body},
        )


@app.post("/ai/cortex/vitals-insight", response_model=dict)
def cortex_vitals_insight(payload: CortexInsightIn):
    wallet = (payload.wallet or "").strip()
    if not wallet:
        raise HTTPException(status_code=400, detail="wallet is required")

    limit = max(20, min(int(payload.limit), 600))

    # 1) Compute stats inside Snowflake
    sql_stats = """
        WITH x AS (
          SELECT hr_bpm, br_rpm
          FROM VITALS
          WHERE wallet = %s
          ORDER BY ts_ms DESC
          LIMIT %s
        )
        SELECT
          COUNT(*) AS n,
          AVG(hr_bpm) AS avg_hr,
          MIN(hr_bpm) AS min_hr,
          MAX(hr_bpm) AS max_hr,
          AVG(br_rpm) AS avg_br,
          MIN(br_rpm) AS min_br,
          MAX(br_rpm) AS max_br
        FROM x
    """

    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(sql_stats, (wallet, limit))
            r = cur.fetchone()
            if not r or int(r[0]) == 0:
                raise HTTPException(status_code=404, detail="No vitals found for this wallet")

            n = int(r[0])
            avg_hr, min_hr, max_hr = float(r[1]), float(r[2]), float(r[3])
            avg_br, min_br, max_br = float(r[4]), float(r[5]), float(r[6])

            # 2) Ask Cortex COMPLETE to generate insight
            prompt = (
                f"You are Quack, a friendly wellness coach for a hackathon demo. "
                f"No diagnosis. Keep it under 5 bullet points.\n\n"
                f"Vitals summary for last {n} samples:\n"
                f"- HR avg {avg_hr:.1f}, min {min_hr:.1f}, max {max_hr:.1f}\n"
                f"- BR avg {avg_br:.1f}, min {min_br:.1f}, max {max_br:.1f}\n\n"
                f"Give a short insight and one breathing tip."
            )

            sql_cortex = """
                SELECT SNOWFLAKE.CORTEX.COMPLETE(%s, %s) AS text
            """

            # Pick a Cortex model available in your account (you can change this)
            cortex_model = os.getenv("CORTEX_TEXT_MODEL", "mistral-large")

            cur.execute(sql_cortex, (cortex_model, prompt))
            out = cur.fetchone()
            text = (out[0] if out else "") or "(empty response)"

        return {
            "ok": True,
            "model": cortex_model,
            "wallet": wallet,
            "n": n,
            "stats": {
                "avg_hr": avg_hr, "min_hr": min_hr, "max_hr": max_hr,
                "avg_br": avg_br, "min_br": min_br, "max_br": max_br
            },
            "insight": str(text).strip(),
        }

    except HTTPException:
        raise
    except Exception as ex:
        raise HTTPException(status_code=500, detail=str(ex))
    finally:
        conn.close()


@app.post("/chat", response_model=dict)
async def chat(payload: ChatIn):
    wallet = (payload.wallet or "").strip()
    msg = (payload.message or "").strip()
    engine = (payload.engine or "cortex").strip().lower()

    if not wallet:
        raise HTTPException(status_code=400, detail="wallet is required")
    if not msg:
        raise HTTPException(status_code=400, detail="message is required")

    limit = max(20, min(int(payload.limit), 600))

    # --- Pull latest vitals from Snowflake ---
    sql = """
        SELECT ts_ms, hr_bpm, br_rpm
        FROM VITALS
        WHERE wallet = %s
        ORDER BY ts_ms DESC
        LIMIT %s
    """
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, (wallet, limit))
            rows = cur.fetchall()
    finally:
        conn.close()

    vitals_ctx = "No recent vitals available."
    if rows:
        rows = list(reversed(rows))
        hr = [float(r[1]) for r in rows]
        br = [float(r[2]) for r in rows]

        def mean(x): return sum(x) / len(x)

        vitals_ctx = (
            f"Recent vitals ({len(rows)} samples): "
            f"HR avg {mean(hr):.1f}, last {hr[-1]:.1f}; "
            f"BR avg {mean(br):.1f}, last {br[-1]:.1f}."
        )

    system = (
        "You are Quack, a friendly wellness chatbot for a hackathon demo. "
        "Be supportive and practical. No medical diagnosis. "
        "If user asks health questions, suggest general wellness tips and advise seeking professional help if concerned."
    )

    prompt = (
        f"{vitals_ctx}\n\n"
        f"User message: {msg}\n\n"
        "Respond conversationally in 2-6 short sentences."
    )

    # --- Generate response using selected engine ---
    if engine == "gradient":
        text = await gradient_chat(
            prompt=prompt,
            system=system,
            model=None,            # uses GRADIENT_TEXT_MODEL
            max_tokens=220,
            temperature=0.6,
        )
        return {"ok": True, "engine": "gradient", "reply": text, "vitals_ctx": vitals_ctx}

    elif engine == "cortex":
        cortex_model = os.getenv("CORTEX_TEXT_MODEL", "mistral-large")
        sql_cortex = "SELECT SNOWFLAKE.CORTEX.COMPLETE(%s, %s) AS text"
        conn = get_conn()
        try:
            with conn.cursor() as cur:
                cur.execute(sql_cortex, (cortex_model, system + "\n\n" + prompt))
                out = cur.fetchone()
                text = (out[0] if out else "") or "(empty response)"
        finally:
            conn.close()

        return {"ok": True, "engine": "cortex", "reply": str(text).strip(), "vitals_ctx": vitals_ctx}

    else:
        raise HTTPException(status_code=400, detail="engine must be 'cortex' or 'gradient'")


import hashlib, time
from fastapi import UploadFile, File, Form
from fastapi.responses import JSONResponse
from pathlib import Path

GRAPH_DIR = Path("static/graphs")
GRAPH_DIR.mkdir(parents=True, exist_ok=True)

@app.post("/nft/graph/memo", response_model=dict)
async def graph_to_memo(
    wallet: str = Form(...),
    file: UploadFile = File(...),
):
    # 1) save image
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="empty file")

    sha = hashlib.sha256(data).hexdigest()
    ts = int(time.time())
    fname = f"{wallet[:6]}_{ts}.png"
    path = GRAPH_DIR / fname
    path.write_bytes(data)

    # 2) public URL (LAN demo)
    image_url = f"https://d4f9-155-246-151-34.ngrok-free.app/static/graphs/{fname}"
    # 3) write memo on Solana (you already have publish_metadata_to_solana_devnet)
    memo_obj = {
        "type": "graph_proof_v1",
        "wallet": wallet,
        "image_url": image_url,
        "sha256": sha,
        "ts": ts,
    }

    # reuse your existing Memo publisher by making a tiny helper
    sig = publish_any_memo(memo_obj)  # <- you add this helper (same logic as publish-metadata)

    return {"ok": True, "image_url": image_url, "sha256": sha, "signature": sig, "memo": memo_obj}

import requests
from fastapi import UploadFile, File, Form

import requests
import json
import os

class PinataClient:
    def __init__(self):
        # I recommend using the JWT (API Secret Token) from Pinata
        self.jwt = os.getenv("PINATA_JWT")
        self.api_key = os.getenv("PINATA_API_KEY")
        self.secret_key = os.getenv("PINATA_API_SECRET")
        self.base_url = "https://api.pinata.cloud"

    def _get_headers(self):
        if self.jwt:
            return {"Authorization": f"Bearer {self.jwt}"}
        return {
            "pinata_api_key": self.api_key,
            "pinata_secret_api_key": self.secret_key,
        }

    def upload_file(self, file_bytes: bytes, filename: str) -> str:
        url = f"{self.base_url}/pinning/pinFileToIPFS"
        # For files, we don't set Content-Type; requests handles the boundary
        files = {"file": (filename, file_bytes)}
        response = requests.post(url, headers=self._get_headers(), files=files)
        response.raise_for_status()
        return response.json()["IpfsHash"]

    def upload_json(self, metadata: dict) -> str:
        url = f"{self.base_url}/pinning/pinJSONToIPFS"
        headers = self._get_headers()
        headers["Content-Type"] = "application/json"
        response = requests.post(url, headers=headers, json=metadata)
        response.raise_for_status()
        return response.json()["IpfsHash"]

pinata = PinataClient()

# --- Minting Logic ---
@app.post("/solana/mint-nft", response_model=dict)
async def mint_nft(
    name: str = Form(...),
    symbol: str = Form("QUACK"),
    file: UploadFile = File(...)
):
    try:
        # 1. Upload Image to IPFS
        image_bytes = await file.read()
        image_hash = pinata.upload_file(image_bytes, file.filename)
        image_url = f"https://gateway.pinata.cloud/ipfs/{image_hash}"

        # 2. Upload Metadata JSON to IPFS
        metadata = {
            "name": name,
            "symbol": symbol,
            "description": "Minted via Han's FastAPI Backend",
            "image": image_url,
            "attributes": [{"trait_type": "Source", "value": "Pinata"}],
            "properties": {
                "files": [{"uri": image_url, "type": "image/png"}],
                "category": "image"
            }
        }
        metadata_hash = pinata.upload_json(metadata)
        metadata_uri = f"https://gateway.pinata.cloud/ipfs/{metadata_hash}"

        # 3. Mint on Solana (Memo Version for Hackathon Proof)
        # Note: For a full Metaplex NFT, you'd typically use 'mpl-token-metadata' 
        # instructions. For a demo, we can record this URI in a Memo tx.
        sig = publish_any_memo({
            "type": "nft_mint_v1",
            "name": name,
            "uri": metadata_uri
        })

        return {
            "ok": True,
            "metadata_uri": metadata_uri,
            "image_url": image_url,
            "solana_sig": sig
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))




from solders.pubkey import Pubkey
from solders.instruction import Instruction, AccountMeta

# Metaplex Core Program ID
CORE_PROGRAM_ID = Pubkey.from_string("CoRiE2m29ogvS2rrvePWDooSByuNc976cu8yvV6S7zC")

@app.post("/solana/mint-real-nft", response_model=dict)
async def mint_real_nft(
    name: str = "Mushroom U1",
    symbol: str = "MUSH"
):
    try:
        client = get_solana_client()
        kp = get_solana_keypair()
        payer = kp.pubkey()
        
        # This is the address of the actual NFT asset
        asset_kp = Keypair()
        asset_pubkey = asset_kp.pubkey()
        
        # IPFS link from your Pinata upload
        uri = "https://gateway.pinata.cloud/ipfs/QmTjrKivbJvq2puZirq1uU35F29x7ZGFEc3SKGXKsZRj6s"

        # Construct the 'Create' instruction for Metaplex Core
        # Data Layout for 'Create' (Discriminator 0)
        # We manually pack the data to avoid broken libraries
        data = bytearray([0]) # Discriminator for Create
        data.extend(len(name).to_bytes(4, 'little'))
        data.extend(name.encode('utf-8'))
        data.extend(len(uri).to_bytes(4, 'little'))
        data.extend(uri.encode('utf-8'))
        
        # Define accounts required by Core
        accounts = [
            AccountMeta(asset_pubkey, True, True), # Asset account
            AccountMeta(payer, True, True),        # Payer
            AccountMeta(payer, True, False),       # Authority
            AccountMeta(Pubkey.from_string("11111111111111111111111111111111"), False, False), # System Program
        ]

        ix = Instruction(CORE_PROGRAM_ID, data, accounts)

        # Send Transaction
        latest = client.get_latest_blockhash()
        msg = MessageV0.try_compile(payer, [ix], [], latest.value.blockhash)
        tx = VersionedTransaction(msg, [kp, asset_kp])
        
        res = client.send_transaction(tx)
        
        return {
            "ok": True,
            "asset_address": str(asset_pubkey),
            "signature": str(res.value),
            "explorer_url": f"https://explorer.solana.com/address/{asset_pubkey}?network=devnet"
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# in app.py
import time, hashlib, os
from fastapi import UploadFile, File, Form, HTTPException
from pinata_utils import pin_file_to_ipfs, pin_json_to_ipfs

@app.post("/nft/graph/pinata", response_model=dict)
async def graph_to_pinata(
    wallet: str = Form(...),
    file: UploadFile = File(...),
):
    wallet = (wallet or "").strip()
    if not wallet:
        raise HTTPException(status_code=400, detail="wallet is required")

    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="empty file")

    sha256 = hashlib.sha256(data).hexdigest()
    ts = int(time.time())

    # 1) Upload PNG to IPFS
    up = await pin_file_to_ipfs(
        file_bytes=data,
        filename="graph.png",
        name=f"quack-graph-{wallet[:6]}-{ts}",
    )
    image_cid = up.get("IpfsHash")
    if not image_cid:
        raise HTTPException(status_code=500, detail=f"Pinata upload failed: {up}")

    # gateway URL for viewing
    gateway = os.getenv("PINATA_GATEWAY", "https://gateway.pinata.cloud/ipfs").rstrip("/")
    image_url = f"{gateway}/{image_cid}"
    image_uri = f"ipfs://{image_cid}"

    # 2) Create NFT metadata JSON (IPFS JSON)
    metadata = {
        "name": "Quack Vitals Graph",
        "description": "A minted snapshot of your vitals visualization (HR/BR) sourced from Snowflake.",
        "image": image_uri,  # wallets prefer ipfs://
        "attributes": [
            {"trait_type": "wallet", "value": wallet},
            {"trait_type": "sha256", "value": sha256},
            {"trait_type": "timestamp", "value": ts},
        ],
    }

    meta_up = await pin_json_to_ipfs(metadata, name=f"quack-meta-{wallet[:6]}-{ts}")
    meta_cid = meta_up.get("IpfsHash")
    if not meta_cid:
        raise HTTPException(status_code=500, detail=f"Pinata pinJSON failed: {meta_up}")

    metadata_uri = f"ipfs://{meta_cid}"
    metadata_url = f"{gateway}/{meta_cid}"

    return {
        "ok": True,
        "wallet": wallet,
        "sha256": sha256,
        "image_cid": image_cid,
        "image_uri": image_uri,
        "image_url": image_url,
        "metadata_cid": meta_cid,
        "metadata_uri": metadata_uri,
        "metadata_url": metadata_url,
    }
import pandas as pd

def data_from_snowflake(wallet_address: str, ctx):
    query = f"SELECT TS_MS, HR_BPM FROM VITALS WHERE WALLET = '{wallet_address}' ORDER BY TS_MS DESC LIMIT 50"
    # Use fetch_pandas_all() for direct conversion to a DataFrame
    cursor = ctx.cursor()
    cursor.execute(query)
    df = cursor.fetch_pandas_all()
    cursor.close()
    return df

import matplotlib.pyplot as plt
import os
import time

def generate_and_save_graph(wallet_address: str, df: pd.DataFrame):
    if df.empty:
        raise ValueError("No data found for this wallet.")
    
    plt.style.use('dark_background')
    fig, ax = plt.subplots(figsize=(12, 6))
    df = df.sort_values('TS_MS')

    # Plot lines
    ax.plot(df['TS_MS'], df['HR_BPM'], color='#007AFF', linewidth=3, label='Heart Rate (BPM)')
    if 'BR_RPM' in df.columns:
        ax.plot(df['TS_MS'], df['BR_RPM'], color='#AF52DE', linewidth=3, label='Breathing (RPM)')

    # --- THE ZOOM FIX ---
    # Calculate min/max and add a small 5% buffer so it's not touching the edges
    y_min = df['HR_BPM'].min()
    y_max = df['HR_BPM'].max()
    padding = max(2, (y_max - y_min) * 0.1) # Ensure at least 2 BPM of "room"
    
    ax.set_ylim(y_min - padding, y_max + padding)
    # --------------------

    ax.set_title(f"Vitals: {wallet_address[:6]}...", fontsize=16, fontweight='bold', pad=20)
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    ax.grid(color='gray', linestyle='--', alpha=0.3)
    ax.legend()

    filename = f"{wallet_address}_{int(time.time())}.png"
    save_path = os.path.join("static", "graphs", filename)
    os.makedirs(os.path.dirname(save_path), exist_ok=True)
    
    plt.savefig(save_path, dpi=150, bbox_inches='tight')
    plt.close()
    return filename, save_path


@app.post("/mint-and-email")
async def mint_and_email(wallet: str, email: str):
    local_ctx = None
    try:
        # 1. Use the correct function name: get_conn()
        local_ctx = get_conn() 
        
        # 2. Get the data
        df = data_from_snowflake(wallet, local_ctx) 
        
        if df is None or df.empty:
            return {"status": "error", "message": "No data found in Snowflake for this wallet."}

        # 3. Generate and save the graph
        filename, filepath = generate_and_save_graph(wallet, df)
        
        # 4. Send email using SENDER_EMAIL/SENDER_PASSWORD from your .env
        send_graph_email(email, filepath)
        
        return {"status": "success", "message": f"Graph sent to {email}", "filename": filename}

    except Exception as e:
        return {"status": "error", "message": f"Details: {str(e)}"}
    finally:
        if local_ctx:
            local_ctx.close()

@app.post("/ai/gradient-meditation")
async def gradient_meditation(wallet: str = Query(...)):
    # Clean the wallet string from the URL
    wallet = wallet.strip()
    
    # 1. Fetch real vitals from Snowflake
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            # Snowflake query using the wallet from the query param
            cur.execute("SELECT HR_BPM, BR_RPM FROM VITALS WHERE wallet=%s ORDER BY TS_MS DESC LIMIT 60", (wallet,))
            rows = cur.fetchall()
    finally:
        conn.close()

    if not rows:
        # Fallback if no data is found so the app doesn't crash during the demo
        avg_hr, latest_hr, state = 75.0, 75.0, "NEUTRAL"
    else:
        avg_hr = sum(r[0] for r in rows) / len(rows)
        latest_hr = rows[0][0]
        state = "STRESSED" if latest_hr > 90 else "TIRED" if latest_hr < 65 else "NEUTRAL"

    # 2. ASK GRADIENT AI TO BE THE "ORCHESTRATOR"
    system_prompt = (
        "You are the mediQuack Bio-Feedback DJ. You select music based on Snowflake vitals. "
        "Tracks available: 'flute', 'yoga', 'mountain'."
    )
    user_prompt = (
        f"User is currently in a {state} state (Avg HR: {avg_hr:.1f}, Latest: {latest_hr:.1f}).\n"
        "Selection Rules:\n"
        "1. If STRESSED: pick 'yoga' (The Mountain Relax Yoga) to lower HR.\n"
        "2. If TIRED: pick 'flute' (Miromax Flute) to provide uplifting focus.\n"
        "3. If NEUTRAL: pick 'mountain' (The Mountain Meditation) for equanimity.\n"
        "Return ONLY the track name."
    )

    try:
        selected = await gradient_chat(prompt=user_prompt, system=system_prompt)
        selected = selected.strip().lower().replace("'", "").replace('"', "")
    except:
        selected = "mountain" # Safe fallback

    file_map = {
        "flute": "miromaxmusic-meditation-flute-455457.mp3",
        "yoga": "the_mountain-meditation-relax-yoga-music-443538.mp3",
        "mountain": "the_mountain-meditation-meditation-music-490007.mp3"
    }
    
    filename = file_map.get(selected, file_map["mountain"])
    track_url = f"https://d4f9-155-246-151-34.ngrok-free.app/static/audio/{filename}"
    
    return {
        "ok": True,
        "track_url": track_url,
        "insight": f"Gradient AI selected {selected.upper()} therapy because your heart rate is {latest_hr:.0f} BPM."
    }
if __name__ == "__main__":
    import uvicorn
    import os

    port = int(os.getenv("PORT", 8000))
    uvicorn.run(
        "app:app",
        host="0.0.0.0",
        port=port,
        reload=True,   # auto-reload on code change
    )
