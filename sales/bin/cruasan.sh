#!/usr/bin/env bash
# cruasan.sh — wrapper HTTPS mínimo para Oven (cliente-facing).
#
# Habla con app.cruasan.com solo por endpoints REST estables. Inyecta la
# autenticación según un PROVEEDOR INTERCAMBIABLE (api_key u oauth), de modo
# que las skills (onboard, invoicing) no sepan qué hay debajo. Agente-neutro:
# funciona igual bajo Claude, Codex o cualquier otro agente.
#
# Cero dependencias externas: bash + curl + coreutils. Sin jq, sin python.
#
# Uso:
#   bin/cruasan.sh GET  /api/invoices/ 'state=pending'
#   bin/cruasan.sh POST /api/invoice_batches/actions/create '{"items":[...]}'
#   bin/cruasan.sh POST /api/... @/ruta/body.json    # cuerpo desde fichero
#   ... | bin/cruasan.sh POST /api/... -             # cuerpo desde stdin
#   bin/cruasan.sh login        # (oauth) Device Authorization Grant RFC 8628
#   bin/cruasan.sh logout       # revoca el refresh (RFC 7009) y limpia tokens
#
# Para cuerpos con texto libre (nombres con apóstrofos, descripciones largas)
# usa @fichero o stdin: evita el quoting de JSON inline en el shell y no pasa
# el cuerpo por argv.
#
# Config en settings.local.sh (ver settings.local.sh.example):
#   BASE_URL, AUTH_PROVIDER=api_key|oauth, y las credenciales del proveedor.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# La credencial vive FUERA del plugin, en ruta estable: las copias del plugin
# son versionadas y cada update crea una copia nueva sin los tokens vivos (el
# refresh token rota, así que un snapshot viejo queda inválido → re-login en
# cada update). Orden de resolución:
#   1. CRUASAN_SETTINGS (override explícito: evals/tests aislados)
#   2. ~/.config/cruasan/sales.settings.sh (canónica, sobrevive a updates)
#   3. settings.local.sh del plugin (legacy) → se MIGRA a la canónica al vuelo
CANONICAL_SETTINGS="${HOME}/.config/cruasan/sales.settings.sh"
LEGACY_SETTINGS="$PLUGIN_DIR/settings.local.sh"
if [ -n "${CRUASAN_SETTINGS:-}" ]; then
  SETTINGS="$CRUASAN_SETTINGS"
elif [ -f "$CANONICAL_SETTINGS" ]; then
  SETTINGS="$CANONICAL_SETTINGS"
elif [ -f "$LEGACY_SETTINGS" ]; then
  mkdir -p "$(dirname "$CANONICAL_SETTINGS")"
  cp "$LEGACY_SETTINGS" "$CANONICAL_SETTINGS"
  SETTINGS="$CANONICAL_SETTINGS"
else
  SETTINGS="$CANONICAL_SETTINGS"
fi

# 'login' puede correr sin settings (los crea) y 'logout' sin nada que hacer;
# el resto de comandos exige credencial previa.
if [ ! -f "$SETTINGS" ] && [ "${1:-}" != "login" ] && [ "${1:-}" != "logout" ]; then
  echo "ERROR: no hay credencial en $SETTINGS. Conéctate con 'bin/cruasan.sh login' o con la skill 'onboard'." >&2
  exit 1
fi
if [ -f "$SETTINGS" ]; then
  # shellcheck disable=SC1090
  . "$SETTINGS"
fi

BASE_URL="${BASE_URL:-https://app.cruasan.com}"
AUTH_PROVIDER="${AUTH_PROVIDER:-api_key}"
CLIENT_ID="${CLIENT_ID:-oven-sales}"

# Agente que llama (cabecera X-Cruasan-Agent). El wrapper es agente-neutro:
# se puede fijar AGENT_NAME en settings.local.sh; si no, se autodetecta.
if [ -z "${AGENT_NAME:-}" ]; then
  if [ -n "${CLAUDECODE:-}" ]; then
    AGENT_NAME='claude'
  elif [ -n "${CODEX_HOME:-}" ] || [ -n "${CODEX_CI:-}" ]; then
    AGENT_NAME='codex'
  else
    AGENT_NAME='unknown'
  fi
fi

# --- Proveedores de auth -----------------------------------------------------
# Cada proveedor exporta auth_header() (cabecera Authorization/X-API-Key) y, si
# aplica, oauth_refresh(). Añadir un proveedor = añadir un case aquí.

