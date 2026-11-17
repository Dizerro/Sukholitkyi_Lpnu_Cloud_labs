import json
import os
import time
from contextlib import asynccontextmanager

import redis
from fastapi import FastAPI, Depends, HTTPException, Response
from pydantic import BaseModel, Field
from sqlalchemy import create_engine, String, Text, select, func, text
from sqlalchemy.engine import URL
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker

url = URL.create(
    'postgresql+psycopg2',
    username=os.environ['DB_USER'],
    password=os.environ['DB_PASSWORD'],
    host=os.environ['DB_HOST'],
    port=5432,
    database=os.environ['DB_NAME'],
)

engine = create_engine(url, pool_pre_ping=True, pool_size=10, max_overflow=5, pool_timeout=10)
SessionLocal = sessionmaker(bind=engine)

REDIS_HOST = os.environ.get('REDIS_HOST')
CACHE_ENABLED = os.environ.get('CACHE_ENABLED', 'false').lower() == 'true'
CACHE_TTL = int(os.environ.get('CACHE_TTL', '30'))
CACHE_INVALIDATE = os.environ.get('CACHE_INVALIDATE', 'false').lower() == 'true'
LIST_KEY = 'notes:list'
LIST_LIMIT = 100

cache = (
    redis.Redis(host=REDIS_HOST, port=6379, decode_responses=True,
                socket_timeout=0.3, socket_connect_timeout=0.3)
    if REDIS_HOST else None
)
use_cache = CACHE_ENABLED and cache is not None


class Base(DeclarativeBase):
    pass


class Note(Base):
    __tablename__ = 'notes'
    id: Mapped[int] = mapped_column(primary_key=True)
    title: Mapped[str] = mapped_column(String(200))
    body: Mapped[str] = mapped_column(Text, default='')
    author: Mapped[str] = mapped_column(String(100), default='anonymous', index=True)


class NoteIn(BaseModel):
    title: str
    body: str = ''
    author: str = Field(default='anonymous', max_length=100)


@asynccontextmanager
async def lifespan(app):
    for _ in range(30):
        try:
            Base.metadata.create_all(engine)
            break
        except Exception:
            time.sleep(2)
    yield

    engine.dispose()


app = FastAPI(title='Notes API', lifespan=lifespan)


def get_db():
    with SessionLocal() as session:
        yield session


def to_dict(n):
    return {'id': n.id, 'title': n.title, 'body': n.body, 'author': n.author}


@app.get('/')
def root():
    return {'message': 'Notes API v2'}


@app.get('/health')
def health():
    return {'status': 'ok'}


@app.get('/notes')
def list_notes(db=Depends(get_db)):
    if use_cache:
        try:
            cached = cache.get(LIST_KEY)
            if cached is not None:
                cache.incr('stats:cache_hits')
                return Response(content=cached, media_type='application/json')
            cache.incr('stats:cache_misses')
        except redis.RedisError:
            pass

    notes = db.scalars(select(Note).order_by(Note.id.desc()).limit(LIST_LIMIT))
    payload = [to_dict(n) for n in notes]

    if use_cache:
        try:
            cache.set(LIST_KEY, json.dumps(payload), ex=CACHE_TTL)
        except redis.RedisError:
            pass
    return payload


@app.post('/notes', status_code=201)
def create_note(data: NoteIn, db=Depends(get_db)):
    n = Note(title=data.title, body=data.body, author=data.author)
    db.add(n)
    db.commit()
    db.refresh(n)
    invalidate_list()
    return to_dict(n)


@app.get('/notes/{note_id}')
def get_note(note_id: int, db=Depends(get_db)):
    n = db.get(Note, note_id)
    if not n:
        raise HTTPException(404, 'not found')
    return to_dict(n)


@app.delete('/notes/{note_id}', status_code=204)
def delete_note(note_id: int, db=Depends(get_db)):
    n = db.get(Note, note_id)
    if not n:
        raise HTTPException(404, 'not found')
    db.delete(n)
    db.commit()
    invalidate_list()


@app.get('/authors/{name}')
def get_author(name: str, db=Depends(get_db)):
    count = db.scalar(select(func.count()).select_from(Note).where(Note.author == name))
    if not count:
        raise HTTPException(404, 'not found')
    return {'name': name, 'notes': count}


@app.get('/stats')
def stats(db=Depends(get_db)):
    """Лічильники для таблиці в docs/CACHE.md: викликайте до і після тесту й віднімайте."""
    row = db.execute(text(
        'SELECT xact_commit, tup_returned, tup_fetched FROM pg_stat_database '
        'WHERE datname = current_database()'
    )).one()
    out = {'db': {'xact_commit': row[0], 'tup_returned': row[1], 'tup_fetched': row[2]}, 'cache': None}
    if cache is not None:
        try:
            out['cache'] = {
                'hits': int(cache.get('stats:cache_hits') or 0),
                'misses': int(cache.get('stats:cache_misses') or 0),
            }
        except redis.RedisError:
            pass
    return out


def invalidate_list():
    if use_cache and CACHE_INVALIDATE:
        try:
            cache.delete(LIST_KEY)
        except redis.RedisError:
            pass
