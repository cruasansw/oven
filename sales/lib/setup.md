# Pre-flight de facturación (`sales_context` → `setup`)

`GET /api/invoices/actions/sales_context` devuelve un bloque `setup` que dice si la empresa
puede emitir YA (`ready_to_emit`) y, si no, qué falta. Doctrina: **blockers se resuelven
ANTES de facturar; warnings se avisan UNA vez y no bloquean.** Las URLs de arreglo vienen
en el propio `setup` (`config_url` por área, ya llevan instance/company): compártelas TAL
CUAL, nunca construyas URLs a mano.

Tu credencial es SOLO de ventas: los datos de empresa, series y registro mercantil **no se
pueden editar por API desde aquí** — se arreglan en la web (por eso las config_url).
La única excepción automatizable es la activación de la regulación por referencia CSV (abajo).

## Blockers (sin esto la emisión falla o no es legal)

| Código | Qué pasa | Qué hacer |
|---|---|---|
| `regulation_pending` | La empresa requiere VeriFactu y no está activo | Receta de activación (abajo) |
| `company_name_missing` | Falta razón social (o nombre y apellidos) | Manda a `company_data.config_url` |
| `company_tax_id_missing` | Falta el NIF/CIF de la empresa | Manda a `company_data.config_url` |
| `company_address_missing` | Falta la dirección fiscal (calle y ciudad) | Manda a `company_data.config_url` |
| `no_invoice_series` | No hay ninguna serie de facturas ordinarias | Manda a `series_setup.config_url` a crear una |

Tras cada arreglo que el cliente diga haber hecho, **vuelve a llamar a `sales_context`** y
verifica que el blocker desapareció — nunca lo des por resuelto de palabra.

## Warnings (avisar, no bloquear)

| Código | Qué decirle al cliente |
|---|---|
| `no_logo` | Las facturas saldrán sin su logo. Se sube en `company_data.config_url` |
| `mercantile_registry_missing` | Los datos de inscripción en el registro mercantil no aparecerán en la factura. Se rellenan en `mercantile_registry.config_url` |
| `no_corrective_series` | No hay serie de rectificativas: el día que necesite rectificar una factura tendrá que crearla en `series_setup.config_url` |

Avísalo con naturalidad al preparar la primera factura de la sesión y no insistas más.

## Receta: activar la regulación (VeriFactu) en conversación

`setup.regulation` trae `state` y, si hay una solicitud en curso, `activation`
(`method`, `state`, `review_notes`). Explica al cliente las **dos vías**:

1. **Apoderamiento AEAT** (recomendada, se puede completar AQUÍ): el cliente da de alta un
   apoderamiento a favor de Cruasan en la sede de la AEAT y te trae la **referencia CSV**
   del justificante. Con ella:
   `POST /api/invoices/actions/activate_regulation` `{"csv_reference": "..."}`
   → el servidor la coteja contra la AEAT: si verifica, **activación inmediata**; si no es
   concluyente, queda `pending_review` (la revisa el equipo de Cruasan — dile que le
   avisarán, no es un error).
2. **Firma de declaración (PDF)**: se genera, firma y sube en la web —
   manda a `setup.regulation.config_url`.

Si `activation.state` ya es `pending_review`: no reintentes ni dupliques — di que está en
revisión por el equipo (y si hay `review_notes`, transmítelas).

Después de una activación con éxito, confirma con `sales_context` (el blocker
`regulation_pending` debe haber desaparecido) antes de seguir facturando.
