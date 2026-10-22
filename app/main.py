import os, time
from contextlib import asynccontextmanager
from fastapi import FastAPI, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import create_engine, String, Text, select
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
engine = create_engine(url, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine)


class Base(DeclarativeBase):
    pass


class Note(Base):
    __tablename__ = 'notes'
    id: Mapped[int] = mapped_column(primary_key=True)
    title: Mapped[str] = mapped_column(String(200))
    body: Mapped[str] = mapped_column(Text, default='')


class NoteIn(BaseModel):
    title: str
    body: str = ''


@asynccontextmanager
async def lifespan(app):
    for _ in range(30):  # база може стартувати повільніше за застосунок
        try:
            Base.metadata.create_all(engine)
            break
        except Exception:
            time.sleep(2)
    yield


app = FastAPI(title='Notes API', lifespan=lifespan)


def get_db():
    with SessionLocal() as session:
        yield session


def to_dict(n):
    return {'id': n.id, 'title': n.title, 'body': n.body}


@app.get('/')
def root():
    return {'message': 'Notes API v1'}


@app.get('/health')
def health():
    return {'status': 'ok'}


@app.get('/notes')
def list_notes(db=Depends(get_db)):
    return [to_dict(n) for n in db.scalars(select(Note))]


@app.post('/notes', status_code=201)
def create_note(data: NoteIn, db=Depends(get_db)):
    n = Note(title=data.title, body=data.body)
    db.add(n)
    db.commit()
    db.refresh(n)
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