auth_header() {
  case "$AUTH_PROVIDER" in
    api_key)
      [ -n "${API_KEY:-}" ] || { echo "ERROR: falta API_KEY en settings.local.sh" >&2; exit 1; }
      printf 'X-API-Key: %s' "$API_KEY"
      ;;
    oauth)
      [ -n "${ACCESS_TOKEN:-}" ] || { echo "ERROR: falta ACCESS_TOKEN; corre 'bin/cruasan.sh login'." >&2; exit 1; }
      printf 'Authorization: Bearer %s' "$ACCESS_TOKEN"
      ;;
    *)
      echo "ERROR: AUTH_PROVIDER desconocido: $AUTH_PROVIDER" >&2; exit 1 ;;
  esac
}

# --- Parseo JSON mínimo (sin jq) ----------------------------------------------
# Solo para las respuestas PLANAS de /oauth/*: strings sin comillas escapadas y
# enteros. `sed -n ...p` no falla sin match (imprime vacío), así que es seguro
# bajo set -e.

json_str() { # $1=json  $2=clave  → valor string (vacío si no está)
  printf '%s' "$1" | tr -d '\n\r' \
    | sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

json_num() { # $1=json  $2=clave  → entero (vacío si no está)
  printf '%s' "$1" | tr -d '\n\r' \
    | sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p'
}

# --- Persistencia segura de settings ------------------------------------------

# Reescribe (o añade) KEY='value' en settings.local.sh conservando el resto de
# claves: fichero temporal en el mismo directorio + mv atómico, permisos 600.
# NUNCA imprime el valor.
settings_put() {
  local key="$1" value="$2" tmp
  tmp="$(mktemp "${SETTINGS}.tmp.XXXXXX")"
  if [ -f "$SETTINGS" ]; then
    grep -v "^${key}=" "$SETTINGS" > "$tmp" || true
  fi
  printf "%s='%s'\n" "$key" "$value" >> "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$SETTINGS"
}

# Persiste los tokens de una respuesta 200 de /oauth/token. El refresh_token
# ROTA en cada refresh: se guarda SIEMPRE el nuevo. No imprime nada.
persist_tokens() {
  local body="$1" access refresh
  access="$(json_str "$body" access_token)"
  refresh="$(json_str "$body" refresh_token)"
  [ -n "$access" ] || return 1
  settings_put ACCESS_TOKEN "$access"
  if [ -n "$refresh" ]; then
    settings_put REFRESH_TOKEN "$refresh"
  fi
  return 0
}

open_browser() {
  if command -v open >/dev/null 2>&1; then
    open "$1" >/dev/null 2>&1 || true
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$1" >/dev/null 2>&1 || true
  elif command -v cmd.exe >/dev/null 2>&1; then
    # Windows (Git Bash/MSYS o WSL con interop): cmd start abre el navegador
    # por defecto. La coma vacía es el "title" que start exige si la URL va
    # entre comillas; los & de la query van escapados para cmd.
    cmd.exe /c start '""' "$(printf '%s' "$1" | sed 's/&/^&/g')" >/dev/null 2>&1 || true
  elif command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command "Start-Process '$1'" >/dev/null 2>&1 || true
  else
    echo "Abre esta URL en tu navegador: $1" >&2
  fi
}

# Refresca el access_token con el refresh_token (grant refresh_token, cliente
# público: SIN client_secret). Persiste ambos tokens nuevos (rotación).
# return 0 si ok / 1 si no se puede refrescar.
oauth_refresh() {
  [ "$AUTH_PROVIDER" = oauth ] || return 1
  [ -n "${REFRESH_TOKEN:-}" ] || return 1
  local resp code body
  resp="$(curl -sS -w '\n%{http_code}' -X POST \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=refresh_token' \
    --data-urlencode "refresh_token=${REFRESH_TOKEN}" \
    --data-urlencode "client_id=${CLIENT_ID}" \
    "${BASE_URL}/oauth/token")" || return 1
  code="$(printf '%s' "$resp" | tail -n1)"
  body="$(printf '%s' "$resp" | sed '$d')"
  [ "$code" = 200 ] || return 1
  persist_tokens "$body"
}

# Flujo de login OAuth: Device Authorization Grant (RFC 8628).
# Pide un device_code, muestra el user_code, abre el navegador para aprobar y
# hace polling al token endpoint hasta recibir (y persistir) los tokens.
oauth_login() {
  # Primer uso sin settings: créalo desde cero (login no exige credencial previa).
  if [ ! -f "$SETTINGS" ]; then
    mkdir -p "$(dirname "$SETTINGS")"
    ( umask 077
      cat > "$SETTINGS" <<EOF
# settings.local.sh — credencial local (generado por 'bin/cruasan.sh login').
# NUNCA se commitea (está en .gitignore). No lo compartas ni lo imprimas.
BASE_URL='${BASE_URL}'
AUTH_PROVIDER='oauth'
CLIENT_ID='${CLIENT_ID}'
EOF
    )
  fi

  echo "Solicitando autorización de dispositivo a ${BASE_URL}..." >&2
  local resp code body
  resp="$(curl -sS -w '\n%{http_code}' -X POST \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode "client_id=${CLIENT_ID}" \
    --data-urlencode 'scope=read write' \
    "${BASE_URL}/oauth/device_authorization")"
  code="$(printf '%s' "$resp" | tail -n1)"
  body="$(printf '%s' "$resp" | sed '$d')"
  [ "$code" = 200 ] || { echo "ERROR: /oauth/device_authorization devolvió HTTP $code" >&2; exit 1; }

  local device_code user_code verify_uri interval expires_in
  device_code="$(json_str "$body" device_code)"
  user_code="$(json_str "$body" user_code)"
  verify_uri="$(json_str "$body" verification_uri_complete)"
  [ -n "$verify_uri" ] || verify_uri="$(json_str "$body" verification_uri)"
  interval="$(json_num "$body" interval)"; interval="${interval:-5}"
  expires_in="$(json_num "$body" expires_in)"; expires_in="${expires_in:-600}"
  if [ -z "$device_code" ] || [ -z "$user_code" ] || [ -z "$verify_uri" ]; then
    echo "ERROR: respuesta inesperada de /oauth/device_authorization." >&2
    exit 1
  fi

  {
    echo ""
    echo "  Código de verificación:  ${user_code}"
    echo "  Comprueba que coincide con el del navegador y aprueba el acceso."
    echo "  Si el navegador no se abre solo, entra en:"
    echo "    ${verify_uri}"
    echo ""
  } >&2
  open_browser "$verify_uri"

  echo "Esperando la aprobación (caduca en ${expires_in}s)..." >&2
  local waited=0 err
  while [ "$waited" -lt "$expires_in" ]; do
    sleep "$interval"
    waited=$((waited + interval))
    resp="$(curl -sS -w '\n%{http_code}' -X POST \
      -H 'Content-Type: application/x-www-form-urlencoded' \
      --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:device_code' \
      --data-urlencode "device_code=${device_code}" \
      --data-urlencode "client_id=${CLIENT_ID}" \
      "${BASE_URL}/oauth/token")"
    code="$(printf '%s' "$resp" | tail -n1)"
    body="$(printf '%s' "$resp" | sed '$d')"

    if [ "$code" = 200 ]; then
      persist_tokens "$body" || { echo "ERROR: /oauth/token no devolvió access_token." >&2; exit 1; }
      settings_put AUTH_PROVIDER oauth
      settings_put CLIENT_ID "$CLIENT_ID"
      echo "Conectado. Tokens guardados en settings.local.sh (no se muestran)." >&2
      exit 0
    fi

    err="$(json_str "$body" error)"
    case "$err" in
      authorization_pending) ;;                          # aún sin aprobar: seguir
      slow_down)             interval=$((interval + 5)) ;;
      access_denied)         echo "ERROR: acceso denegado por el usuario." >&2; exit 1 ;;
      expired_token)         echo "ERROR: el código expiró sin aprobarse. Relanza 'bin/cruasan.sh login'." >&2; exit 1 ;;
      *)                     echo "ERROR: respuesta inesperada de /oauth/token (HTTP $code${err:+, error=$err})." >&2; exit 1 ;;
    esac
  done
  echo "ERROR: tiempo agotado (${expires_in}s) sin aprobación. Relanza 'bin/cruasan.sh login'." >&2
  exit 1
}

