# AGENTS.md — Guía para agentes de IA

> Este archivo describe la arquitectura, convenciones y reglas del proyecto para que cualquier agente de IA pueda trabajar de forma autónoma, segura y coherente con el código existente.

---

## 1. Descripción del proyecto

**Dashboard Lab v3** es una aplicación web autocontenida (un único archivo HTML de ~1600 líneas) para gestión de muestras de laboratorio. Lee archivos Excel, calcula métricas de plazos y caducidad, y presenta 8 vistas con gráficas, tablas, alertas y análisis de equipo.

- **Archivo principal:** `dashboard_v3.html`
- **Sin backend:** toda la lógica corre en el navegador
- **Sin build step:** HTML + CSS + JS en un solo archivo
- **Dependencias (CDN):** Tailwind CSS (play), SheetJS 0.18.5, Chart.js 3.9.1

---

## 2. Estructura del repositorio

```
c:\...\CYC-WEB\v0\c\
├── dashboard_v3.html     ← ARCHIVO PRINCIPAL (versión activa)
├── dashboard_v2.html     ← Versión anterior (no tocar)
├── dashboard.html        ← Versión original (no tocar)
├── cavedish.webp         ← Logo (referenciado en el HTML)
├── README.md             ← Documentación de usuario
├── AGENTS.md             ← Este archivo
└── obsoleto\             ← Archivos archivados, ignorar
```

**Regla:** Trabajar únicamente sobre `dashboard_v3.html`. Crear versiones nuevas si el cambio es estructural grande (e.g. `dashboard_v4.html`).

---

## 3. Columnas del Excel — nombres EXACTOS

> ⚠️ CRÍTICO: Los nombres de columna son **sensibles a mayúsculas, espacios y acentos**. El código accede a ellos como `d['F. Recepción']` — un carácter incorrecto rompe silenciosamente la funcionalidad.

| Nombre exacto | Notas |
|---|---|
| `Muestra` | ID único, filtro de filas vacías |
| `F. Recepción` | Espacio después del punto, acento en "ó" |
| `Cliente` | — |
| `Matriz` | — |
| `Parametro` | **Sin acento** en la "a" |
| `Código` | Acento en "ó" |
| `F.Límite` | **Sin espacio** entre "F." y "Límite", acento en "í" |
| `Area` | **Sin acento** en la "a" |
| `Método` | Acento en "é" |
| `Persona` | — |
| `F. Caduc` | Espacio después del punto |
| `F. Max` | Espacio después del punto |
| `Min` | — |
| `Conductivid` | Abreviatura de Conductividad |
| `Estado` | Campo de texto libre del Excel |
| `Firma` | Vacío = sin firmar |
| `FinAna` | Vacío = análisis sin finalizar |
| `Intro` | Campo de notas |
| `ceco` | Centro de coste, **todo en minúscula** |

### Acceso en código

```javascript
// CORRECTO
d['F. Recepción']   // con espacio y acento
d['F.Límite']        // sin espacio, con acento
d['Método']          // con acento
d['Código']          // con acento
d.Parametro          // sin acento
d.Area               // sin acento
d.ceco               // minúscula

// INCORRECTO — NO usar
d['F.Recepcion']     // falta acento
d['Fecha Limite']    // nombre antiguo (v1)
d['F. Límite']       // tiene espacio (error)
d.Metodo             // falta acento
```

---

## 4. Campos calculados — definición y acceso

Estos campos se añaden a cada objeto fila en `procesarDatos()`. Son **solo lectura** y se recalculan cada vez que se carga el archivo.

```javascript
d.diasEspera        // Number: HOY − F. Recepción (días enteros)
d.diasPlazo         // Number: F.Límite − F. Recepción (días enteros)
d.diasParaVencer    // Number: F.Límite − HOY (puede ser negativo)
d.pctPlazo          // Number: Math.round(diasEspera / diasPlazo * 100)
d.diasParaCaducar   // Number|null: F. Caduc − HOY (null si no hay fecha)
d.estadoVencimiento // String: 'ok' | 'proximo' | 'vencido'
d.estadoCaducidad   // String: 'ok' | 'proxima' | 'caducado'
d.firmado           // Boolean: Firma !== ''
d.finAnaCompleto    // Boolean: FinAna !== ''
```

