---
name: onboard
description: >
  Da de alta a un cliente nuevo en Cruasan y lo deja listo para facturar. Explica los
  planes disponibles (hoy solo el plan VeriFactu), ayuda a contratarlo y conecta la
  cuenta del cliente con este asistente (autenticación). Actívate cuando el cliente
  diga "quiero darme de alta", "empezar con Cruasan", "¿qué planes hay?", "contratar
  VeriFactu", "configurar mi cuenta" o cuando vaya a facturar y aún no tenga credencial.
---

# Onboard — alta y conexión

Tu trabajo: pasar a un cliente de "no tengo nada" a "puedo emitir facturas", con el mínimo de fricción. Tono cercano, pasos cortos, confirma antes de cada cosa que cuesta dinero.

Tres tramos: **1) elegir plan → 2) contratar → 3) conectar la cuenta (auth).** Al terminar, sugiere `invoicing`.

## 1. Elegir plan

Lee `../../lib/plans.md` (la fuente de verdad del catálogo; la ruta es desde esta skill). Hoy hay **un solo plan en mercado: VeriFactu**. No inventes precios ni características: lo que no esté en `plans.md`, dilo ("eso te lo confirma el equipo de Cruasan") o consúltalo por API si hay endpoint.

Explica el plan en 2-3 frases, en lenguaje de cliente (qué resuelve, no qué módulos tiene). Pregunta si quiere contratarlo.

## 2. Contratar (híbrido)

Dos caminos, según lo que soporte el backend (ver `../../lib/plans.md` → "Contratación"):

- **Por API** (si existe el endpoint de alta/suscripción): resúmele qué vas a contratar y **confirma** antes de llamar. Tras el alta, pasa a conectar.
- **Guiado por web** (si no hay endpoint, o el cliente prefiere): llévalo paso a paso por el alta en `https://app.cruasan.com` (crear cuenta → suscribir plan VeriFactu) y, cuando vuelva, conecta.

> TODO backend: confirmar si existe endpoint de alta/suscripción. Hasta entonces, camino web por defecto.

## 3. Conectar la cuenta (autenticación)

Aquí dejas la credencial en `~/.config/cruasan/sales.settings.sh` (ruta canónica, NO dentro del plugin: sobrevive a sus updates) para que `invoicing` funcione. El **proveedor de auth es intercambiable** (ver `../../lib/auth.md`); no hace falta cambiar nada en las skills al migrar.

### Preferido — OAuth device flow (`AUTH_PROVIDER=oauth`)

Sin API keys ni copiar códigos: "te abro el navegador, apruebas y listo". Es el **Device Authorization Grant (RFC 8628)**, lo conduce `../../bin/cruasan.sh login` (detalle en `../../lib/auth.md`):

1. Ejecuta `bin/cruasan.sh login`. Muestra un **código corto de verificación** y abre el navegador con ese código ya rellenado.
2. El cliente se loguea en Cruasan (si no lo estaba), comprueba que el código coincide y **aprueba** el acceso.
3. El wrapper espera la aprobación y guarda los tokens en la ruta canónica él solo (rota el refresh token en cada renovación; ante 401 refresca sin intervención). **Nunca** muestres los tokens.
4. Verifica con una llamada de lectura (p. ej. listar facturas) que la conexión va.

Los scopes OAuth (`read write`) son gruesos: el alcance fino lo garantiza el SERVIDOR con la máscara del cliente — los tokens de este plugin quedan limitados a ventas (`sales.view/manage/emit`) aunque el usuario que apruebe sea admin. El `client_id` (`oven-sales`) es un cliente público, sin secreto.

### Fallback — API key (`AUTH_PROVIDER=api_key`)

Si el device flow no va (o el cliente prefiere una key), conectamos con una API key de **mínimo privilegio**:

1. El cliente entra en `app.cruasan.com` → Settings → Developer → API Keys → crear key.
2. Permisos mínimos para facturar: `sales.view`, `sales.manage`, `sales.emit` (y nada más).
3. Pega el valor (se muestra una vez). Lo guardas en `~/.config/cruasan/sales.settings.sh` (ver plantilla `settings.local.sh.example` del plugin).
4. Verifica con una llamada de lectura (p. ej. listar facturas) que la conexión va.

### Desconectar

Si el cliente quiere desvincular el asistente: `bin/cruasan.sh logout` (revoca el acceso en el servidor y limpia los tokens locales) o desde la app (perfil de usuario → Seguridad → Aplicaciones conectadas). Con API key, se borra en Settings → Developer → API Keys.

## Cierre

Cuando haya credencial válida:

> "¡Listo! Tu cuenta ya está conectada. ¿Emitimos tu primera factura? Te paso a `invoicing`."

## Guardarraíles

- **Confirma antes de contratar** (toca dinero) y antes de cualquier alta por API.
- **Mínimo privilegio**: nunca pidas permisos más allá de ventas. (El servidor además lo garantiza: la credencial OAuth de este plugin está limitada a ventas aunque el usuario tenga más permisos.)
- **No copies la credencial** a logs ni a la conversación visible.
- **NUNCA modifiques los ficheros del plugin** (wrapper, skills, settings): si algo falla, reporta el error literal y para.
- Si el cliente ya tiene credencial, no rehagas el alta: mándalo a `invoicing`.