# Desconecta al cliente. Con oauth: revoca el refresh_token en el servidor
# (RFC 7009, cliente público sin secreto; el servidor responde 200 siempre,
# no filtra si el token existía) y blanquea SIEMPRE los tokens locales, aunque
# la revocación falle (best effort). Con api_key: solo informa (la key se
# borra desde la app). No imprime jamás los tokens.
do_logout() {
  if [ ! -f "$SETTINGS" ]; then
    echo "No hay settings.local.sh: nada que desconectar." >&2
    exit 0
  fi
  case "$AUTH_PROVIDER" in
    oauth)
      if [ -n "${REFRESH_TOKEN:-}" ]; then
        curl -sS -o /dev/null -X POST \
          -H 'Content-Type: application/x-www-form-urlencoded' \
          --data-urlencode "token=${REFRESH_TOKEN}" \
          --data-urlencode 'token_type_hint=refresh_token' \
          --data-urlencode "client_id=${CLIENT_ID}" \
          "${BASE_URL}/oauth/revoke" || true
      fi
      settings_put ACCESS_TOKEN ''
      settings_put REFRESH_TOKEN ''
      echo "Desconectado. Para volver a conectar: bin/cruasan.sh login" >&2
      ;;
    api_key)
      {
        echo "Estás conectado con API key; el wrapper no puede eliminarla del servidor."
        echo "Bórrala en app.cruasan.com → Settings → Developer → API Keys."
        echo "Si además quieres limpiar la copia local, vacía API_KEY en settings.local.sh."
      } >&2
      ;;
    *)
      echo "ERROR: AUTH_PROVIDER desconocido: $AUTH_PROVIDER" >&2; exit 1 ;;
  esac
  exit 0
}

