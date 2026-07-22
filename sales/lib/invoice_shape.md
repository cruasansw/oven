# Shape de la factura (item del lote) — referencia canónica

El payload de cada item (`items[].input`) usa el shape del API público de facturas.
**No inventes campos ni códigos**: lo que no esté aquí, pregúntalo o consúltalo por API.

## Ejemplo canónico (venta estándar)

```json
{
  "_ref": "acme-julio-1",
  "input": {
    "customer": { "tax_id": "B12345678", "company_name": "Acme SL" },
    "issue_date": "2026-07-15",
    "lines": [
      {
        "description": "Consultoría julio",
        "units": 10,
        "unit_price": 65,
        "item_type": "service",
        "taxes": [{ "system_code": "esp_vat_21" }]
      }
    ],
    "payment_means": "wire_transfer",
    "notes": "Pedido #4711"
  }
}
```

## Campos que importan

| Campo | Regla |
|---|---|
| `_ref` | Ponlo TÚ, legible y estable (`"acme-julio-1"`). Nunca recicles un `_ref` ya materializado (el sistema lo veta). |
| `customer` | Basta UN identificador: `tax_id` (preferido), `system_id` o `id`. El servidor lo matchea contra la BD — `resolution.customer` te dice si existe o se creará. Añade `company_name` (o `first_name`/`last_name` si es persona) cuando sea nuevo: VeriFactu exige nombre. **OJO con `system_id`**: es el id interno de 24 caracteres hex que devuelve la búsqueda de clientes — NUNCA pongas ahí un NIF (eso es `tax_id`); uno inválido → issue `INVALID_SYSTEM_ID`. |
| `customer.country` | País del cliente (ISO alpha-3, `"ESP"`; acepta alpha-2 o nombre). **En un cliente NUEVO con motor de impuestos es imprescindible**: sin él el motor no puede determinar el IVA (issue `engine_unavailable: buyer_country_missing`). Pídeselo al usuario al recoger los datos del cliente nuevo — los existentes ya lo tienen en su ficha. |
| `customer.full_address` | Dirección postal en una línea (calle, número, CP, ciudad). **Opcional**: pídela al dar de alta un cliente nuevo pero SIN bloquear — si el usuario no la tiene, sigue sin ella. |
| `series_code` | **Opcional** — sin él se usa la serie por defecto (`resolution.series` te dice cuál). Si hay varias y el cliente quiere otra: `GET /api/series/`. |
| `issue_date` | `YYYY-MM-DD`. Sin ella, hoy. |
| `lines[].taxes` | SIEMPRE `{ "system_code": "..." }` — el campo se llama **system_code**, no `code`. Códigos válidos: `GET /api/invoices/actions/list_taxes` (chuleta abajo). Si lo omites y la empresa tiene motor de impuestos, lo determina el motor. |
| `lines[].item_type` | `service` (default) o `product` — la NATURALEZA de lo vendido; cambia el tratamiento fiscal (p. ej. intracomunitario). NO es el tipo de línea. |
| `lines[].type` | Tipo de LÍNEA: `general` (default), `disbursement` (**suplido** — gasto pagado por cuenta del cliente, sin IVA: notaría, tasas…) o `text` (línea informativa sin importe). Para un suplido: `{"type": "disbursement", "description": "...", "units": 1, "unit_price": N}` — sin `taxes` ni `item_type`. |
| `lines[].sku` | **Solo si el catálogo está activo** (`sales_context` → `catalog.active`). Referencia un producto del catálogo: el servidor autorrellena descripción, precio de tarifa, tipo, unidad y clasificación contable. **Lo que TÚ mandes gana** (manda `unit_price` solo si el cliente dijo un importe distinto de la tarifa; los `taxes` del cliente también ganan). El sku sale de la búsqueda (`POST /api/products/actions/search_for_copilot`) — **nunca lo inventes**. Sku desconocido → issue `PRODUCT_NOT_FOUND`. |
| `lines[].discount_percent` / `discount_amount` | Descuento por línea. También hay `discount_percent`/`discount_amount` a nivel factura. |
| `discount_percent` / `discount_amount` (nivel factura) | Descuento GENERAL sobre toda la factura (0-100 el percent). Independiente de los descuentos por línea. |
| `purchase_order` | Referencia de la orden de pedido del cliente (string libre, sale en la factura). |
| `invoice_period` | Período que cubre la factura: `{"start_date": "YYYY-MM-DD", "end_date": "YYYY-MM-DD"}`. También hay `period` POR LÍNEA con el mismo shape. |
| `tags` | Etiquetas de la factura: array de strings (`["proyecto-x"]`). Útiles para filtrar y agrupar. |
| `invoice_number` | NO lo mandes en ventas normales: lo asigna la emisión. |
| `totals` | Solo de SALIDA — lo calcula el servidor; nunca lo mandes. |

A nivel de lote: `external_ref` (clave de idempotencia TUYA en `create`: si repites el create con la misma, no se duplica el lote) y `name` descriptivo.

## Rectificativas (corregir una factura YA emitida)

