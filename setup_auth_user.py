#!/usr/bin/env python3
"""Cria usuário Supabase Auth para acesso ao TM Val."""

from __future__ import annotations

import os
import sys
from pathlib import Path

from dotenv import load_dotenv
from supabase import create_client

ROOT = Path(__file__).resolve().parent
ENV_PATH = ROOT / ".env"

APP_EMAIL = "victorchirity@colegioequacao.com"
APP_PASSWORD = "sushi123"


def main() -> None:
    load_dotenv(ENV_PATH)
    url = os.getenv("SUPABASE_URL", "").strip()
    key = os.getenv("SUPABASE_ANON_KEY", "").strip() or os.getenv(
        "SUPABASE_SERVICE_KEY", ""
    ).strip()

    if not url or not key:
        print("Configure SUPABASE_URL e SUPABASE_ANON_KEY no .env")
        sys.exit(1)

    client = create_client(url, key)

    print(f"Verificando usuário {APP_EMAIL}...")
    try:
        client.auth.sign_in_with_password(
            {"email": APP_EMAIL, "password": APP_PASSWORD}
        )
        print("Usuário já existe e a senha está correta.")
        return
    except Exception:
        pass

    print("Criando usuário...")
    try:
        response = client.auth.sign_up(
            {"email": APP_EMAIL, "password": APP_PASSWORD}
        )
        if response.user:
            print("Usuário criado. Confirme o e-mail via SQL se necessário.")
        else:
            print("Resposta inesperada no sign_up:", response)
    except Exception as exc:
        print(f"Erro no sign_up: {exc}")
        sys.exit(1)


if __name__ == "__main__":
    main()
