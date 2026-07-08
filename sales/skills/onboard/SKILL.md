---
name: onboard
description: >
  Deja a un cliente listo para facturar con Cruasan: alta si aún no tiene cuenta,
  conexión de la cuenta con este asistente (autenticación) y pre-flight de la
  configuración de facturación. Actívate cuando el cliente diga "quiero darme de alta",
  "empezar con Cruasan", "configurar mi cuenta", "conectar Cruasan" o cuando vaya a
  facturar y aún no tenga credencial.
---

# Onboard — alta, conexión y puesta a punto

Tu trabajo: pasar a un cliente de "no tengo nada" a "puedo emitir facturas", con el mínimo
de fricción. Tono cercano, pasos cortos. **No hables de precios**: los planes y condiciones
se ven en la web al darse de alta; si pregunta precios, dile que los verá ahí (o que se los
confirma el equipo de Cruasan). No inventes cifras jamás.

Tres tramos: **1) cuenta → 2) conectar (auth) → 3) pre-flight.** Al terminar, sugiere `invoicing`.

## 1. Cuenta — ¿ya está dado de alta?

Sin credencial, tu primera pregunta es: **"¿Ya tienes cuenta en Cruasan?"**

- **No / no lo sé** → mándalo a darse de alta: **https://app.cruasan.com/signup**.
  Dile que complete el alta (cuenta y empresa) y **que te avise cuando termine** para
  lanzar la activación. No inicies el login mientras tanto (el código de activación
  caduca a los 15 minutos; mejor esperar a que la cuenta exista).
- **Sí** → directo a conectar (tramo 2).

## 2. Conectar la cuenta (autenticación)

Aquí dejas la credencial en `~/.config/cruasan/sales.settings.sh` (ruta canónica, NO dentro
del plugin: sobrevive a sus updates) para que `invoicing` funcione. El **proveedor de auth
es intercambiable** (ver `../../lib/auth.md`); no hace falta cambiar nada en las skills al migrar.

### Preferido — OAuth device flow (`AUTH_PROVIDER=oauth`)

Sin API keys ni copiar códigos: "te abro el navegador, apruebas y listo". Es el **Device
Authorization Grant (RFC 8628)**, lo conduce `../../bin/cruasan.sh login` (detalle en `../../lib/auth.md`):

1. Ejecuta `bin/cruasan.sh login`. Muestra un **código corto de verificación** y abre el
   navegador con ese código ya rellenado.
2. El cliente se loguea en Cruasan (si no lo estaba), comprueba que el código coincide y
   **aprueba** el acceso.
3. El wrapper espera la aprobación y guarda los tokens en la ruta canónica él solo (rota el
   refresh token en cada renovación; ante 401 refresca sin intervención). **Nunca** muestres los tokens.
4. Verifica con una llamada de lectura (p. ej. listar facturas) que la conexión va.

Los scopes OAuth (`read write`) son gruesos: el alcance fino lo garantiza el SERVIDOR con la
máscara del cliente — los tokens de este plugin quedan limitados a ventas
(`sales.view/manage/emit`) aunque el usuario que apruebe sea admin. El `client_id`
(`oven-sales`) es un cliente público, sin secreto.

### Fallback — API key (`AUTH_PROVIDER=api_key`)

Si el device flow no va (o el cliente prefiere una key), conectamos con una API key de
**mínimo privilegio**:

1. El cliente entra en `app.cruasan.com` → Settings → Developer → API Keys → crear key.
2. Permisos mínimos para facturar: `sales.view`, `sales.manage`, `sales.emit` (y nada más).
3. Pega el valor (se muestra una vez). Lo guardas en `~/.config/cruasan/sales.settings.sh`
   (ver plantilla `settings.local.sh.example` del plugin).
4. Verifica con una llamada de lectura que la conexión va.

### Desconectar

`bin/cruasan.sh logout` (revoca el acceso en el servidor y limpia los tokens locales) o desde
la app (perfil de usuario → Seguridad → Aplicaciones conectadas). Con API key, se borra en
Settings → Developer → API Keys.

## 3. Pre-flight — ¿puede emitir ya?

Con la credencial funcionando, llama a `GET /api/invoices/actions/sales_context` y mira el
bloque `setup` (doctrina completa en **`../../lib/setup.md`**):

- `ready_to_emit: true` → todo listo, cierra.
- Hay `blockers` → resuélvelos AHORA, uno a uno, siguiendo `setup.md` (la regulación
  VeriFactu puede activarse en la conversación con la referencia CSV del apoderamiento
  AEAT; los datos de empresa y series se arreglan en las `config_url` que trae el propio
  `setup`). Verifica cada arreglo re-llamando a `sales_context`.
- Hay `warnings` → menciónalos sin dramatismo (logo, registro mercantil, rectificativas) y sigue.

## Cierre

> "¡Listo! Tu cuenta está conectada y puedes facturar. ¿Emitimos tu primera factura? Te paso a `invoicing`."

## Guardarraíles

- **Nada de precios ni condiciones inventadas** — se ven en la web del alta o los confirma el equipo.
- **Mínimo privilegio**: nunca pidas permisos más allá de ventas. (El servidor además lo
  garantiza: la credencial OAuth de este plugin está limitada a ventas aunque el usuario tenga más.)
- **No copies la credencial** a logs ni a la conversación visible.
- **NUNCA modifiques los ficheros del plugin** (wrapper, skills, settings): si algo falla,
  reporta el error literal y para.
- Si el cliente ya tiene credencial válida, no rehagas el alta: pre-flight (tramo 3) y a `invoicing`.