### Lógica de `estadoVencimiento`

```javascript
if (diasParaVencer < 0)      estadoVencimiento = 'vencido';
else if (diasParaVencer <= 7) estadoVencimiento = 'proximo';
else                          estadoVencimiento = 'ok';
```

### Lógica de `estadoCaducidad`

```javascript
if (diasParaCaducar < 0)       estadoCaducidad = 'caducado';
else if (diasParaCaducar <= 30) estadoCaducidad = 'proxima';
else                            estadoCaducidad = 'ok';
```

---

## 5. Arquitectura JavaScript

### Estado global

```javascript
let datosGlobales   = [];   // Datos activos (puede estar filtrado por persona)
let datosOriginales = [];   // Todos los datos cargados (nunca filtrados)
let charts          = {};   // Instancias de Chart.js activas (clave = canvasId)
let vistaActual     = 'general';
let puestoTrabajoActual = '';       // Persona seleccionada en sidebar
let tablaOrden      = { col: null, dir: 'asc' };
let quickFilterActivo   = '';       // Chip activo en Tablas
let ribbonFilterActivo  = '';       // Filtro de ribbon activo
let alertTabActivo      = 'atab-plazo';
let paginaActual        = 1;
let tablaFiltradosCache = [];       // Resultado de filtros para paginación
let filtrosListenersAttached = false;
```

### Constantes de localStorage

```javascript
const LS_RAW  = 'labDashboard_v3_raw';    // Datos crudos del Excel (JSON)
const LS_META = 'labDashboard_v3_meta';   // Metadatos (fecha, total)
// + 'lab_darkmode' para preferencia de tema
```

### Flujo de datos

```
Excel (.xlsx / .xls)
    ↓  leerExcel(arrayBuffer)          ← SheetJS: header en fila 2
    ↓  rawData (array de objetos)
    ↓  procesarDatos(rawData)          ← añade campos calculados
    ↓  datosOriginales / datosGlobales
    ↓  actualizarDashboard()           ← renderiza KPIs + gráficas + filtros
    ↓  renderVista(vistaActual)        ← renderiza la vista activa
```

### Función de lectura de Excel — detalles críticos

```javascript
function leerExcel(arrayBuffer) {
    const workbook = XLSX.read(new Uint8Array(arrayBuffer), { type: 'array' });
    const worksheet = workbook.Sheets[workbook.SheetNames[0]];

    // ⚠️ header:1 para obtener array de arrays (control manual de fila de cabecera)
    const allRows = XLSX.utils.sheet_to_json(worksheet, {
        header: 1,
        raw: false,       // convierte fechas a string con dateNF
        dateNF: 'yyyy-mm-dd',
        defval: ''
    });

    const headers  = allRows[1];      // Fila 2 (índice 1) = CABECERAS
    const dataRows = allRows.slice(2); // Fila 3+ = datos

    return dataRows
        .map(row => { /* mapea a objeto usando headers */ })
        .filter(row => row['Muestra'] && String(row['Muestra']).trim() !== '');
}
```

---

## 6. Sistema de vistas

### Registro de vistas

Las vistas están registradas en el objeto `titles` dentro de `cambiarVista()`:

```javascript
const titles = {
    general:  ['Vision General',    '...'],
    miidia:   ['Mi Dia',            '...'],
    kpi:      ['Indicadores KPI',   '...'],
    graficas: ['Graficas',          '...'],
    tablas:   ['Tablas Detalladas', '...'],
    analisis: ['Analisis Avanzado', '...'],
    alertas:  ['Alertas',          '...'],
    equipo:   ['Gestion de Equipo', '...']
};
```

### Añadir una nueva vista

1. Añadir botón en `<nav>` del sidebar con `id="nav-NOMBRE"` y `onclick="cambiarVista('NOMBRE')"`
2. Añadir `<div id="vista-NOMBRE" class="hidden space-y-6">` en `#dashboardContent`
3. Añadir entrada en el objeto `titles` en `cambiarVista()`
4. Añadir `'NOMBRE'` al array `vistas` en `cambiarVista()`
5. Añadir case en `renderVista()` llamando a la función de render
6. Implementar `actualizarNOMBRE()` con la lógica de la vista

