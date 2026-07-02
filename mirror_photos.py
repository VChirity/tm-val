#!/usr/bin/env python3
"""Espelha fotos dos atletas no Supabase Storage para carregamento rapido."""

from __future__ import annotations

import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))

from scraper import (  # noqa: E402
    ensure_photos_bucket,
    get_client,
    mirror_photo_to_storage,
)


def main() -> None:
    client = get_client()
    ensure_photos_bucket(client)

    rows = (
        client.table("athletes")
        .select("name,gender,photo_url")
        .not_.is_("photo_url", "null")
        .execute()
        .data
        or []
    )

    updated = 0
    for index, row in enumerate(rows, start=1):
        photo_url = row.get("photo_url")
        if not photo_url or "supabase.co/storage" in photo_url:
            continue

        print(f"[{index}/{len(rows)}] {row['name']}")
        mirrored = mirror_photo_to_storage(
            client,
            row["gender"],
            row["name"],
            photo_url,
        )
        if mirrored and mirrored != photo_url:
            client.table("athletes").update({"photo_url": mirrored}).eq(
                "name", row["name"]
            ).eq("gender", row["gender"]).execute()
            updated += 1
        time.sleep(0.05)

    print(f"Fotos espelhadas: {updated}")


if __name__ == "__main__":
    main()
