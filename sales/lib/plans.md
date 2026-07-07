# Planes de Cruasan — catálogo (fuente de verdad para `onboard`)

> No inventes precios ni características. Lo que no esté aquí (ni se pueda consultar por API), dilo:
> "eso te lo confirma el equipo de Cruasan". Mantén este fichero al día cuando cambien los planes.

## Plan en mercado (hoy)

### VeriFactu

- **Qué resuelve (en lenguaje de cliente):** emitir facturas conformes a VeriFactu (el sistema de
  facturación verificable de la AEAT) sin pelearte con software fiscal. Creas la factura, la confirmas
  y Cruasan se encarga del registro VeriFactu.
- **Para quién:** autónomos y pymes que necesitan facturar cumpliendo VeriFactu.
- **Permisos que necesita la credencial:** `sales.view`, `sales.manage`, `sales.emit` (solo ventas).
- **Precio:** _por confirmar con el equipo de Cruasan_ (TODO: rellenar cuando esté cerrado).
- **Límites / condiciones:** _por confirmar_ (TODO).

## Contratación

Camino **híbrido** (lo decide `onboard`):

- **Por API** — si existe endpoint de alta/suscripción al plan. _TODO backend: confirmar endpoint._
  Hasta entonces, no asumas que existe.
- **Guiado por web** (por defecto hoy) — alta en `https://app.cruasan.com`: crear cuenta → suscribir
  plan VeriFactu. Después se conecta la credencial (ver `lib/auth.md`).

## Próximos planes

_(Aún no hay más planes en mercado. Cuando los haya, se añaden aquí y el concierge podrá ofrecerlos.)_
