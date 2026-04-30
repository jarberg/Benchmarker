from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel

from database import get_db, Config

router = APIRouter(prefix="/configs", tags=["configs"])


# ── schemas ───────────────────────────────────────────────────────────────────

class ConfigCreate(BaseModel):
    name: Optional[str] = None
    config: dict


class ConfigResponse(BaseModel):
    id: str
    name: Optional[str]
    config: dict

    class Config:
        from_attributes = True


# ── routes ────────────────────────────────────────────────────────────────────

@router.get("", response_model=List[ConfigResponse])
def list_configs(db: Session = Depends(get_db)):
    """Return all saved config presets."""
    return db.query(Config).all()


@router.post("", response_model=ConfigResponse, status_code=201)
def create_config(payload: ConfigCreate, db: Session = Depends(get_db)):
    """Save a new config preset."""
    cfg = Config(name=payload.name, config=payload.config)
    db.add(cfg)
    db.commit()
    db.refresh(cfg)
    return cfg


@router.get("/{config_id}", response_model=ConfigResponse)
def get_config(config_id: str, db: Session = Depends(get_db)):
    cfg = db.query(Config).filter(Config.id == config_id).first()
    if not cfg:
        raise HTTPException(status_code=404, detail="Config not found")
    return cfg


@router.delete("/{config_id}", status_code=204)
def delete_config(config_id: str, db: Session = Depends(get_db)):
    cfg = db.query(Config).filter(Config.id == config_id).first()
    if not cfg:
        raise HTTPException(status_code=404, detail="Config not found")
    db.delete(cfg)
    db.commit()
