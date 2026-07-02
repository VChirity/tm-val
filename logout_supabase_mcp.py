import sqlite3
from pathlib import Path

DB = Path(r"C:\Users\ADMIN\AppData\Roaming\Cursor\User\globalStorage\state.vscdb")
conn = sqlite3.connect(DB)
cur = conn.cursor()
cur.execute("SELECT key FROM ItemTable")
keys = [row[0] for row in cur.fetchall()]

markers = (
    "W3BsdWdpbi1zdXBhYmFzZS1zdXBhYmFzZ",  # Plugin-supabase-supabase (base64)
    "W3VybDphSFIwY0hNNkx5OXRZM0F1YzNWd1lXSmhjMlV1WTI5dEwyMWpjQV0",  # url:https://mcp.supabase.com/mcp
    "plugin-supabase-supabase",
)

to_delete = [
    k
    for k in keys
    if any(m in k for m in markers)
]

print(f"Removendo {len(to_delete)} entradas...")
for key in to_delete:
    cur.execute("DELETE FROM ItemTable WHERE key = ?", (key,))

conn.commit()
conn.close()
print("Logout Supabase MCP concluido.")
