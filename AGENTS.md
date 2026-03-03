# AGENTS.md — Guía para agentes de IA

> Este archivo describe la arquitectura, convenciones y reglas del proyecto para que cualquier agente de IA pueda trabajar de forma autónoma, segura y coherente con el código existente.

---

## 1. Descripción del proyecto

**Dashboard Lab v3** es una aplicación web autocontenida (un único archivo HTML de ~2100 líneas) para gestión de muestras de laboratorio. Lee archivos Excel, calcula métricas de plazos y caducidad, y presenta 9 vistas con gráficas, tablas, alertas, análisis de equipo y calendario de carga por fechas.

- **Archivo principal:** `dashboard_v3.3.html`
- **Archivo de datos:** `V3.xls` (debe estar en el mismo directorio que el HTML)
- **Sin backend:** toda la lógica corre en el navegador
- **Sin build step:** HTML + CSS + JS en un solo archivo
- **Dependencias (CDN):** Tailwind CSS (play), SheetJS 0.18.5, Chart.js 3.9.1
- **Compatibilidad:** Chrome 86+ / Edge 86+ para carga automática de V3.xls (File System Access API). Firefox no soporta `showOpenFilePicker`.

---

## 2. Estructura del repositorio

```
c:\OTROS\CYC_WEBAPP\cyc\
├── dashboard_v3.3.html   ← ARCHIVO PRINCIPAL (versión activa)
├── V3.xls                ← Datos de muestras (siempre en el mismo directorio)
├── dashboard_v3.2.html   ← Versión anterior (no tocar)
├── dashboard_v3.html     ← Versión anterior (no tocar)
├── cavedish.webp         ← Logo (referenciado en el HTML)
├── README.md             ← Documentación de usuario
├── AGENTS.md             ← Este archivo
└── obsoleto\             ← Archivos archivados, ignorar
```

**Regla:** Trabajar únicamente sobre `dashboard_v3.3.html`. Crear versiones nuevas si el cambio es estructural grande (e.g. `dashboard_v4.html`).

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
let calFechaMes         = new Date(); // Mes mostrado en vista-calendario (siempre día 1)
```

### Constantes de localStorage

```javascript
const LS_RAW  = 'labDashboard_v3_raw';    // Datos crudos del Excel (JSON)
const LS_META = 'labDashboard_v3_meta';   // Metadatos (fecha, total)
// + 'lab_darkmode' para preferencia de tema
```

### Persistencia en IndexedDB

El handle del archivo V3.xls se guarda en IndexedDB (no localStorage, ya que `FileSystemFileHandle` no es serializable):

```javascript
// Base de datos: 'labDashboardFS_v1'  |  Object store: 'handles'
// Clave usada: 'fileHandle'  →  FileSystemFileHandle de V3.xls
```

### Flujo de datos

```
V3.xls (desde FileSystemFileHandle o drag & drop)
    ↓  recargarDesdeRuta() / handleFiles()
    ↓  _procesarArrayBuffer(arrayBuffer, nombre, fechaMod)
    ↓  leerExcel(arrayBuffer)              ← SheetJS: header en fila 2
    ↓  rawData (array de objetos)
    ↓  procesarDatos(rawData)              ← añade campos calculados
    ↓  datosOriginales / datosGlobales
    ↓  guardarEnLocalStorage(rawData, fechaMod)  ← persiste en localStorage
    ↓  actualizarDashboard()               ← renderiza KPIs + gráficas + filtros
    ↓  renderVista(vistaActual)            ← renderiza la vista activa
```

### Secuencia de inicialización

```javascript
// Al final del <script>:
initDarkMode();
cargarDesdeLocalStorage();   // muestra datos cacheados inmediatamente
_intentarAutoCargar();       // refresca desde el archivo real (asíncrono)
```

`_intentarAutoCargar()` NO muestra diálogo al usuario: si hay permiso previo, carga silenciosamente; si no, muestra un indicator de "Autorizar" en la zona de carga.

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

Las vistas están registradas en `cambiarVista()`:

```javascript
const vistas = ['general','miidia','kpi','graficas','tablas','analisis','alertas','equipo','calendario'];

