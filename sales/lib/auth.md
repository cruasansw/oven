# Auth — proveedor intercambiable

El wrapper `bin/cruasan.sh` se autentica contra `app.cruasan.com` mediante un **proveedor de auth intercambiable**, fijado por `AUTH_PROVIDER` en `settings.local.sh`. Las skills (`onboard`, `invoicing`) **no saben** qué proveedor hay debajo: solo llaman al wrapper.

| `AUTH_PROVIDER` | Cabecera | Estado |
|---|---|---|
| `oauth` | `Authorization: Bearer <ACCESS_TOKEN>` | ✅ operativo (device flow RFC 8628) — preferido |
| `api_key` | `X-API-Key: <API_KEY>` | ✅ operativo — fallback |

Cambiar de proveedor = cambiar `AUTH_PROVIDER` y sus credenciales en `settings.local.sh`. Cero cambios en las skills.

## Cero dependencias

`bin/cruasan.sh` usa solo `bash` + `curl` + coreutils (`sed`, `grep`, `tr`, `tail`, `printf`, `mktemp`). Sin `jq`, sin `python`, sin `node`. Funciona en macOS, Linux, WSL y Windows con Git Bash (el shell que usan los agentes en Windows) sin instalar nada. La clave: el script corre en el shell DEL AGENTE, no del usuario — y tanto Claude Code como Codex aportan un entorno bash en todas las plataformas. Windows nativo sin ningún bash (solo PowerShell) queda fuera.

## Agente-neutro

El wrapper funciona igual bajo cualquier agente (Claude, Codex…). Identifica quién llama con la cabecera `X-Cruasan-Agent`: usa `AGENT_NAME` de `settings.local.sh` si está definido y, si no, autodetecta (`CLAUDECODE` → `claude`; `CODEX_HOME`/`CODEX_CI` → `codex`; si no, `unknown`). `X-Cruasan-Actor-Type: ai_agent` va siempre fijo. Nada del plugin (nombres, mensajes, flujo) depende del agente.

## Mínimo privilegio (siempre)

Oven solo factura. La credencial debe tener **solo permisos de ventas**:

- `sales.view` — listar facturas/lotes
- `sales.manage` — crear/editar borradores, materializar, anular
- `sales.emit` — **emitir** (gate dedicado; `sales.manage` no basta)

Nada de `accounting`, `crm`, `expenses`, `assistant`. Si falta `sales.emit`, el wrapper devuelve 403 al emitir y la skill lo explica sin forzar la llamada.

## Proveedor `oauth` — Device Authorization Grant (RFC 8628)

`app.cruasan.com` expone el **device flow** de OAuth 2.0: el backend publica el endpoint de `device_authorization` en el discovery (`/.well-known/oauth-authorization-server`), junto al `token_endpoint` (`/oauth/token`) y el `revocation_endpoint` (`/oauth/revoke`).

- **Cliente público**: `client_id = oven-sales`, **sin** `client_secret` (un CLI distribuido no puede guardar secretos). Ninguna llamada OAuth envía secreto. Cada plugin de Oven tiene su propio cliente OAuth con patrón `oven-<plugin>`.
- **Scopes**: `read write` (gruesos). El alcance fino lo pone el SERVIDOR con la **máscara de permisos del cliente** (`enforce_permission_mask` en el registro de `oven-sales`): los tokens de este plugin quedan limitados a `sales.view`/`sales.manage`/`sales.emit` aunque el usuario que aprobó sea admin. Cualquier endpoint fuera de ventas responde 403 — es la garantía real de mínimo privilegio, no el prompt.

### Flujo de login (`bin/cruasan.sh login`)

1. El wrapper hace `POST /oauth/device_authorization` (`client_id`, `scope`) y recibe `device_code`, `user_code`, `verification_uri` / `verification_uri_complete`, `expires_in` (600 s) e `interval` (5 s).
2. Muestra el `user_code` y **abre el navegador** en `verification_uri_complete` (`open` en macOS, `xdg-open` en Linux, `cmd.exe /c start` o `powershell Start-Process` en Windows/Git Bash/WSL; si nada funciona, imprime la URL).
3. El cliente se loguea en Cruasan, comprueba que el código coincide y **aprueba** el acceso.
4. Mientras, el wrapper hace **polling** a `POST /oauth/token` con `grant_type=urn:ietf:params:oauth:grant-type:device_code` cada `interval` segundos. Respuestas de error durante el polling (HTTP 400):
   - `authorization_pending` — aún sin aprobar: seguir esperando
   - `slow_down` — subir el intervalo **+5 s** y seguir
   - `access_denied` — el usuario denegó: abortar
   - `expired_token` — el código caducó: abortar y relanzar el login
5. Al aprobar, llega `{ access_token, token_type: Bearer, expires_in, refresh_token, scope }` y el wrapper **persiste** `ACCESS_TOKEN` + `REFRESH_TOKEN` en `settings.local.sh` (reescritura segura vía fichero temporal; los tokens **nunca** se imprimen).

### Refresh con rotación

Ante un 401, el wrapper hace `POST /oauth/token` con `grant_type=refresh_token` (`refresh_token` + `client_id`, sin secreto) y reintenta la llamada original una vez. El servidor **rota** el refresh token: la respuesta trae `access_token` **y** `refresh_token` nuevos, y el wrapper guarda **siempre** ambos (el refresh token viejo queda invalidado). Si el refresh falla, hay que relanzar `bin/cruasan.sh login`.

### Desconectar

`bin/cruasan.sh logout` revoca el `refresh_token` en el servidor (`POST /oauth/revoke`, RFC 7009, con `token` + `token_type_hint=refresh_token` + `client_id`, sin secreto; el servidor responde 200 siempre y no filtra si el token existía) y **blanquea siempre** `ACCESS_TOKEN` y `REFRESH_TOKEN` en `settings.local.sh`, aunque la revocación falle (best effort). El access token que quedara en vuelo ya no se puede refrescar y caduca solo en menos de 1 hora. El cliente también puede revocar el acceso desde la app: perfil de usuario → Seguridad → Aplicaciones conectadas.

Con `api_key`, `logout` no borra nada del servidor: la key se elimina en `app.cruasan.com` → Settings → Developer → API Keys (y, si se quiere, se vacía `API_KEY` en `settings.local.sh`).

## Proveedor `api_key` (fallback)

1. El cliente crea una API key en `app.cruasan.com` → Settings → Developer → API Keys, con los 3 permisos de ventas.
2. Se guarda en `settings.local.sh` (`AUTH_PROVIDER=api_key`, `API_KEY=...`). Ver `settings.local.sh.example`.
3. **Nunca** se commitea (está en `.gitignore`) ni se imprime en la conversación.