### Añadir una nueva columna visible en la tabla principal

La tabla principal (`Tablas`) tiene un sistema de toggle de columnas:

1. Añadir `<input type="checkbox" id="col-NUEVA" ...>` en `#colToggleMenu`
2. En `aplicarFiltrosTabla()`, añadir `const showNUEVA = getColVisible('col-NUEVA')`
3. Añadir `<th data-col-toggle="col-NUEVA">` en el `<thead>`
4. Añadir celda `<td data-col-toggle="col-NUEVA">` en el template de fila
5. Añadir `'col-NUEVA'` al array `toggleCols` en `actualizarTablaPrincipal()`

---

## 7. Parser de fechas — `parseFecha()`

Función crítica. Siempre usarla para parsear cualquier columna de fecha.

```javascript
function parseFecha(val) {
    if (!val) return null;
    if (val instanceof Date && !isNaN(val)) return val;

    const s = String(val).trim();

    // 1. ISO: yyyy-mm-dd o yyyy/mm/dd
    const iso = s.match(/^(\d{4})[-\/](\d{1,2})[-\/](\d{1,2})/);
    if (iso) return new Date(+iso[1], +iso[2]-1, +iso[3]);

    // 2. Español: dd/mm/yyyy o dd-mm-yyyy
    const dmy = s.match(/^(\d{1,2})[-\/](\d{1,2})[-\/](\d{4})/);
    if (dmy) return new Date(+dmy[3], +dmy[2]-1, +dmy[1]);

    // 3. Número de serie Excel
    const serial = parseFloat(s);
    if (!isNaN(serial) && serial > 1000) {
        return new Date(Math.round((serial - 25569) * 86400 * 1000));
    }

    return null;
}
```

**Regla:** Nunca usar `new Date(val)` directamente sobre valores de Excel. Siempre usar `parseFecha()`.

---

## 8. Sistema de gráficas (Chart.js)

### Regla crítica: siempre destruir antes de recrear

```javascript
// CORRECTO
if (charts['miChart']) charts['miChart'].destroy();
charts['miChart'] = new Chart(ctx, { ... });

// INCORRECTO — causa memory leak y error de canvas
charts['miChart'] = new Chart(ctx, { ... }); // sin destruir primero
```

### Función helper `crearGrafico()`

Para gráficas simples (doughnut, pie, bar con un dataset):

```javascript
crearGrafico(canvasId, tipo, labels, data, colors);
// tipo: 'doughnut' | 'pie' | 'bar'
// colors: array de strings hsl()
```

### Paleta de colores recomendada

```javascript
const COLORS = [
    'hsl(142.1 76.2% 36.3%)',  // verde
    'hsl(222.2 47.4% 11.2%)',  // azul oscuro
    'hsl(24.6 95% 53.1%)',     // naranja
    'hsl(215.4 16.3% 46.9%)', // gris-azul
    'hsl(0 84.2% 60.2%)',     // rojo
    'hsl(280 76% 53%)',        // púrpura
    'hsl(200 76% 53%)',        // cian
    'hsl(45 93% 47%)',         // amarillo
    'hsl(340 82% 52%)',        // rosa
    'hsl(160 84% 39%)',        // verde oscuro
];
```

---

## 9. Sistema de color / diseño

### Variables CSS (tema)

El diseño usa variables CSS en `:root` (claro) y `html.dark` (oscuro). **No usar colores hardcodeados** en código nuevo — usar siempre `hsl(var(--nombre))`:

```css
hsl(var(--background))      /* fondo de página */
hsl(var(--card))            /* fondo de tarjetas */
hsl(var(--border))          /* bordes */
hsl(var(--foreground))      /* texto principal */
hsl(var(--muted-foreground)) /* texto secundario */
hsl(var(--muted))           /* fondos secundarios/hover */
hsl(var(--primary))         /* color de acento */
hsl(var(--primary-foreground)) /* texto sobre primary */
hsl(var(--destructive))     /* alertas, errores */
```

### Badges de estado