Una rectificativa es una factura NUEVA (con su propia serie de rectificativas — el servidor
la elige solo) que corrige una emitida. No confundir con **anular** (eso es `bulk_cancel`)
ni con editar un borrador `pending` (eso es editar, no rectificar).

Campos sobre el shape normal del item:

| Campo | Regla |
|---|---|
| `subtype` | `"corrective"` — obligatorio. |
| `corrected_invoices` | `[{"invoice_number": "F-2026-00123"}]` — la(s) factura(s) EMITIDA(s) que corrige. El staging la resuelve contra la BD y te devuelve `resolution.corrected` (nº, fecha, total y cliente de la original): **enséñaselo al usuario antes de materializar**. Número inexistente → issue `CORRECTED_INVOICE_NOT_FOUND`; borrador → `CORRECTED_INVOICE_NOT_EMITTED` (un borrador se edita o se descarta, no se rectifica); de otro cliente → `CORRECTED_INVOICE_CUSTOMER_MISMATCH` (debe ser el MISMO destinatario). |
| `corrective_type` | Obligatorio: `"substitution"` (la nueva REEMPLAZA entera a la original → `lines` = el contenido completo ya corregido) o `"differences"` (`lines` = SOLO el delta, con importes negativos si corrige a la baja). Para "me equivoqué en el importe/concepto", lo natural es substitution. |
| `corrective_reason` | Obligatorio: motivo en texto, sale en la factura. |
| `corrective_code` | Código AEAT del motivo: `R1` error fundado en derecho (importe/datos incorrectos — el caso típico), `R2` concurso de acreedores, `R3` crédito incobrable, `R4` resto de motivos, `R5` solo facturas simplificadas. Si dudas entre R1 y R4, pregunta el motivo; sin código el servidor asume `R4`. |
| `lines[].taxes` (en rectificativas) | **Calca los impuestos de la ORIGINAL línea a línea** (mismos `system_code`; y los mismos `sku` si los llevaba): la rectificativa espeja el régimen fiscal de la operación original, NO se re-determina con el contexto de hoy. Única excepción: si el motivo de la rectificación ES un IVA mal aplicado — entonces pon el correcto y dilo en `corrective_reason`. |

El cliente (`customer`) de la rectificativa: el mismo que la original.

## Chuleta de impuestos frecuentes (`system_code`)

- **IVA general**: `esp_vat_21` (21%), `esp_vat_10` (10%), `esp_vat_4` (4%), `esp_vat_0` (0%)
- **Con recargo de equivalencia**: `esp_vat_21_req`, `esp_vat_10_req`, `esp_vat_4_req`
- **Exenciones / 0%**: `esp_vat_exenta` (exenta op. interior), `esp_vat_isp` (inversión sujeto pasivo), `esp_vat_export` (exportación), `esp_vat_goods_intra` / `esp_vat_services_intra` (intracomunitario bienes/servicios), `esp_vat_nosujeta`
- **Canarias / Ceuta y Melilla**: `esp_igic_7` (IGIC general), `esp_ipsi_10`…
- **Retenciones IRPF** (se añaden como otro elemento en `taxes`): `esp_withholding_15` (15%), `esp_withholding_7` (7% inicio actividad), `esp_withholding_19` (19% alquileres)

Ejemplo profesional con retención: `"taxes": [{ "system_code": "esp_vat_21" }, { "system_code": "esp_withholding_15" }]`.
La lista completa y vigente: `GET /api/invoices/actions/list_taxes`.

## Lo que te devuelve el servidor (y DEBES usar)

Cada `create`/`update` devuelve por item un resumen compilado:

```json
{
  "_ref": "acme-julio-1",
  "status": "ready",              // invalid | incomplete | ready
  "emit_ready": true,             // ¿pasaría la emisión YA?
  "form_issues": [],              // input malformado → corrige el input
  "materialize_issues": [],       // qué falta para materializar (con path exacto)
  "emit_issues": [],              // qué faltará para EMITIR (p. ej. IVA por línea, nombre del cliente)
  "resolution": {
    "customer": { "matched": "existing", "display_name": "Acme SL" },  // existing | new | unresolved
    "series": { "code": "F-[YYYY]-[0]", "source": "default" },
    "totals": { "total_net_amount": 650, "total_amount": 786.5 },
    "catalog_suggestions": [                        // solo si una línea SIN sku parece del catálogo
      { "line": 0, "description": "Pañales", "candidates": [{ "sku": "PAN-T3", "name": "Pañales talla 3", "price_amount": 12.5 }] }
    ]
  }
}
```

Doctrina: **`validation` es tu checklist, `resolution` es tu confirmación.** Enseña al
cliente el nombre matcheado y los totales de `resolution` ANTES de materializar; resuelve
los issues preguntando, no adivinando; y no propongas emitir hasta `emit_ready: true`.
Si viene `catalog_suggestions`, una línea de texto libre parece corresponder a productos
del catálogo: **propón esos productos al usuario** (con su tarifa) antes de seguir — si
acepta, corrige la línea poniendo el `sku`; si no, la línea libre se queda como está.