const titles = {
    general:   ['Vision General',    '...'],
    miidia:    ['Mi Dia',            '...'],
    kpi:       ['Indicadores KPI',   '...'],
    graficas:  ['Graficas',          '...'],
    tablas:    ['Tablas Detalladas', '...'],
    analisis:  ['Analisis Avanzado', '...'],
    alertas:   ['Alertas',           '...'],
    equipo:    ['Gestion de Equipo', '...'],
    calendario:['Carga por Fechas',  'Distribucion semanal y mensual de muestras pendientes']
};
```

### Vista-calendario — funciones JS

| Función | Descripción |
|---|---|
| `calNavMes(dir)` | Navega: `dir=-1` mes anterior, `dir=0` hoy, `dir=1` mes siguiente |
| `actualizarCalendario()` | Construye `recMap` (dict `'YYYY-MM-DD' → [índices]`) y llama a `renderCalMes` + `renderCalGraficaSemana` |
| `renderCalMes(recMap)` | Renderiza la cuadrícula mensual con heatmap de 5 niveles de verde |
| `calVerDia(key)` | Al hacer click en un día: muestra tabla de muestras + chart horizontal de parámetros |
| `renderCalGraficaSemana(recMap)` | Gráfica de barras agrupada por día de la semana (histórico del mes mostrado) |

**Heatmap de color:**
- `recMap[key].length === 0` → `hsl(var(--muted))` (fondo gris)
- `> 0` hasta máximo mensual: 4 intensidades de verde (`hsla(142,76%,36%,.2)` a `hsl(142,76%,28%)`)
- Día actual: outline con `hsl(var(--primary))`

**Chart de parámetros por día (`calDiaChart`):**
- Tipo `bar` con `indexAxis: 'y'` (horizontal)
- Top 12 parámetros por frecuencia
- Alto dinámico: `Math.max(120, paramLabels.length * 28) + 'px'`
- Se destruye al cerrar el panel del día

### Añadir una nueva vista

1. Añadir botón en `<nav>` del sidebar con `id="nav-NOMBRE"` y `onclick="cambiarVista('NOMBRE')"`
2. Añadir `<div id="vista-NOMBRE" class="hidden space-y-6">` en `#dashboardContent`
3. Añadir entrada en el objeto `titles` en `cambiarVista()`
4. Añadir `'NOMBRE'` al array `vistas` en `cambiarVista()`
5. Añadir case en `renderVista()` llamando a la función de render
6. Implementar `actualizarNOMBRE()` con la lógica de la vista

---

## 7. Carga automática de V3.xls (File System Access API)

### Flujo de carga

```
Apertura del HTML
    ↓
cargarDesdeLocalStorage()     ← muestra datos cacheados si existen
    ↓
_intentarAutoCargar()
    ├── Si protocol !== 'file://' → intenta fetch('./V3.xls') y './V3.xlsx'
    │       ↓ éxito → _procesarArrayBuffer(buf, nombre, Last-Modified header)
    │
    └── Si protocol === 'file://' → lee FileSystemFileHandle de IndexedDB
            ├── perm === 'granted'  → recargarDesdeRuta()  (silencioso)
            └── perm !== 'granted'  → muestra estado "Autorizar carga"
```

### Funciones de FS API + IndexedDB

```javascript
_abrirIDB()                         // abre DB 'labDashboardFS_v1', store 'handles'
_idbSet(k, v)                       // guarda handle
_idbGet(k)                          // recupera handle
_idbDel(k)                          // borra handle

seleccionarArchivoV3()              // abre showOpenFilePicker, guarda handle en IDB
recargarDesdeRuta()                 // recarga V3.xls (fetch o fileHandle)
desvincularArchivo()                // borra handle de IDB, resetea UI
_intentarAutoCargar()               // init: carga silenciosa si hay permiso
_mostrarFsStatusOk(nombre, fecha)   // UI: "Vinculado: V3.xls — 01/03/2026"
_mostrarFsStatusPendiente(nombre)   // UI: "Autorizar carga de V3.xls"
```

### Regla CORS con file:// protocol

```javascript
// ❌ fetch() desde file:// lanza CORS error
fetch('./V3.xls')   // → "blocked by CORS policy" desde origin 'null'

// ✅ SIEMPRE guardar con este guard
if (location.protocol !== 'file:') {
    // intentar fetch
}
// Si no, usar FileSystemFileHandle desde IndexedDB
```

### `_procesarArrayBuffer` — función central de carga

```javascript
function _procesarArrayBuffer(arrayBuffer, nombre, fechaMod) {
    const rawData = leerExcel(arrayBuffer);
    datosOriginales = procesarDatos(rawData);
    datosGlobales = [...datosOriginales];
    guardarEnLocalStorage(rawData, fechaMod);   // ← fechaMod = fecha real del archivo
    // actualiza UI, pobla filtros, renderiza dashboard
    mostrarToast(datosOriginales.length + ' muestras cargadas — ' + nombre, 'success');
}
```

### `guardarEnLocalStorage` — firma actualizada

