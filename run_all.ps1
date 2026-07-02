# Executa setup completo do TM Val (banco + scraper + app web)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

Set-Location $root

Write-Host "==> Instalando dependencias Python..." -ForegroundColor Cyan
py -m pip install -r requirements.txt --quiet

Write-Host "==> Criando tabelas no Supabase..." -ForegroundColor Cyan
py setup_database.py

Write-Host "==> Coletando Top 100 da WTT..." -ForegroundColor Cyan
py scraper.py

Write-Host "==> Iniciando app Flutter (PWA)..." -ForegroundColor Cyan
Set-Location "$root\flutter_app"
flutter pub get
flutter run -d web-server --web-port=8080 --web-hostname=localhost
