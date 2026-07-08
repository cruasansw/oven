# Cruasan — qué resuelve (referencia para `onboard`)

> **Nada de precios ni condiciones**: se ven en la web al darse de alta
> (https://app.cruasan.com/signup) o los confirma el equipo de Cruasan. No inventes cifras.

## VeriFactu (el producto que este plugin acompaña)

- **Qué resuelve (en lenguaje de cliente):** emitir facturas conformes a VeriFactu (el
  sistema de facturación verificable de la AEAT) sin pelearte con software fiscal. Creas la
  factura, la confirmas y Cruasan se encarga del registro VeriFactu y del PDF.
- **Para quién:** autónomos y pymes que necesitan facturar cumpliendo VeriFactu.
- **Permisos que necesita la credencial de este plugin:** `sales.view`, `sales.manage`,
  `sales.emit` (solo ventas).

## Alta

Self-service en la web: **https://app.cruasan.com/signup** (cuenta → empresa → plan). No hay
alta por API: el asistente acompaña (manda al signup, espera el aviso del cliente y conecta
la credencial — flujo en la skill `onboard`).
