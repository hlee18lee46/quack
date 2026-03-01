# mongo_api.py
from fastapi import APIRouter

router = APIRouter(prefix="/mongo", tags=["mongo"])

@router.get("/")
async def get_mongo_status():
    return {"status": "connected"}