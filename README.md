# The Oven 🥐 — plugins de Cruasan para asistentes IA

Plugins oficiales de [Cruasan](https://app.cruasan.com) para trabajar desde tu asistente
de IA (Claude Code y compatibles). Tu asistente conversa; Cruasan factura.

## Plugin `sales` — Ventas

Emite y gestiona **facturas VeriFactu** desde la conversación: borradores, revisión,
emisión con registro fiscal, remesas de varias facturas, catálogo de productos,
consultas y anulaciones. Solo endpoints estables y mínimo privilegio: la credencial
del plugin únicamente puede operar sobre tus ventas.

### Instalar (Claude Code)

```bash
claude plugin marketplace add cruasansw/oven
claude plugin install sales@cruasan-oven
```

### Conectar tu cuenta

Abre una conversación y dile a tu asistente que quieres conectar Cruasan — el propio
plugin te guía (login por navegador, sin copiar claves). Tu credencial queda en
`~/.config/cruasan/sales.settings.sh`, fuera del plugin: sobrevive a las actualizaciones.

### Actualizar

```bash
claude plugin update sales
```

### Desconectar

Dile "desconecta Cruasan" a tu asistente, o desde la app: perfil → Seguridad →
Aplicaciones conectadas.

---

© Cruasan Software. El contenido de este repositorio se distribuye para su uso con
los servicios de Cruasan.
