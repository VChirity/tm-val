# Publicar TM Val no GitHub Pages

Backend continua 100% no Supabase. O GitHub Pages hospeda só a interface web.

## URL final

Depois do deploy, o app fica em:

`https://SEU-USUARIO.github.io/NOME-DO-REPO/`

Exemplo: se o repositório for `tm-val`, a URL será `https://seu-usuario.github.io/tm-val/`

## Passo a passo (só uma vez)

### 1. Criar repositório no GitHub

- Acesse https://github.com/new
- Nome sugerido: `tm-val`
- Deixe **Public**
- **Não** marque README, .gitignore ou license (o projeto já tem arquivos locais)

### 2. Adicionar secrets no GitHub

No repositório: **Settings → Secrets and variables → Actions → New repository secret**

| Nome | Valor |
|------|-------|
| `SUPABASE_URL` | Copie de `.env` ou `flutter_app/assets/.env` |
| `SUPABASE_ANON_KEY` | Copie de `.env` ou `flutter_app/assets/.env` |

A anon key pode ser pública (o app roda no navegador), mas não commite o `.env` no git.

### 3. Ativar GitHub Pages

No repositório: **Settings → Pages**

- **Source:** GitHub Actions

### 4. Enviar o código

No PowerShell, na pasta do projeto:

```powershell
cd "D:\Projetos\TM Val"
git init
git add .
git commit -m "Configura deploy do TM Val no GitHub Pages"
git branch -M main
git remote add origin https://github.com/SEU-USUARIO/tm-val.git
git push -u origin main
```

Troque `SEU-USUARIO` e `tm-val` pelos nomes reais.

### 5. Aguardar o deploy

- Vá em **Actions** no GitHub
- O workflow **Deploy TM Val (Flutter Web)** roda sozinho
- Quando terminar, a URL aparece no job (environment **github-pages**)

## Atualizar o app online

Qualquer `git push` na branch `main` republica automaticamente.

## Desenvolvimento local

```powershell
cd "D:\Projetos\TM Val\flutter_app"
flutter run -d web-server --web-port=8080 --web-hostname=localhost
```

Abra http://localhost:8080