Usar siempre las funciones helper:

```javascript
estadoBadgeClass('vencido')  // → 'bg-destructive/10 text-destructive'
estadoBadgeClass('proximo')  // → 'bg-orange-100 text-orange-800'
estadoBadgeClass('ok')       // → 'bg-green-100 text-green-800'

estadoBadgeText('vencido')   // → 'Vencido'
estadoBadgeText('proximo')   // → 'Próximo'
estadoBadgeText('ok')        // → 'En plazo'
```

### Semáforo de progreso (pctPlazo)

```javascript
const color = pct > 100 ? '#ef4444' : pct > 75 ? '#f97316' : pct > 50 ? '#eab308' : '#22c55e';
// HTML: <div class="progress-wrap"><div class="progress-fill" style="width:${Math.min(pct,100)}%;background:${color}"></div></div>
```

---

## 10. Modal de detalle

El modal es un elemento DOM único (`#detailModal`) que se rellena dinámicamente.

### Apertura

```javascript
// Cada fila de tabla debe tener: onclick="abrirModal(idx)"
// donde idx = datosGlobales.indexOf(d)  o  datosGlobales.findIndex(...)
abrirModal(idx);
```

### Cierre

```javascript
cerrarModal();  // también lo hace ESC o click en el backdrop
```

### Estructura del modal

```javascript
function abrirModal(idx) {
    const d = datosGlobales[idx];  // objeto completo con campos calculados
    // rellena #modalTitle y #modalContent
    // muestra #detailModal con clase .open
}
```

---

## 11. Toast / notificaciones

```javascript
mostrarToast(mensaje, tipo);
// tipo: 'success' | 'error' | 'warning' | 'info'
// Duración: 3.5 segundos, animación slide-in/out
```

---

## 12. Reglas de codificación

### Convenciones

- **Funciones en camelCase:** `actualizarKPIs`, `aplicarFiltrosTabla`, `parseFecha`
- **IDs de elementos en camelCase o kebab:** `tablaPrincipal`, `alertBadge`, `col-progreso`
- **Variables de estado globales** declaradas al inicio del `<script>` con `let`
- **Constantes** con `const` en mayúsculas: `LS_RAW`, `LS_META`

### Patrón de render de tabla

Todas las tablas siguen el mismo patrón:

```javascript
function actualizarXxxTabla() {
    const tbody = document.getElementById('xxxBody');
    const datos = datosGlobales.filter(/* criterio */);

    tbody.innerHTML = datos.map((d, i) => `
        <tr class="border-b hover:bg-muted/50 cursor-pointer transition-colors"
            style="border-color:hsl(var(--border))"
            onclick="abrirModal(${datosGlobales.indexOf(d)})">
            <td class="p-3 text-sm">...</td>
        </tr>
    `).join('') || emptyRow(NUM_COLUMNAS);
}
```

### Patrón de actualización de gráfica

```javascript
function actualizarGraficaXxx() {
    const ctx = document.getElementById('xxxChart');
    if (!ctx) return;
    if (charts['xxxChart']) charts['xxxChart'].destroy();
    charts['xxxChart'] = new Chart(ctx, { ... });
}
```

### No mezclar `datosGlobales` y `datosOriginales`

| Variable | Cuándo usar |
|---|---|
| `datosOriginales` | Poblar filtros (para tener todas las opciones disponibles), exportar TODO |
| `datosGlobales` | Render de cualquier tabla o gráfica, calcular KPIs |

`datosGlobales` es un subset de `datosOriginales` filtrado por `puestoTrabajoActual`.

---

## 13. Casos de prueba mínimos a verificar

Antes de entregar cualquier cambio, verificar manualmente:

- [ ] Cargar un Excel con cabecera en fila 2 → datos aparecen correctamente
- [ ] `diasEspera` y `diasPlazo` se calculan y muestran en tabla y modal
- [ ] El filtro de persona (sidebar) filtra todas las vistas
- [ ] Click en cualquier fila → modal se abre con datos correctos
- [ ] Tecla ESC cierra el modal
- [ ] Todas las pestañas de Alertas muestran datos coherentes
- [ ] Gráficas se destruyen y recrean sin errores de canvas al cambiar de vista
- [ ] Modo oscuro funciona (toggle y persistencia en localStorage)
- [ ] Sidebar se colapsa y expande correctamente
- [ ] Exportar genera un XLSX descargable
- [ ] `localStorage` persiste y restaura sesión al recargar el navegador

