#!/usr/bin/env python3
"""Faz build do Flutter Web e publica no Supabase Storage."""

from __future__ import annotations

import mimetypes
import os
import subprocess
import sys
from pathlib import Path

from dotenv import load_dotenv
from supabase import create_client

ROOT = Path(__file__).resolve().parent
FLUTTER_DIR = ROOT / "flutter_app"
BUILD_DIR = FLUTTER_DIR / "build" / "web"
ENV_PATH = ROOT / ".env"
BUCKET = "tm-val-app"
BASE_HREF = f"/storage/v1/object/public/{BUCKET}/"

# Supabase Storage usa text/plain por padrao; mapeamento explicito evita HTML cru no browser.
MIME_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".wasm": "application/wasm",
    ".png": "image/png",
    ".ico": "image/x-icon",
    ".svg": "image/svg+xml",
    ".woff": "font/woff",
    ".woff2": "font/woff2",
    ".ttf": "font/ttf",
    ".otf": "font/otf",
}


def guess_content_type(path: Path) -> str:
    ext = path.suffix.lower()
    if ext in MIME_TYPES:
        return MIME_TYPES[ext]
    guessed = mimetypes.guess_type(path.name)[0]
    return guessed or "application/octet-stream"


def load_client():
    load_dotenv(ENV_PATH)
    url = os.getenv("SUPABASE_URL", "").strip()
    key = os.getenv("SUPABASE_SERVICE_KEY", "").strip() or os.getenv(
        "SUPABASE_ANON_KEY", ""
    ).strip()
    if not url or not key:
        print("Defina SUPABASE_URL e SUPABASE_ANON_KEY no .env")
        sys.exit(1)
    return create_client(url, key), url


def build_flutter() -> None:
    print("Building Flutter Web...")
    flutter = os.environ.get("FLUTTER_BIN", r"C:\Flutter\bin\flutter.bat")
    subprocess.run(
        [
            flutter,
            "build",
            "web",
            "--release",
            f"--base-href={BASE_HREF}",
        ],
        cwd=FLUTTER_DIR,
        check=True,
        shell=isinstance(flutter, str) and flutter.endswith(".bat"),
    )


def ensure_bucket(client) -> None:
    try:
        buckets = client.storage.list_buckets()
        names = {b.name for b in buckets}
        if BUCKET in names:
            return
    except Exception:
        pass

    try:
        print(f"Criando bucket publico '{BUCKET}'...")
        client.storage.create_bucket(BUCKET, options={"public": True})
    except Exception as exc:
        print(f"Bucket '{BUCKET}' ja existe ou sera usado via SQL ({exc}).")


def upload_build(client) -> int:
    if not BUILD_DIR.exists():
        print("Build nao encontrado. Rode build_flutter primeiro.")
        sys.exit(1)

    uploaded = 0
    for path in BUILD_DIR.rglob("*"):
        if not path.is_file():
            continue

        rel = path.relative_to(BUILD_DIR).as_posix()
        content_type = guess_content_type(path)

        with path.open("rb") as handle:
            client.storage.from_(BUCKET).upload(
                rel,
                handle.read(),
                file_options={
                    "content-type": content_type,
                    "upsert": "true",
                    "cache-control": "3600",
                },
            )
        uploaded += 1
        if uploaded % 10 == 0:
            print(f"  {uploaded} arquivos...")

    return uploaded


def main() -> None:
    client, url = load_client()
    build_flutter()
    ensure_bucket(client)
    count = upload_build(client)

    public_url = f"{url.rstrip('/')}/storage/v1/object/public/{BUCKET}/index.html"
    print(f"\nDeploy concluido ({count} arquivos).")
    print(f"Arquivos publicos em: {public_url}")
    print(
        "\nATENCAO: o Supabase Storage serve HTML como text/plain por seguranca."
        "\nEssa URL NAO abre o app no navegador. Publique build/web em"
        " Firebase Hosting, Vercel, Netlify ou Cloudflare Pages."
    )


if __name__ == "__main__":
    main()
