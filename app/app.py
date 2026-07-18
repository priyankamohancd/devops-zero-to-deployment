"""DevOps Starter Kit application.

A small Flask service that demonstrates health checks, database connectivity,
containerization, CI/CD, and deployment to Amazon EKS.
"""
from __future__ import annotations

import os
import time
from datetime import datetime, timezone
from typing import Any

from flask import Flask, jsonify, render_template, request
from sqlalchemy import DateTime, Integer, String, create_engine, select, text
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker


class Base(DeclarativeBase):
    """SQLAlchemy declarative base."""


class DeploymentRecord(Base):
    """A tiny business entity used to prove database persistence."""

    __tablename__ = "deployment_records"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    service_name: Mapped[str] = mapped_column(String(80), nullable=False)
    environment: Mapped[str] = mapped_column(String(40), nullable=False)
    status: Mapped[str] = mapped_column(String(30), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "service_name": self.service_name,
            "environment": self.environment,
            "status": self.status,
            "created_at": self.created_at.isoformat(),
        }


def normalize_database_url(url: str) -> str:
    """Convert common PostgreSQL URLs to SQLAlchemy's psycopg driver format."""
    if url.startswith("postgres://"):
        return url.replace("postgres://", "postgresql+psycopg://", 1)
    if url.startswith("postgresql://"):
        return url.replace("postgresql://", "postgresql+psycopg://", 1)
    return url


def initialize_database(engine: Any, attempts: int = 10, delay_seconds: int = 2) -> None:
    """Wait for the database and safely create the demo table.

    PostgreSQL advisory locking prevents two EKS replicas from attempting the
    initial schema creation at exactly the same time.
    """
    for attempt in range(1, attempts + 1):
        try:
            if engine.dialect.name == "postgresql":
                with engine.begin() as connection:
                    connection.execute(text("SELECT pg_advisory_lock(20260718)"))
                    try:
                        Base.metadata.create_all(bind=connection)
                    finally:
                        connection.execute(text("SELECT pg_advisory_unlock(20260718)"))
            else:
                Base.metadata.create_all(engine)
            return
        except OperationalError:
            if attempt == attempts:
                raise
            time.sleep(delay_seconds)


def create_app(test_config: dict[str, Any] | None = None) -> Flask:
    app = Flask(__name__)
    app.config.from_mapping(
        DATABASE_URL=normalize_database_url(
            os.getenv("DATABASE_URL", "sqlite+pysqlite:////tmp/devops-starter-kit.db")
        ),
        APP_VERSION=os.getenv("APP_VERSION", "development"),
        APP_ENV=os.getenv("APP_ENV", "local"),
        GIT_COMMIT=os.getenv("GIT_COMMIT", "unknown"),
    )

    if test_config:
        app.config.update(test_config)

    database_url = normalize_database_url(app.config["DATABASE_URL"])
    engine_options: dict[str, Any] = {"pool_pre_ping": True}
    if database_url.startswith("sqlite"):
        engine_options["connect_args"] = {"check_same_thread": False}

    engine = create_engine(database_url, **engine_options)
    session_factory = sessionmaker(bind=engine, expire_on_commit=False)
    initialize_database(engine)

    app.extensions["db_engine"] = engine
    app.extensions["db_session_factory"] = session_factory

    @app.get("/")
    def home():
        with session_factory() as session:
            records = session.scalars(
                select(DeploymentRecord)
                .order_by(DeploymentRecord.created_at.desc())
                .limit(20)
            ).all()

        return render_template(
            "index.html",
            records=records,
            app_version=app.config["APP_VERSION"],
            app_env=app.config["APP_ENV"],
            git_commit=app.config["GIT_COMMIT"],
            pod_name=os.getenv("POD_NAME", "local-container"),
        )

    @app.get("/health")
    def health():
        return jsonify({"status": "ok"}), 200

    @app.get("/ready")
    def ready():
        try:
            with engine.connect() as connection:
                connection.execute(text("SELECT 1"))
            return jsonify({"status": "ready", "database": "connected"}), 200
        except Exception as exc:  # pragma: no cover - depends on external database
            return jsonify({"status": "not-ready", "error": str(exc)}), 503

    @app.get("/api/info")
    def info():
        return jsonify(
            {
                "application": "devops-starter-kit",
                "version": app.config["APP_VERSION"],
                "environment": app.config["APP_ENV"],
                "git_commit": app.config["GIT_COMMIT"],
                "pod_name": os.getenv("POD_NAME", "local-container"),
                "node_name": os.getenv("NODE_NAME", "local-machine"),
            }
        )

    @app.get("/api/deployments")
    def list_deployments():
        with session_factory() as session:
            records = session.scalars(
                select(DeploymentRecord).order_by(DeploymentRecord.created_at.desc())
            ).all()
        return jsonify([record.to_dict() for record in records])

    @app.post("/api/deployments")
    def create_deployment():
        payload = request.get_json(silent=True) or request.form.to_dict()
        service_name = str(payload.get("service_name", "")).strip()
        environment = str(payload.get("environment", "")).strip()
        status = str(payload.get("status", "SUCCESS")).strip().upper()

        if not service_name or not environment:
            return jsonify({"error": "service_name and environment are required"}), 400

        allowed_statuses = {"SUCCESS", "FAILED", "RUNNING"}
        if status not in allowed_statuses:
            return jsonify({"error": f"status must be one of {sorted(allowed_statuses)}"}), 400

        record = DeploymentRecord(
            service_name=service_name,
            environment=environment,
            status=status,
        )
        with session_factory() as session:
            session.add(record)
            session.commit()

        return jsonify(record.to_dict()), 201

    return app


app = create_app()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
