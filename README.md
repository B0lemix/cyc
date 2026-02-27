# Dashboard Lab v3 — Gestión de Muestras

> Sistema de monitorización de muestras de laboratorio basado en Excel.
> Aplicación web autocontenida — sin servidor, sin instalación, funciona en cualquier navegador moderno.

---

## Índice

1. [Visión general](#1-visión-general)
2. [Primeros pasos](#2-primeros-pasos)
3. [Formato del Excel](#3-formato-del-excel)
4. [Campos calculados](#4-campos-calculados)
5. [Vistas y funcionalidades](#5-vistas-y-funcionalidades)
6. [Funciones de gestión](#6-funciones-de-gestión)
7. [Modo oscuro y personalización](#7-modo-oscuro-y-personalización)
8. [Exportación](#8-exportación)
9. [Persistencia de sesión](#9-persistencia-de-sesión)
10. [Preguntas frecuentes](#10-preguntas-frecuentes)
11. [Referencia técnica rápida](#11-referencia-técnica-rápida)

---

## 1. Visión general

**Dashboard Lab v3** es una aplicación HTML/CSS/JS que permite a analistas y responsables de laboratorio visualizar, filtrar y gestionar el estado de todas las muestras pendientes a partir de un archivo Excel estándar.

### Usuarios objetivo

| Perfil | Usos principales |
|---|---|
| **Analista** | Ver su carga del día, identificar muestras urgentes, controlar plazos y caducidades |
| **Responsable de área** | Supervisar el equipo, detectar cuellos de botella, exportar informes |
| **Jefe de laboratorio** | KPIs globales, SLA por área, distribución de carga, tendencias |

### Tecnologías utilizadas

| Librería | Versión | Uso |
|---|---|---|
| [Tailwind CSS](https://tailwindcss.com/) | CDN (play) | Estilos y layout |
| [SheetJS (XLSX)](https://sheetjs.com/) | 0.18.5 | Lectura de archivos Excel |
| [Chart.js](https://www.chartjs.org/) | 3.9.1 | Gráficas y visualizaciones |
| Google Fonts — Inter | — | Tipografía |

> No se envía ningún dato a ningún servidor. Todo el procesamiento ocurre en el navegador del usuario.

---

## 2. Primeros pasos

1. Abrir `dashboard_v3.html` en un navegador moderno (Chrome, Edge, Firefox).
2. Arrastrar el archivo Excel a la zona de carga **o** hacer clic en **"Seleccionar archivo"**.
3. El dashboard carga automáticamente y muestra la **Visión General**.
4. Usar el selector **"Filtrar por Personal"** en la barra lateral para ver la carga de un analista concreto.

> **Nota:** La próxima vez que se abra el archivo, los datos de la última sesión se restauran automáticamente desde `localStorage`.

Para cargar un archivo nuevo, hacer clic en **"Cargar nuevo"** (botón en la cabecera superior).

---

## 3. Formato del Excel

### Estructura requerida

```
Fila 1 → (puede contener un título, información corporativa u otra cosa — se ignora)
Fila 2 → CABECERAS de columna  ← obligatorio
Fila 3+ → Datos
```

> ⚠️ **La fila 2 debe contener exactamente las cabeceras** tal como se indican abajo. Los nombres son sensibles a mayúsculas, espacios y acentos.

### Columnas requeridas / reconocidas

| Columna | Descripción | Tipo |
|---|---|---|
| `Muestra` | Identificador único de la muestra | Texto |
| `F. Recepción` | Fecha de recepción en el laboratorio | Fecha |
| `Cliente` | Nombre del cliente | Texto |
| `Matriz` | Tipo de matriz analizada | Texto |
| `Parametro` | Parámetro a analizar | Texto |
| `Código` | Código interno de referencia | Texto |
| `F.Límite` | Fecha límite de entrega de resultados | Fecha |
| `Area` | Área del laboratorio responsable | Texto |
| `Método` | Método analítico aplicado | Texto |
| `Persona` | Analista asignado | Texto |
| `F. Caduc` | Fecha de caducidad de la muestra | Fecha |
| `F. Max` | Valor máximo de referencia | Texto/Número |
| `Min` | Valor mínimo de referencia | Texto/Número |
| `Conductivid` | Valor de conductividad | Texto/Número |
| `Estado` | Estado interno registrado en el Excel | Texto |
| `Firma` | Nombre/fecha de firma del analista | Texto |
| `FinAna` | Registro de fin de análisis | Texto |
| `Intro` | Campo de introducción / notas | Texto |
| `ceco` | Centro de coste | Texto |

### Formatos de fecha aceptados

El parser de fechas acepta automáticamente los siguientes formatos:

- `AAAA-MM-DD` — ISO estándar (ej. `2025-03-15`)
- `DD/MM/AAAA` — Español (ej. `15/03/2025`)
- `DD-MM-AAAA` — Con guiones (ej. `15-03-2025`)
- Números de serie de Excel (fechas almacenadas internamente como enteros)

---

## 4. Campos calculados

Estos campos **no están en el Excel** y son calculados automáticamente al cargar los datos.

| Campo | Fórmula | Significado |
|---|---|---|
| `diasEspera` | `HOY − F. Recepción` | Días transcurridos desde que llegó la muestra |
| `diasPlazo` | `F.Límite − F. Recepción` | Total de días permitidos para completar el análisis |
| `diasParaVencer` | `F.Límite − HOY` | Días restantes hasta el plazo límite |
| `pctPlazo` | `diasEspera / diasPlazo × 100` | Porcentaje del plazo total ya consumido |
| `diasParaCaducar` | `F. Caduc − HOY` | Días hasta que caduca la muestra |

### Estado de vencimiento de plazo (`estadoVencimiento`)

| Valor | Condición | Color |
|---|---|---|
| `vencido` | `diasParaVencer < 0` | Rojo |
| `proximo` | `0 ≤ diasParaVencer ≤ 7` | Naranja |
| `ok` | `diasParaVencer > 7` | Verde |

### Estado de caducidad (`estadoCaducidad`)

| Valor | Condición | Significado |
|---|---|---|
| `caducado` | `diasParaCaducar < 0` | Muestra caducada |
| `proxima` | `0 ≤ diasParaCaducar ≤ 30` | Caduca en menos de 30 días |
| `ok` | `diasParaCaducar > 30` | Sin riesgo de caducidad próxima |

### Campos derivados

| Campo | Condición |
|---|---|
| `firmado` | `true` si la columna `Firma` tiene algún valor |
| `finAnaCompleto` | `true` si la columna `FinAna` tiene algún valor |

---

## 5. Vistas y funcionalidades

### 5.1 Visión General

Panel de resumen con los indicadores más importantes.

**Tarjetas KPI (fila superior):**

| Tarjeta | Qué muestra |
|---|---|
| Total Muestras | Recuento total de filas cargadas |
| Vencidas | Muestras con plazo superado |
| Próximas a vencer | Muestras que vencen en ≤ 7 días |
| Días Espera promedio | Media de `diasEspera` de todas las muestras |
| Caducidad próxima | Muestras con `F. Caduc` ≤ 30 días |

**Gráficas:**
- Distribución por Área (donut) — o por Parámetros si hay un analista seleccionado
- Estado de Vencimientos (barras: Vencidas / Próximas / En plazo)

**Alertas recientes:** Lista de las 5 muestras más urgentes (clicables → abre modal de detalle).

---

### 5.2 Mi Día ☀️ *(para analistas)*

Vista personalizada diseñada para el trabajo diario. Se recomienda **seleccionar primero un analista** en el selector de la barra lateral.

Muestra 6 secciones con sus propias mini-tablas (clicables):

| Sección | Color | Criterio |
|---|---|---|
| 🔴 Crítico | Rojo | Vencidas + vencen HOY |
| 🟠 Urgente | Naranja | Vencen en 1–3 días |
| 🟡 Esta semana | Amarillo | Vencen en 4–7 días |
| ⚗️ Caducidad próxima | Púrpura | `F. Caduc` ≤ 30 días |
| ✍️ Sin Firma | Azul | Columna `Firma` vacía |
| 🔬 Sin FinAna | Índigo | Columna `FinAna` vacía |

Cada sección muestra hasta 20 registros: Muestra · Cliente · Fecha · Días restantes · Área.

---

### 5.3 Indicadores KPI

Métricas avanzadas de rendimiento:

| KPI | Cálculo |
|---|---|
| Tasa de Cumplimiento | `(En plazo / Total) × 100` |
| Eficiencia de Plazo | `(1 − promedio(diasEspera) / promedio(diasPlazo)) × 100` |
| Carga Promedio | `Total muestras / número de analistas` |
| Clientes Activos | Clientes únicos con muestras |
| Métodos Utilizados | Métodos únicos en uso |
| Plazo Promedio | Media de `diasPlazo` en días |

**Tabla SLA por Área** *(para responsables)*: muestra para cada área el total, muestras en plazo, vencidas, próximas y el % de cumplimiento con semáforo de color.

---

### 5.4 Gráficas

6 visualizaciones independientes:

1. Distribución por Área / por Parámetros (según filtro de personal)
2. Top 5 Clientes
3. Distribución por Matriz
4. Top 10 Parámetros
5. Muestras por Método
6. Distribución por Centro de Coste (`ceco`)

Gráfica de evolución (scatter): **Días Espera vs Días Plazo** por muestra, con colores según estado de vencimiento.

---

### 5.5 Tablas Detalladas

Vista de tabla completa con todas las funcionalidades de filtrado.

**Filtros disponibles:**
- Por Área · Cliente · Parámetro · Estado de vencimiento · Persona
- Búsqueda libre (busca en Muestra, Cliente, Parámetro, Código)
- Filtro por rango de fechas de recepción (Desde · Hasta)

**Chips de filtro rápido:**

| Chip | Efecto |
|---|---|
| 🔴 Vencidas | Solo muestras con plazo superado |
| ⚠️ Próximas | Vencen en ≤ 7 días |
| ⚡ Hoy | Vencen exactamente hoy |
| 📅 Esta semana | Vencen en 1–7 días |
| ✍️ Sin firma | Columna Firma vacía |
| 🔬 Sin FinAna | Columna FinAna vacía |
| ✅ En plazo | Solo muestras sin urgencia |
| × Limpiar | Elimina el chip activo |

**Toggle de columnas:** Botón "Columnas" para mostrar/ocultar: Matriz, Código, Método, Días Plazo, F. Recepción, Progreso.

**Columna Progreso:** Barra de color que muestra el % del plazo consumido.

| % Plazo consumido | Color |
|---|---|
| < 50 % | Verde |
| 50–75 % | Amarillo |
| 75–100 % | Naranja |
| > 100 % | Rojo |

**Ordenación:** Click en cualquier cabecera de columna. Segundo click invierte el orden.

**Paginación:** 50 filas por página con navegación ← / →.

**Click en fila:** Abre el [modal de detalle](#modal-de-detalle).

---

### 5.6 Alertas

Vista con 4 pestañas independientes, cada una con su contador:

| Pestaña | Criterio de selección |
|---|---|
| ⏱ Plazo | `estadoVencimiento` = `vencido` o `proximo` |
| ⚗️ Caducidad | `estadoCaducidad` = `caducado` o `proxima` |
| ✍️ Sin Firma | Columna `Firma` vacía |
| 🔬 Sin FinAna | Columna `FinAna` vacía |

Todas las filas son clicables → abre el modal de detalle.

---

### 5.7 Gestión de Equipo

**Tabla de carga por persona:**
- Persona · Total muestras · Vencidas · Próximas · Rendimiento (%) · Barra de carga relativa

**Gráfico de barras apiladas:** Distribución por persona (En plazo / Próximas / Vencidas).

**Heatmap de rendimiento:** Cuadrícula de métricas por analista con semáforo de color:
- Vencidas % — qué porcentaje de su carga está vencido
- Eficiencia — tiempo restante promedio respecto al plazo
- Carga — número total de muestras asignadas

---

### 5.8 Análisis Avanzado

- Distribución por prioridad (Alta / Media / Baja)
- Top 10 Parámetros (barras)
- Scatter plot **Días Espera vs Días Plazo** con colores por estado

---

### Modal de detalle

Click en cualquier fila de cualquier tabla abre un modal con toda la información de la muestra organizada en 5 secciones:

| Sección | Campos |
|---|---|
| Identificación | Muestra, Código, Cliente, Matriz |
| Fechas | F. Recepción, F.Límite, F. Caduc, F. Max, Min |
| Análisis | Parámetro, Método, Área, Conductividad, ceco |
| Estado | Estado (Excel), Firma, FinAna, Intro, Persona |
| Calculado | Días Espera, Días Plazo, % Plazo, Días para Vencer, Estado Vencimiento, Estado Caducidad |

Barra de progreso visual en el modal con el % del plazo consumido y color semáforo.

**Cierre:** botón ×, click fuera del modal, o tecla `ESC`.

---

## 6. Funciones de gestión

### Stats Ribbon (barra de estado rápida)

Visible siempre bajo el encabezado cuando hay datos cargados. Muestra 6 contadores clicables:

```
[ Total: 234 ]  [ 🔴 Vencidas: 12 ]  [ 🟠 Próximas: 28 ]  [ ✅ En plazo: 194 ]  [ ⚗️ Caduc. próxima: 5 ]  [ ✍️ Sin firma: 17 ]
```

Hacer click en cualquier contador navega a la vista Tablas con el filtro correspondiente aplicado.

### Filtro por Personal (sidebar)

El selector en la parte inferior del sidebar filtra **todos los datos globales** a un único analista. Afecta a todas las vistas simultáneamente.

Cuando hay un analista seleccionado:
- Las gráficas muestran distribución de sus parámetros en lugar de áreas
- La vista "Mi Día" muestra únicamente su carga
- Las exportaciones se limitan a sus datos

---

## 7. Modo oscuro y personalización

### Activar modo oscuro

Botón de luna/sol (🌙/☀️) en la cabecera superior derecha. La preferencia se guarda en `localStorage` con la clave `lab_darkmode` y se restaura automáticamente.

### Colapsar sidebar

Botón ☰ en la esquina superior izquierda. El sidebar se reduce a 64 px mostrando solo los iconos de navegación.

### Imprimir

Botón de impresora (🖨) en la cabecera. Llama a `window.print()`. La hoja de estilos de impresión oculta automáticamente el sidebar, la ribbon de estadísticas y todos los elementos marcados con `.no-print`.

---

## 8. Exportación

Botón **"Exportar"** en la cabecera. Despliega 3 opciones:

| Opción | Contenido |
|---|---|
| Exportar todo | Todos los registros de `datosOriginales` sin filtros |
| Personal seleccionado | Solo las muestras de `datosGlobales` (respeta filtro de analista) |
| Vencidas + Urgentes | Solo alertas de `datosGlobales` (vencidas y próximas) |

El Excel exportado incluye **las 19 columnas originales + los campos calculados**: Días Espera, Días Plazo, Días para Vencer, Estado Vencimiento.

Nombre del archivo generado: `lab_completo_AAAA-MM-DD.xlsx` / `lab_PERSONA_AAAA-MM-DD.xlsx` / `alertas_PERSONA_AAAA-MM-DD.xlsx`.

---

## 9. Persistencia de sesión

Los datos del Excel se guardan en `localStorage` del navegador al cargar un archivo. Al abrir el dashboard de nuevo, la sesión anterior se restaura automáticamente (con un toast informativo).

| Clave localStorage | Contenido |
|---|---|
| `labDashboard_v3_raw` | JSON con los datos crudos del Excel |
| `labDashboard_v3_meta` | Fecha de última carga y total de registros |
| `lab_darkmode` | Preferencia de modo oscuro (`"dark"` o `""`) |

> **Límite:** `localStorage` soporta ~5 MB. Para archivos Excel muy grandes (miles de filas con muchas columnas), puede alcanzarse el límite. El sistema captura el error y avisa.

Para borrar la sesión y cargar un archivo nuevo: botón **"Cargar nuevo"** (visible tras cargar datos).

---

## 10. Preguntas frecuentes

**¿Por qué no se cargan mis datos?**
Verificar que las cabeceras estén exactamente en la **fila 2** del Excel, con los nombres exactos indicados (acentos incluidos). Comprobar también que la columna `Muestra` tenga valores en todas las filas de datos.

**¿Las fechas aparecen como números raros?**
Asegurarse de que las celdas de fecha en Excel tengan formato de fecha (no texto). El parser admite varios formatos pero las celdas con formato de texto pueden no reconocerse.

**¿Puedo usar el dashboard sin conexión a internet?**
Las librerías (Tailwind, SheetJS, Chart.js) se cargan desde CDN. Sin conexión no funcionará. Para uso offline, descargar las librerías localmente y actualizar los `<script src>`.

**¿Los datos se envían a algún servidor?**
No. Todo el procesamiento es local en el navegador. Los datos solo se guardan en `localStorage` del navegador del usuario.

**¿Qué navegadores son compatibles?**
Chrome 90+, Edge 90+, Firefox 88+, Safari 15+. No compatible con Internet Explorer.

**¿Puedo añadir más columnas al Excel?**
Sí. Las columnas extra se leen y se muestran en el modal de detalle como parte del objeto de datos, aunque no aparecerán en las tablas principales (que muestran columnas fijas).

---

## 11. Referencia técnica rápida

### Archivos del proyecto

```
c:\...\CYC-WEB\v0\c\
├── dashboard_v3.html   ← Aplicación principal (versión actual)
├── dashboard_v2.html   ← Versión anterior (referencia)
├── dashboard.html      ← Versión original (referencia)
├── cavedish.webp       ← Logo de la aplicación
├── README.md           ← Esta documentación
├── AGENTS.md           ← Guía para agentes de IA
└── obsoleto\           ← Versiones anteriores archivadas
```

### Resumen de vistas y funciones JS asociadas

| Vista | ID | Función JS |
|---|---|---|
| Visión General | `vista-general` | `actualizarDashboard()` |
| Mi Día | `vista-miidia` | `actualizarMiDia()` |
| KPI | `vista-kpi` | `actualizarKPIsAvanzados()` |
| Gráficas | `vista-graficas` | `actualizarGraficasAvanzadas()` |
| Tablas | `vista-tablas` | `actualizarTablaPrincipal()` |
| Análisis | `vista-analisis` | `actualizarAnalisisAvanzado()` |
| Alertas | `vista-alertas` | `actualizarTablaAlertas()` |
| Equipo | `vista-equipo` | `actualizarCargaTrabajo()` + `actualizarGraficoEquipo()` + `actualizarHeatmap()` |

### Paleta de colores del sistema

| Variable CSS | Modo claro | Modo oscuro | Uso |
|---|---|---|---|
| `--background` | `hsl(0 0% 100%)` | `hsl(220 14% 10%)` | Fondo de página |
| `--card` | `hsl(0 0% 100%)` | `hsl(220 14% 14%)` | Fondo de tarjetas |
| `--border` | `hsl(214 32% 91%)` | `hsl(220 14% 22%)` | Bordes |
| `--primary` | `hsl(222 47% 11%)` | `hsl(210 70% 72%)` | Acentos, botones |
| `--destructive` | `hsl(0 84% 60%)` | `hsl(0 70% 58%)` | Alertas, errores |
| `--muted` | `hsl(210 40% 96%)` | `hsl(220 14% 19%)` | Fondos secundarios |

---

*Dashboard Lab v3 — Cavendish / CYC · Última revisión: 2026-02*
