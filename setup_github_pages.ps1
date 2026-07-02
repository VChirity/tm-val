# Publica o TM Val no GitHub Pages (repo: VChirity/tm-val)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$gh = "$env:ProgramFiles\GitHub CLI\gh.exe"
if (-not (Test-Path $gh)) {
    throw "GitHub CLI nao encontrado. Instale com: winget install GitHub.cli"
}

function Get-GitHubToken {
    $inputText = "protocol=https`nhost=github.com`n"
    $output = $inputText | & git credential-manager get 2>$null
    foreach ($line in $output) {
        if ($line -like "password=*") {
            return $line.Substring(9)
        }
    }
    throw "Token do GitHub nao encontrado. Faca login no GitHub no navegador/VS Code e tente de novo."
}

function Get-DotEnvValue([string]$Key) {
    $value = py -c @"
from pathlib import Path
from dotenv import dotenv_values
for path in [Path(r'$root/.env'), Path(r'$root/flutter_app/assets/.env')]:
    if path.exists():
        data = dotenv_values(path)
        val = data.get('$Key')
        if val:
            print(val)
            break
"@
    if (-not $value) {
        throw "Variavel $Key nao encontrada em .env"
    }
    return $value.Trim()
}

Write-Host "==> Autenticando no GitHub..." -ForegroundColor Cyan
$env:GH_TOKEN = Get-GitHubToken
$ghUser = & $gh api user -q .login
if (-not $ghUser) {
    throw "Nao foi possivel autenticar no GitHub."
}
Write-Host "Conta: $ghUser" -ForegroundColor DarkGray

$owner = $ghUser
$repo = "tm-val"

Write-Host "==> Lendo credenciais Supabase..." -ForegroundColor Cyan
$supabaseUrl = Get-DotEnvValue "SUPABASE_URL"
$supabaseAnon = Get-DotEnvValue "SUPABASE_ANON_KEY"

Write-Host "==> Preparando repositorio git..." -ForegroundColor Cyan
if (-not (Test-Path ".git")) {
    git init | Out-Null
    git branch -M main | Out-Null
}

git add .
$status = git status --porcelain
if ($status) {
    git commit -m "Publica TM Val com deploy automatico no GitHub Pages" | Out-Null
} else {
    Write-Host "Nenhuma alteracao nova para commit." -ForegroundColor Yellow
}

Write-Host "==> Criando/atualizando repositorio remoto..." -ForegroundColor Cyan
$repoExists = $false
try {
    & $gh repo view "$owner/$repo" --json name 1>$null 2>$null
    $repoExists = $LASTEXITCODE -eq 0
} catch {
    $repoExists = $false
}

if (-not $repoExists) {
    & $gh repo create "$owner/$repo" --public --description "TM Val - consulta de atletas WTT" --source=. --remote=origin --push
} else {
    $remotes = git remote
    if ($remotes -notcontains "origin") {
        git remote add origin "https://github.com/$owner/$repo.git"
    }
    git push -u origin main
}

Write-Host "==> Configurando secrets do Actions..." -ForegroundColor Cyan
$supabaseUrl | & $gh secret set SUPABASE_URL --repo "$owner/$repo"
$supabaseAnon | & $gh secret set SUPABASE_ANON_KEY --repo "$owner/$repo"

Write-Host "==> Ativando GitHub Pages (GitHub Actions)..." -ForegroundColor Cyan
& $gh api "repos/$owner/$repo/pages" -X PUT -f build_type=workflow 2>$null
if ($LASTEXITCODE -ne 0) {
    & $gh api "repos/$owner/$repo/pages" -X POST -f build_type=workflow
}

Write-Host "==> Disparando deploy..." -ForegroundColor Cyan
& $gh workflow run "Deploy TM Val (Flutter Web)" --repo "$owner/$repo" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "O workflow rodara automaticamente apos o push." -ForegroundColor Yellow
}

$pagesUrl = "https://$owner.github.io/$repo/"
Write-Host ""
Write-Host "Concluido!" -ForegroundColor Green
Write-Host "URL do app (aguarde 2-5 min): $pagesUrl" -ForegroundColor Green
Write-Host "Acompanhe em: https://github.com/$owner/$repo/actions" -ForegroundColor Cyan
