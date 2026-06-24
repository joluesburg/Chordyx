# Conectar Chordyx a GitHub y activar Pages

Tu repo local está en:

`/Users/josel.espinosaburgos/Documents/Login/Chordyx`

Rama actual: **`joluesburg`** (2 commits).

---

## Paso 1 — Crear el repo en GitHub

1. Entra en [github.com/new](https://github.com/new)
2. **Repository name:** `Chordyx` (o el nombre que prefieras)
3. **Visibility:** Public (necesario para GitHub Pages gratis) o Private (Pages también funciona en planes de pago)
4. **No** marques “Add a README” ni “Add .gitignore” — ya los tienes localmente
5. Clic en **Create repository**

---

## Paso 2 — Conectar remoto y subir

Sustituye `TU_USUARIO` por tu usuario de GitHub (ej. `joluesburg`):

```bash
cd "/Users/josel.espinosaburgos/Documents/Login/Chordyx"

git remote add origin https://github.com/TU_USUARIO/Chordyx.git

git push -u origin joluesburg
```

Si GitHub te pide autenticación:
- **HTTPS:** usa un [Personal Access Token](https://github.com/settings/tokens) (scope `repo`) como contraseña
- **SSH:** si ya tienes clave SSH configurada:

```bash
git remote set-url origin git@github.com:TU_USUARIO/Chordyx.git
git push -u origin joluesburg
```

---

## Paso 3 — (Opcional) Renombrar rama a `main`

GitHub Pages y muchas guías usan `main`. Si quieres alinear:

```bash
git branch -m joluesburg main
git push -u origin main
```

En GitHub: **Settings → General → Default branch →** cambia a `main`.

---

## Paso 4 — Activar GitHub Pages

1. Repo en GitHub → **Settings → Pages**
2. **Build and deployment → Source:** Deploy from a branch
3. **Branch:** `main` (o `joluesburg` si no renombraste) → carpeta **`/docs`**
4. **Save**

En 1–2 minutos la web estará en:

`https://TU_USUARIO.github.io/Chordyx/`

Privacidad: `https://TU_USUARIO.github.io/Chordyx/privacy.html`

---

## Paso 5 — App Store Connect

| Campo | URL |
|-------|-----|
| Privacy Policy URL | `https://TU_USUARIO.github.io/Chordyx/privacy.html` |
| Marketing URL (opcional) | `https://TU_USUARIO.github.io/Chordyx/` |

---

## Comprobar

```bash
git remote -v
git status
git log --oneline -3
```

Deberías ver `origin` apuntando a GitHub y `Your branch is up to date with 'origin/joluesburg'` (o `main`).

---

## Problemas frecuentes

| Error | Solución |
|-------|----------|
| `remote origin already exists` | `git remote remove origin` y repite Paso 2 |
| `failed to push — rejected` | Primero creaste el repo con README en GitHub → haz pull con `--allow-unrelated-histories` o borra el repo y créalo vacío |
| Pages no carga | Espera 2 min; revisa que la rama y `/docs` coincidan en Settings → Pages |
| 404 en privacy.html | Confirma que `docs/privacy.html` está en la rama que publica Pages |