```javascript
// FIRMA ACTUAL (v3.3)
function guardarEnLocalStorage(rawData, fechaArchivo) {
    localStorage.setItem(LS_RAW, JSON.stringify(rawData));
    localStorage.setItem(LS_META, JSON.stringify({
        fecha: fechaArchivo || new Date().toLocaleString('es-ES'),
        total: rawData.length
    }));
}
// ⚠️ fechaArchivo debe ser la fecha de MODIFICACIÓN del archivo V3.xls,
//    no la fecha actual. Se usa en "Ultima act." del header.
```

**Orígenes de `fechaMod` según la ruta de carga:**
| Ruta | Fuente de fecha |
|---|---|
| Fetch HTTP | `resp.headers.get('Last-Modified')` parseado con `new Date()` |
| FileSystemFileHandle | `file.lastModified` (timestamp) |
| Drag & drop manual | `file.lastModified` (timestamp) |

---

## 8. Parser de fechas — `parseFecha()`

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

## 9. Sistema de gráficas (Chart.js)

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

## 10. Sistema de color / diseño

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

## 11. Modal de detalle

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

## 12. Toast / notificaciones

```javascript
mostrarToast(mensaje, tipo);
// tipo: 'success' | 'error' | 'warning' | 'info'
// Duración: 3.5 segundos, animación slide-in/out
```

---

## 13. Reglas de codificación

### Convenciones

- **Funciones en camelCase:** `actualizarKPIs`, `aplicarFiltrosTabla`, `parseFecha`
- **Funciones internas/privadas con prefijo `_`:** `_abrirIDB`, `_idbGet`, `_procesarArrayBuffer`
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

## 14. Casos de prueba mínimos a verificar

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
- [ ] **[v3.3]** Botón "Autorizar carga de V3.xls" abre el file picker en Chrome/Edge
- [ ] **[v3.3]** Tras autorizar, recargar la página carga V3.xls automáticamente (sin diálogo)
- [ ] **[v3.3]** "Ultima act." muestra la fecha de modificación del archivo V3.xls, no la hora de recarga
- [ ] **[v3.3]** Botón "Recargar V3.xls" en el header recarga el archivo sin recargar la página
- [ ] **[v3.3]** Sin errores CORS en consola al abrir el HTML por doble-click (file://)
- [ ] **[v3.3]** Vista "Carga por Fechas" muestra el calendario mensual con heatmap de colores
- [ ] **[v3.3]** Click en día del calendario muestra tabla + gráfica de parámetros
- [ ] **[v3.3]** Navegación mensual (← / Hoy / →) actualiza el calendario correctamente
- [ ] **[v3.3]** Cerrar panel de día destruye `calDiaChart` sin errores de canvas

---

## 15. Anti-patrones — qué NO hacer

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

// ❌ No usar fetch() sobre archivos locales sin el guard de protocolo
fetch('./V3.xls')   // CORS error si protocol === 'file:'

// ✅ Siempre guard
if (location.protocol !== 'file:') { /* fetch */ }
// Para file://, usar FileSystemFileHandle desde IndexedDB

// ❌ No guardar FileSystemFileHandle en localStorage (no serializable)
localStorage.setItem('handle', fileHandle)  // → falla silenciosamente

// ✅ Usar IndexedDB (structured-cloneable)
await _idbSet('fileHandle', fileHandle)
```

---

## 16. Extensiones frecuentes y cómo implementarlas

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

### E. Añadir un nuevo mes/periodo al calendario

El calendario usa `calFechaMes` (variable global de estado). Para añadir una vista de período personalizado:
1. Calcular el rango de fechas deseado
2. Filtrar `datosGlobales` por `parseFecha(d['F. Recepción'])` dentro del rango
3. Construir `recMap` como `{ 'YYYY-MM-DD': [índices] }` y llamar a `renderCalMes(recMap)`

---

## 17. Rendimiento y límites

| Límite | Valor aproximado | Nota |
|---|---|---|
| Filas de Excel procesables | ~5.000–10.000 | Depende del navegador y RAM |
| localStorage disponible | ~5 MB | Error capturado con try/catch |
| IndexedDB para FileHandle | Sin límite práctico | Solo guarda el handle, no datos |
| Puntos en scatter chart | Limitado a 200 | Ver `sample = datosGlobales.slice(0, 200)` |
| Filas por página en tabla | 50 | Constante `ROWS_PER_PAGE` |
| Mini-tablas en Mi Día | 20 por sección | Ver `.slice(0, 20)` |
| Analistas en chart de equipo | Top 10 | Ver `.slice(0, 10)` |
| Parámetros en chart de día | Top 12 | Ver `.slice(0, 12)` en `calVerDia()` |

---

*AGENTS.md — Dashboard Lab v3.3 · Actualizado: 2026-03*
