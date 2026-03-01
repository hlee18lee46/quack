# pinata_utils.py
import os
import httpx

PINATA_FILE_URL = "https://api.pinata.cloud/pinning/pinFileToIPFS"
PINATA_JSON_URL = "https://api.pinata.cloud/pinning/pinJSONToIPFS"

def _pinata_headers():
    jwt = os.getenv("PINATA_JWT")
    if not jwt:
        raise RuntimeError("Missing PINATA_JWT in .env")
    return {"Authorization": f"Bearer {jwt}"}

async def pin_file_to_ipfs(file_bytes: bytes, filename: str, name: str):
    headers = _pinata_headers()

    # multipart/form-data
    files = {
        "file": (filename, file_bytes, "image/png"),
    }
    # optional metadata
    data = {
        "pinataMetadata": f'{{"name":"{name}"}}'
    }

    async with httpx.AsyncClient(timeout=60.0) as client:
        r = await client.post(PINATA_FILE_URL, headers=headers, files=files, data=data)
        r.raise_for_status()
        return r.json()  # { IpfsHash, PinSize, Timestamp }

async def pin_json_to_ipfs(obj: dict, name: str):
    headers = _pinata_headers()
    payload = {
        "pinataMetadata": {"name": name},
        "pinataContent": obj,
    }
    async with httpx.AsyncClient(timeout=60.0) as client:
        r = await client.post(PINATA_JSON_URL, headers=headers, json=payload)
        r.raise_for_status()
        return r.json()  # { IpfsHash, PinSize, Timestamp }