---

## 14. Anti-patrones — qué NO hacer

```javascript
// ❌ No usar new Date() directamente sobre valores de Excel
new Date(row['F. Recepción'])

// ✅ Usar siempre parseFecha()
parseFecha(row['F. Recepción'])

// ❌ No modificar datosOriginales fuera de procesarDatos()
datosOriginales = datosOriginales.filter(...)

// ✅ Trabajar siempre sobre datosGlobales para filtros temporales
datosGlobales = datosOriginales.filter(...)

// ❌ No crear un Chart.js sin destruir el anterior
charts['areaChart'] = new Chart(...)

// ✅ Destruir siempre antes
if (charts['areaChart']) charts['areaChart'].destroy();
charts['areaChart'] = new Chart(...)

// ❌ No hardcodear colores — rompe el modo oscuro
style="background: white; color: #111"

// ✅ Usar variables CSS
style="background: hsl(var(--card)); color: hsl(var(--foreground))"

// ❌ No acceder a columnas con nombres incorrectos
d['F. Limite']    // falta tilde
d['Metodo']       // falta tilde
d['F.Recepción']  // falta espacio

// ✅ Nombres exactos
d['F.Límite']
d['Método']
d['F. Recepción']
```

---

## 15. Extensiones frecuentes y cómo implementarlas

### A. Añadir un nuevo KPI card en Vista General

1. Añadir el HTML de la tarjeta en `#vista-general` (mismo patrón que los existentes)
2. Asignar un `id` al elemento que muestra el valor (ej. `id="kpiNuevo"`)
3. Calcular el valor en `actualizarKPIs()` y asignarlo: `document.getElementById('kpiNuevo').textContent = valor`

### B. Añadir un nuevo filtro en Tablas

1. Añadir `<select id="filterNuevo">` en la sección de filtros de `#vista-tablas`
2. En `poblarFiltros()`, poblar el select con valores únicos de `datosOriginales`
3. En `aplicarFiltrosTabla()`, añadir: `const nuevo = document.getElementById('filterNuevo').value; if (nuevo) filtrados = filtrados.filter(d => d.ColumnaExcel === nuevo);`
4. En `actualizarTablaPrincipal()`, añadir `'filterNuevo'` al array de listeners

### C. Añadir una nueva pestaña en Alertas

1. Añadir `<button id="atab-nueva" class="alert-tab" onclick="switchAlertTab('atab-nueva')">` en la barra de pestañas
2. Añadir `<div id="apanel-nueva" class="hidden">` con su tabla y `<tbody id="apanel-nueva-body">`
3. Añadir `'apanel-nueva'` al array en `switchAlertTab()`
4. Añadir `'atab-nueva': 'apanel-nueva'` al `panelMap` en `switchAlertTab()`
5. En `actualizarTablaAlertas()`, filtrar los datos y rellenar `apanel-nueva-body`

### D. Añadir un campo nuevo al modal

En `abrirModal()`, dentro de la sección correspondiente, añadir:

```javascript
campoModal('Etiqueta', d.campoNuevo || '-')
// La función campoModal() genera el HTML de un campo del grid
```

---

## 16. Rendimiento y límites

| Límite | Valor aproximado | Nota |
|---|---|---|
| Filas de Excel procesables | ~5.000–10.000 | Depende del navegador y RAM |
| localStorage disponible | ~5 MB | Error capturado con try/catch |
| Puntos en scatter chart | Limitado a 200 | Ver `sample = datosGlobales.slice(0, 200)` |
| Filas por página en tabla | 50 | Constante `ROWS_PER_PAGE` |
| Mini-tablas en Mi Día | 20 por sección | Ver `.slice(0, 20)` |
| Analistas en chart de equipo | Top 10 | Ver `.slice(0, 10)` |

---

*AGENTS.md — Dashboard Lab v3 · Actualizado: 2026-02*