# --- Comandos ----------------------------------------------------------------
if [ "${1:-}" = "login" ]; then
  oauth_login
fi
if [ "${1:-}" = "logout" ]; then
  do_logout
fi

METHOD="${1:?Uso: cruasan.sh <GET|POST> <ruta> [query|body|@fichero|-]}"
PATH_="${2:?falta la ruta, p.ej. /api/invoices/}"
DATA="${3:-}"

# Cuerpo desde stdin (-) o fichero (@ruta). Se materializa AQUÍ y no con el
# @fichero nativo de curl: el retry tras refrescar el token en un 401 tiene
# que poder reenviar el mismo cuerpo (stdin solo se puede leer una vez).
if [ "$DATA" = "-" ]; then
  DATA="$(cat)"
elif [ "${DATA#@}" != "$DATA" ]; then
  BODY_FILE="${DATA#@}"
  [ -f "$BODY_FILE" ] || { echo "ERROR: no existe el fichero de cuerpo: $BODY_FILE" >&2; exit 1; }
  DATA="$(cat "$BODY_FILE")"
fi

do_request() {
  local hdr; hdr="$(auth_header)"
  if [ "$METHOD" = GET ]; then
    # Query como pares k=v separados por & — cada valor se URL-encodea (curl
    # --get + --data-urlencode): espacios, ñ, etc. no rompen la URL.
    local query_args=()
    if [ -n "$DATA" ]; then
      local pairs pair
      IFS='&' read -r -a pairs <<< "$DATA"
      for pair in "${pairs[@]}"; do
        query_args+=(--data-urlencode "$pair")
      done
    fi
    # ${arr[@]+...}: expansión segura de array vacío bajo set -u en bash 3.2 (macOS)
    curl -sS -w '\n%{http_code}' --get ${query_args[@]+"${query_args[@]}"} -H "$hdr" \
      -H 'X-Cruasan-Actor-Type: ai_agent' -H "X-Cruasan-Agent: ${AGENT_NAME}" \
      "${BASE_URL}${PATH_}"
  else
    curl -sS -w '\n%{http_code}' -X "$METHOD" -H "$hdr" \
      -H 'Content-Type: application/json' \
      -H 'X-Cruasan-Actor-Type: ai_agent' -H "X-Cruasan-Agent: ${AGENT_NAME}" \
      --data "${DATA:-"{}"}" "${BASE_URL}${PATH_}"
  fi
}

RESP="$(do_request)"; CODE="$(printf '%s' "$RESP" | tail -n1)"; BODY="$(printf '%s' "$RESP" | sed '$d')"

# 401 → intenta refrescar token (solo oauth) y reintenta una vez.
if [ "$CODE" = 401 ] && oauth_refresh; then
  . "$SETTINGS"
  RESP="$(do_request)"; CODE="$(printf '%s' "$RESP" | tail -n1)"; BODY="$(printf '%s' "$RESP" | sed '$d')"
fi

printf '%s\n' "$BODY"
case "$CODE" in
  2*) exit 0 ;;
  401) echo "ERROR 401: credencial inválida o caducada. Reconéctate con 'bin/cruasan.sh login' (oauth) o la skill 'onboard'." >&2; exit 1 ;;
  403) echo "ERROR 403: la credencial no tiene permiso para esta operación (¿falta sales.emit?)." >&2; exit 1 ;;
  *)   echo "ERROR HTTP $CODE" >&2; exit 1 ;;
esac
