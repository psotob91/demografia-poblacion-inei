# Auditoria y refactor conservador 2026-04-12

## Objetivo

Auditar y refactorizar el repositorio sin romper el output contractual downstream:

`data/final/population_inei/population_result.parquet`

La llave logica contractual es:

- `year_id`
- `age`
- `sex_id`
- `location_id`

Las columnas contractuales son:

- `year_id`
- `age`
- `sex_id`
- `location_id`
- `population`

## Baseline pre-cambio

Baseline observada antes de modificar el codigo:

| chequeo | valor |
|---|---:|
| filas | 207792 |
| columnas | 5 |
| columnas | `year_id, age, sex_id, location_id, population` |
| tipos | `integer, integer, integer, integer, integer` |
| PK unicas | 207792 |
| duplicados PK | 0 |
| rango `year_id` | 1995-2030 |
| rango `age` | 0-110 |
| dominio `sex_id` | 8507, 8532 |
| rango `location_id` | 0-25 |
| numero de ubicaciones | 26 |
| rango `population` | 0-319672 |
| celdas faltantes | 0 |
| MD5 parquet | `d9b4fdbb8d2654da19c9ec31c27dd395` |

Nota: el MD5 del archivo parquet se registra como evidencia de archivo, pero la comparacion final debe priorizar un hash deterministico de contenido ordenado por PK porque la metadata fisica del parquet puede cambiar tras reescrituras equivalentes.

## Hallazgos iniciales

- `scripts/99_qc_global_hierarchical.R` agregaba `pk_hash` sobre la tabla principal en memoria, por lo que el resumen de QC jerarquico podia reportar 6 columnas aunque el parquet contractual tuviera 5.
- El bloque final de catalogo en el QC jerarquico usaba una firma incompatible de `register_run_start()` y una funcion `register_artefact()` no definida en las utilidades actuales; ademas estaba envuelto en `try(..., silent = TRUE)`.
- `reports/method-report.qmd` era principalmente narrativo-metodologico; faltaban secciones de evidencia ejecutable, comparacion baseline/post, despliegue, diccionarios y propuesta de maestros.
- Existian documentos `MASTER_*` activos bajo `docs/` aunque la gobernanza vigente indica que los masters historicos deben consolidarse o archivarse.

## Evidencia post-cambio

Ejecucion realizada desde la raiz del repositorio el 2026-04-12.

## Cambios implementados

- Se agrego `scripts/98_contract_fingerprint.R` para generar fingerprints reproducibles de outputs parquet.
- Se agrego `scripts/96_generate_table_dictionaries.R` para generar diccionarios extendidos de artefactos tabulares del pipeline.
- Se agrego `scripts/97_validate_dictionary_coverage.R` para fallar si una tabla esperada no tiene diccionario o si el diccionario no cubre sus columnas.
- Se corrigio `scripts/99_qc_global_hierarchical.R` para calcular duplicados sin agregar `pk_hash` al objeto principal y para registrar artefactos con `register_artifact()`.
- Se corrigio `R/catalog_utils.R` para que `register_run_finish()` escriba correctamente el estado `success`/`failed` en `provenance_runs.csv`.
- Se corrigio `scripts/04_build_national_from_dept.R` para que el diccionario del nacional aditivo no dependa del orden fisico de columnas.
- Se amplio `reports/method-report.qmd` con anexo tecnico de flujo real, pseudocodigo, QC, diccionarios, comparacion baseline/post, despliegue y propuesta de maestros.
- Se consolido la gobernanza de masters en `docs/MASTERS_GOVERNANCE.md` y se retiraron los `MASTER_*` activos de `docs/`, preservando sus copias historicas en `docs/archive/masters_legacy/`.

## Ejecucion

Pipeline ejecutado en orden:

1. `scripts/01_ingesta_raw_inei.R`
2. `scripts/02_normaliza_long_omop.R`
3. `scripts/03_extrapola_80_110.R`
4. `scripts/04_build_national_from_dept.R`
5. `scripts/05_build_population_view_hierarchical.R`
6. `scripts/99_qc_global.R`
7. `scripts/99_qc_global_hierarchical.R`

Despues de corregir `R/catalog_utils.R`, se re-ejecutaron los dos scripts de QC para confirmar que la evidencia de catalogo se genera con el codigo corregido.

Iteracion adicional solicitada:

- generar diccionarios para staging, finales, QC, fingerprints y catalogos;
- validar cobertura exacta de columnas por diccionario;
- re-renderizar HTML incorporando la cobertura de diccionarios.

Resultado de la iteracion adicional:

- pipeline principal re-ejecutado completo;
- `scripts/96_generate_table_dictionaries.R` ejecutado correctamente;
- `scripts/97_validate_dictionary_coverage.R` ejecutado correctamente;
- `reports/method-report.qmd` re-renderizado correctamente;
- HTML revisado: ya no contiene mensajes de cobertura/comparacion pendiente.

Advertencia observada en las corridas: `The project is out-of-sync -- use renv::status() for details.` No bloqueo la ejecucion y no se modifico `renv.lock`.

## Fingerprint post-cambio

| chequeo | valor post |
|---|---:|
| filas | 207792 |
| columnas | 5 |
| columnas | `year_id, age, sex_id, location_id, population` |
| tipos | `integer, integer, integer, integer, integer` |
| PK unicas | 207792 |
| duplicados PK | 0 |
| faltantes requeridos | 0 |
| rango `year_id` | 1995-2030 |
| rango `age` | 0-110 |
| dominio `sex_id` | 8507, 8532 |
| dominio `location_id` | 0-25 |
| rango `population` | 0-319672 |
| MD5 parquet | `d9b4fdbb8d2654da19c9ec31c27dd395` |
| SHA-256 contenido ordenado por PK | `3e3e7d6d355dbca05a2a87bad0c28b9ec13ca081334cb5507717401ee3a65a87` |

Comparacion baseline vs post-cambio: todos los chequeos estructurales y de contenido coinciden (`all_match=TRUE`).

## QC y reporte

- `scripts/99_qc_global.R`: exito, run final `20260412_011530`.
- Iteracion final de QC contractual: exito, run `20260412_013747`.
- QC contractual final: 207792 filas, 5 columnas, 0 duplicados PK, 0 poblaciones negativas, 10 flags de monotonicidad de cola, 0 faltantes en comparacion nacional/departamentos y 2059 diferencias detectivas entre nacional oficial `0` y suma departamental.
- `scripts/99_qc_global_hierarchical.R`: exito, run final `20260412_011536`.
- Iteracion final de QC jerarquico: exito, run `20260412_013754`.
- QC jerarquico final: 207792 filas, 5 columnas, 0 columnas requeridas faltantes, 0 duplicados PK, 0 poblaciones negativas, contiene `location_id=9000` y no contiene `location_id=0`.
- `reports/method-report.qmd` renderizado correctamente a `reports/method-report.html`.
- `data/_catalog/provenance_runs.csv` registra los runs finales como `success`.

## Diccionarios

La cobertura se valida con `scripts/97_validate_dictionary_coverage.R`.

Tablas esperadas:

- staging: `download_log.csv`, `parse_log.csv`, `raw_long.parquet`, `omop_like_long.parquet`, `population_national_from_dept.parquet`;
- finales: `population_result.parquet`, `population_result_hierarchical.parquet`;
- QC y fingerprints: `contract_fingerprint_*`, `qc_*`, `qc_hierarchical_*`;
- catalogo: `catalogo_artefactos.csv`, `provenance_runs.csv`.

Los diccionarios se excluyen de la lista de tablas esperadas para evitar una recursion infinita de diccionarios de diccionarios.

Resultado final de cobertura:

- tablas validadas: 24;
- tablas sin diccionario o con cobertura incompleta: 0;
- `population_national_from_dept_diccionario_ext.csv` revisado: `population` esta descrita como conteo absoluto de poblacion y `location_id` como identificador de ubicacion `9000`.

## Compatibilidad downstream

Veredicto: compatibilidad preservada para el output contractual downstream.

No cambiaron:

- ruta;
- nombre de archivo;
- formato parquet;
- nombres de columnas;
- tipos de columnas;
- granularidad;
- dominios observados;
- unicidad de la llave logica;
- hash deterministico de contenido.

## Iteracion adicional 2026-04-14: cola demografica calibrada por mortalidad

Problema detectado en la iteracion previa:

- aunque la cola interna hasta 125 con tope `age=125 <= 1` habia mejorado casos pequenos, el contractual `110+` seguia siendo demasiado alto en Lima y en el nacional oficial `location_id=0`;
- la inspeccion visual del portal mostraba picos claramente inverosimiles en `age=110`.

Metodo implementado en esta iteracion:

- se reemplazo la plantilla Weibull por una schedule nacional Peru `80:125` por sexo y ano;
- la schedule se construye con `mx` de Peru en `wpp2019`, interpolado a anos calendario;
- la extension de edades altas `100:125` se hace con ajuste Kannisto `logit(mx) ~ age`;
- la schedule de mortalidad se convierte a pesos de supervivencia y esos pesos reparten exactamente la masa observada `80 y +` de cada estrato;
- el contractual conserva `0:109` y `age=110` como `110+`, con redondeo Hamilton para preservar la masa abierta observada.

Artefactos nuevos de trazabilidad:

- `data/derived/staging/inei_population/population_tail_external_benchmark_peru_80_125.parquet`
- `data/derived/qc/inei_population/qc_tail_external_alignment_national.csv`
- `data/derived/qc/inei_population/qc_tail_share_110plus.csv`
- `data/derived/qc/inei_population/qc_tail_visual_priority.csv`

Resultados clave de la iteracion:

- `qc_tail_mass_n_diff = 0`
- `qc_tail_cap_125_n_diff = 0`
- `qc_tail_external_alignment_n_diff = 0`
- `qc_110plus_collapse_n_diff = 0`
- `qc_tail_share_110plus_n_far = 0`

Chequeo puntual 2024 tras el cambio:

- Peru oficial `location_id=0`, `age=110`: `8` hombres y `26` mujeres;
- Lima `location_id=15`, `age=110`: `4` hombres y `11` mujeres;
- Apurimac `location_id=3`, `age=110`: `0` hombres y `0` mujeres.

Revision visual humana:

- las curvas de coherencia demografica ya no muestran el pico artificial en `110+` para Apurimac, Lima ni `9000`;
- los paneles de extrapolacion muestran continuidad de la cola interna y coincidencia visual entre benchmark nacional e interno esperado.

## Iteracion portal QC y coherencia demografica

Solicitud implementada: crear un portal HTML tecnico similar al de `mortalidad-causa-especifica`, con un modulo de QC del pipeline y otro modulo de coherencia demografica.

Nuevo artefacto principal:

- `reports/qc_demografia_poblacion/index.html`

Modulos generados:

- `reports/qc_demografia_poblacion/modules/pipeline-qc/index.html`
- `reports/qc_demografia_poblacion/modules/coherencia-demografica/index.html`

Metodo implementado:

- el portal es HTML estatico con CSS/JavaScript local;
- no se agregaron dependencias interactivas nuevas;
- las figuras se generan como PNG con `ggplot2`;
- la coherencia demografica usa como fuente principal `population_result_hierarchical.parquet`;
- el total nacional usado en coherencia es `location_id=9000`, porque es el nacional aditivo consistente con departamentos;
- el nacional oficial `location_id=0` se mantiene como contrato downstream y se revisa en el modulo QC.

Figuras generadas:

- 936 curvas principales de poblacion por edad simple, sexo, anio y region/total;
- 26 tendencias temporales auxiliares por region/total;
- 26 mapas edad-anio auxiliares por region/total;
- 2 figuras QC auxiliares.

Tablas nuevas con diccionario:

- `reports/qc_demografia_poblacion/downloads/qc_artifact_inventory.csv`
- `reports/qc_demografia_poblacion/downloads/coherence_curve_manifest.csv`
- `reports/qc_demografia_poblacion/downloads/coherence_trend_manifest.csv`
- `reports/qc_demografia_poblacion/downloads/coherence_heatmap_manifest.csv`
- `reports/qc_demografia_poblacion/downloads/portal_build_summary.csv`

Validacion de la iteracion:

- `scripts/95_build_qc_demografia_reports.R`: exito en el segundo intento.
- Primer intento fallido: el grafico QC nacional asumio una columna inexistente (`diff_official_minus_sum`); se corrigio para usar `diff_abs`.
- Primer intento fallido: el grafico de cola etaria asumio que el CSV de flags contenia edad y poblacion; se corrigio para reconstruir las curvas desde `population_result_hierarchical.parquet` para los estratos flagged.
- `scripts/97_validate_dictionary_coverage.R`: exito con 29 tablas validadas, incluyendo tablas del portal.
- `reports/method-report.qmd`: re-renderizado correctamente a HTML.
- Revision de enlaces locales del portal: 0 referencias rotas en `index.html`, modulo QC y modulo de coherencia.
- Revision de figuras: 990 PNG generados y 0 PNG vacios.
- Resumen de build del portal: `contract_ok=TRUE`, `hierarchical_ok=TRUE`, `dictionary_coverage_ok=TRUE`, `fingerprint_content_ok=TRUE`.

Comparacion contractual tras la iteracion del portal:

- `n_rows`: 207792 vs 207792;
- `n_cols`: 5 vs 5;
- columnas: `year_id|age|sex_id|location_id|population`;
- schema: `year_id:integer;age:integer;sex_id:integer;location_id:integer;population:integer`;

## Iteracion 2026-04-14: coherencia cruzada 110+ con mortalidad

Problema operativo identificado:

- podia existir un estrato con muertes observadas `110+` en SINADEF y poblacion contractual `110+ = 0` en este repo;
- esa situacion es incoherente para el uso downstream en mortalidad y carga de enfermedad;
- la solucion debia evitar una dependencia circular fuerte entre repos.

Cambio implementado:

- se agrego un input opcional `crossrepo_death_110plus_snapshot` en `config/runtime_paths.yml`;
- el snapshot esperado es agregado y no sensible: `death_110plus_summary.parquet`;
- si el snapshot existe y es valido, y un estrato tiene muertes observadas `110+` pero poblacion contractual `110+ = 0`, el contractual eleva `age=110` a `1`;
- el ajuste se registra como `coherence_floor_applied = TRUE` y `mass_adjustment_from_crossrepo_qc = +1`;
- si el snapshot no existe, el pipeline sigue en modo normal y reporta `skipped_no_snapshot`.

Artefactos nuevos:

- `data/derived/staging/inei_population/population_crossrepo_110plus_adjustment.parquet`
- `data/derived/qc/inei_population/qc_crossrepo_110plus_coherence.csv`
- `data/derived/qc/inei_population/qc_crossrepo_mass_adjustment.csv`

Portal y glosario:

- el tomo de extrapolacion ahora incluye una seccion "Coherencia cruzada mortalidad-demografia";
- se agregaron definiciones para `coherence_floor`, `cross-repo QC`, `death_110plus_summary` y `mass_adjustment_from_crossrepo_qc`.

Arquitectura recomendada:

- la coordinacion entre `tabla-mortalidad-peru`, `demografia-poblacion-inei` y `mortalidad-causa-especifica` debe vivir en un repo maestro externo;
- la reconciliacion cruzada se hace via snapshots publicados, no via llamadas directas entre repos.
- duplicados PK: 0 vs 0;
- faltantes requeridos: 0 vs 0;
- dominios de anio, edad, sexo y ubicacion: sin cambios;
- MD5 parquet: `d9b4fdbb8d2654da19c9ec31c27dd395`;
- SHA-256 de contenido ordenado: `3e3e7d6d355dbca05a2a87bad0c28b9ec13ca081334cb5507717401ee3a65a87`.

## Iteracion UX del modulo QC y glosario tecnico

Solicitud implementada: redisenar el modulo QC para que funcione como experiencia de revision, no solo como descarga tecnica.

Cambios implementados:

- el modulo QC se organizo en tomos HTML:
  - contrato downstream;
  - trazabilidad observado-final;
  - extrapolacion 80-110;
  - nacionalidad/aditividad;
  - diccionarios, catalogo, provenance y glosario;
- se agrego glosario tecnico local con tooltips/drawer para terminos como `PK`, `content_sha256`, `file_md5`, `location_id=0`, `location_id=9000`, `observed`, `final`, `extrapolated`, `diff_abs`, `flag_diff`, `n_tail_increase_flags` y `hierarchical`;
- cada tabla QC nueva incluye "Como leer esta tabla" y diccionario de columnas;
- se agregaron selectores por anio, region y sexo para la revision observado-final y extrapolacion;
- se agregaron selectores por anio y sexo para la revision nacional;
- se generaron tablas derivadas de revision:
  - `qc_observed_vs_final.csv`;
  - `qc_extrapolated_80_125.csv`;
  - `qc_national_modes.csv`;
  - `qc_glossary.csv`;
- se agregaron manifiestos y diccionarios para las tablas nuevas;
- se redujo ruido en la tabla de auditoria observado-final: los registros normalmente extrapolados quedan documentados y descargables, mientras que la vista de hallazgos se concentra en cambios observados inesperados o flags reales;
- el grafico nacional fue iterado tras inspeccion visual: se mantuvo la curva absoluta y se agrego un panel inferior de diferencia contra la suma departamental para que la discrepancia detectiva no quede oculta por la escala.

Validacion real ejecutada:

- `scripts/95_build_qc_demografia_reports.R`: exito tras dos renders completos de la iteracion UX;
- `scripts/97_validate_dictionary_coverage.R`: exito con 36 tablas validadas y cobertura exacta de columnas;
- revision de enlaces locales: 8 HTML, 0 referencias rotas;
- revision de figuras: 4806 PNG y 0 PNG vacios;
- revision de descargas: 40 CSV disponibles en el portal;
- revision de estructura HTML:
  - observado-final: 3 selectores, 1872 paneles filtrables, diccionario y guia de lectura;
  - extrapolacion: 3 selectores, 1872 paneles filtrables, diccionario y guia de lectura;
  - nacionalidad: 2 selectores, 72 paneles filtrables, diccionario y guia de lectura;
  - contrato: diccionarios, guia de lectura y links a fingerprints;
  - diccionarios-glosario: glosario y cobertura de diccionarios;
- inspeccion visual de muestras:
  - curva observado-final con edad en eje X y banda de edades extrapoladas 80-110;
  - curva de extrapolacion 80-110 con linea de inicio de extrapolacion y flags visibles;
  - curva nacional con panel de poblacion absoluta y panel de diferencia contra suma departamental.

Resumen de build final del portal:

- `run_id`: `portal-qc-demografia-20260412-192852`;
- filas contractuales: 207792;
- filas jerarquicas: 207792;
- curvas de coherencia demografica: 936;
- tendencias auxiliares: 26;
- mapas edad-anio auxiliares: 26;
- figuras observado-final QC: 1872;
- figuras extrapolacion QC: 1872;
- figuras nacionalidad QC: 72;
- `contract_ok=TRUE`;
- `hierarchical_ok=TRUE`;
- `dictionary_coverage_ok=TRUE`;
- `fingerprint_content_ok=TRUE`.

Veredicto de presentacion:

- el lector puede distinguir nacional oficial `0`, nacional aditivo `9000`, suma departamental, observado normalizado, final contractual y extrapolado 80-110;
- las diferencias entre nacional oficial y suma departamental se presentan como QC detectivo, no como ruptura contractual;
- los valores extrapolados quedan revisables por anio, region y sexo;
- los terminos y columnas nuevos tienen definicion dentro del portal.

## Ajuste final de portada QC

Se realizo una pasada adicional de UX sobre la portada del modulo QC para reducir falsas alarmas y ruido visual:

- la comparacion baseline vs post ahora separa `generated_at` como campo volatil y deja la tabla principal enfocada en compatibilidad estructural y de contenido;
- se agrego un bloque de prioridades con conteos accionables y enlaces directos a los tomos relevantes;
- la vista previa nacional en portada ahora muestra solo filas con diferencia detectiva;
- la vista previa de aditividad `9000` muestra explicitamente cuando no hay filas discrepantes.

Validacion posterior al ajuste:

- portal regenerado con `run_id=portal-qc-demografia-20260412-210950`;
- enlaces locales rotos: 0;
- PNG vacios: 0;
- fingerprint contractual post recalculado sin cambios en `file_md5` ni `content_sha256`.

## Iteracion 2026-04-13: cola interna 0-125 y export contractual con 110+

Esta iteracion reemplaza el criterio anterior de "contenido identico" por un criterio coordinado y documentado de cambio semantico controlado:

- el modelamiento interno ahora llega a `age=125`;
- el output contractual mantiene la misma ruta, nombre, columnas, tipos y granularidad;
- el output contractual exporta `age=0:109` como edades simples;
- el output contractual exporta `age=110` como grupo abierto `110+`;
- `population(age=110)` se construye como la suma exacta de toda la masa interna con `age >= 110`.

### Cambios implementados

- `scripts/02_normaliza_long_omop.R`: el grupo observado `80 y +` deja de cerrarse artificialmente en `110`; ahora queda trazado como grupo abierto con `age_group_open`.
- `scripts/03_extrapola_80_110.R`: genera primero un artefacto interno reproducible `population_modeled_internal_0_125.parquet`, construye un bridge contractual `population_tail_contract_bridge_80_109_110plus.parquet` con redondeo Hamilton y luego colapsa `110:125` en la fila contractual `age=110`.
- `scripts/99_qc_global.R`: agrega `qc_110plus_collapse_exact.csv` y falla si `110+ final != suma interna >=110`.
- `config/spec_population_inei.yml` y `config/spec_population_inei_hierarchical.yml`: documentan la nueva semantica contractual de `age=110`.
- `docs/DATA_CONTRACT.md`, `README.qmd`, `reports/method-report.qmd` y el portal QC: actualizados para dejar explicito que `age=110` significa `110+`.

### Evidencia de ejecucion

- Pipeline principal ejecutado completo el `2026-04-13`.
- QC contractual ejecutado correctamente (`run_id=20260413_145355`).
- QC jerarquico ejecutado correctamente (`run_id=20260413_145402`).
- `scripts/96_generate_table_dictionaries.R`: exito.
- `scripts/97_validate_dictionary_coverage.R`: exito con `40` tablas validadas y `0` fallas.
- `scripts/95_build_qc_demografia_reports.R`: exito final con `run_id=portal-qc-demografia-20260413-162433`.
- `quarto render reports/method-report.qmd`: exito, HTML actualizado.

### Fingerprint estructural y de contenido

Baseline pre-cambio semantico:

- `file_md5 = d9b4fdbb8d2654da19c9ec31c27dd395`
- `content_sha256 = 3e3e7d6d355dbca05a2a87bad0c28b9ec13ca081334cb5507717401ee3a65a87`

Post-cambio semantico:

- `file_md5 = 326554f8883e46f2b4a6c75b3072c716`
- `content_sha256 = 6fcea37dd81609f0d2d0a9097fedf18ee2a44c596268c2440c92d50c90a104fb`

Chequeos estructurales preservados:

- ruta contractual: sin cambios;
- archivo contractual: sin cambios;
- columnas: `year_id, age, sex_id, location_id, population`;
- tipos: `integer` en las 5 columnas;
- filas: `207792`;
- PK duplicada: `0`;
- faltantes requeridos: `0`;
- dominio de `year_id`: `1995-2030`;
- dominio contractual de `age`: `0-110`;
- dominio de `sex_id`: `8507, 8532`;
- dominio de `location_id`: `0-25`;
- rango observado de `population`: `0-319672`.

Interpretacion:

- la compatibilidad estructural downstream se preserva;
- el cambio de `file_md5` y `content_sha256` es esperado y deseado, porque `age=110` ya no representa "110 exactos" sino `110+`.

### QC de cola 80+ y colapso 110+

Nuevos artefactos:

- `data/derived/qc/inei_population/qc_tail_mass_80plus_exact.csv`
- `data/derived/qc/inei_population/qc_tail_cap_125_national.csv`
- `data/derived/qc/inei_population/qc_110plus_collapse_exact.csv`

Resultado:

- `sum(internal 80:125) == observed 80 y +`: `0` discrepancias;
- `age=125` nacional por `year_id x sex_id` siempre `<= 1.0`;
- filas evaluadas: `1872`;
- `diff != 0`: `0`;
- veredicto: en todos los estratos `year_id x sex_id x location_id`, la fila contractual `age=110` coincide exactamente con el bridge contractual `110+`, y ese bridge preserva exactamente la masa observada `80 y +`.

### Estado final del portal y reporte

- portal principal: `reports/qc_demografia_poblacion/index.html`
- tomo de contrato: `reports/qc_demografia_poblacion/modules/pipeline-qc/tomos/contrato.html`
- tomo de cola interna y colapso: `reports/qc_demografia_poblacion/modules/pipeline-qc/tomos/extrapolacion.html`
- reporte metodologico: `reports/method-report.html`

Resumen del portal final:

- `dictionary_coverage_ok = TRUE`
- `fingerprint_structure_ok = TRUE`
- `fingerprint_content_match = FALSE` (esperado por el cambio semantico 110+)
- `qc_110plus_collapse_figures = 1`
- `qc_extrapolation_figures = 1872`
- `qc_observed_final_figures = 1872`
- `qc_national_figures = 72`

### Veredicto de esta iteracion

Se implemento correctamente la separacion entre cola interna modelada y export contractual:

- internamente: `0:125`;
- contractualmente: `0:109 + 110+`.

La estructura downstream se mantuvo estable y la nueva semantica quedo trazable, documentada y demostrada con QC exacto.

### Observacion metodologica abierta

La iteracion actual corrige el problema mas grave de explosiones extremas en departamentos pequenos, pero no elimina por completo la sensacion de cola alta en el nacional oficial `location_id=0` y en departamentos con mucha masa `80 y +`.

Evidencia puntual revisada:

- Apurimac 2024 ya no muestra miles en `110+`; quedo en `14` hombres y `20` mujeres.
- El tope nacional interno a `age=125` se cumple (`<= 1.0` por sexo-anio).
- Aun asi, el nacional oficial contractual `age=110` sigue acumulando mucha masa porque representa todo `110:125` despues de redistribuir la masa observada `80 y +`.

Interpretacion:

- esta iteracion deja la cola mucho mas coherente que la version spline libre anterior;
- pero el nivel absoluto de `110+` en el nacional oficial todavia puede resultar alto para lectura sustantiva;
- si se desea una cola mas agresivamente protegida contra sobrepoblacion extrema, la siguiente iteracion metodologica deberia agregar una restriccion adicional sobre la masa total `110+`, no solo sobre `age=125`.

## Iteracion 2026-04-14: benchmark oficial `all_years` desde `tabla-mortalidad-peru`

Despues de una nueva revision del repo hermano `tabla-mortalidad-peru`, se verifico que ya existe la familia:

- `data/final/life_table_mortality/all_years/single_age/ref_life_table_mortality_single_age.csv`

Cobertura real observada:

- `year_id = 1995:2025`
- `location_id = 1:25`
- `sex_id = 8507, 8532`
- `age = 0:110`, con `110` como grupo abierto `110+`

No se encontro una fila nacional `location_id = 0` en esa familia `all_years`.

### Cambio metodologico implementado

Se reemplazo el benchmark previo basado solo en Peru/WPP por una jerarquia hibrida:

1. `location_id = 1:25`, `year_id = 1995:2025`:
   - benchmark principal desde la tabla de vida oficial regional `all_years`;
2. `location_id = 0`, `year_id = 1995:2025`:
   - benchmark nacional implicito agregado desde las 25 regiones oficiales, ponderado por la masa observada `80 y +` del propio repo;
3. `year_id = 2026:2030`:
   - fallback explicito Peru/WPP con extension Kannisto.

La semantica contractual se mantuvo:

- interno: `80:125`;
- contractual: `0:109 + age=110` como `110+`.

### Archivos ajustados

- `R/tail_model_utils.R`
- `scripts/03_extrapola_80_110.R`
- `R/qc_utils.R`
- `scripts/99_qc_global.R`
- `scripts/95_build_qc_demografia_reports.R`
- `config/spec_population_inei.yml`
- `config/spec_population_inei_hierarchical.yml`
- `reports/method-report.qmd`

### Nuevos QC reforzados

Se mantuvieron los QC de masa exacta y colapso exacto, y se reforzaron los de benchmark:

- `qc_tail_external_alignment_national.csv`
- `qc_tail_share_110plus.csv`
- `qc_tail_visual_priority.csv`
- `qc_tail_benchmark_source_by_stratum.csv`

Resultado resumido:

- `qc_tail_mass_n_diff = 0`
- `qc_tail_cap_125_n_diff = 0`
- `qc_tail_external_alignment_n_diff = 0`
- `qc_tail_share_110plus_n_far = 0`
- `qc_110plus_collapse_n_diff = 0`
- `qc_tail_benchmark_source_n_strata = 1872`

Distribucion real de fuentes efectivas:

- `official_life_table_all_years_regional`: `1550` estratos
- `implicit_national_from_official_regions`: `62` estratos
- `wpp_peru_fallback_2026_2030`: `260` estratos

Esto confirma que:

- las regiones `1:25` usan benchmark oficial `1995:2025`;
- el nacional oficial `0` usa benchmark implicito agregado `1995:2025`;
- el fallback WPP queda restringido a `2026:2030`.

### Revision numerica puntual

Chequeo `2024`:

- Apurimac `location_id = 3`:
  - hombres `110+ = 0`
  - mujeres `110+ = 0`
- Lima `location_id = 15`:
  - hombres `110+ = 43`
  - mujeres `110+ = 48`
- Peru oficial `location_id = 0`:
  - hombres `110+ = 75`
  - mujeres `110+ = 120`

Estos valores reemplazan la iteracion previa en la que Lima y el nacional oficial aun retenian una cola `110+` demasiado pesada.

### Revision visual humana

Se revisaron explicitamente los paneles:

- Apurimac 2024
- Lima 2024
- Peru oficial 2024

Hallazgos visuales:

- Apurimac ya no presenta el spike grotesco en `110+`;
- Lima muestra una cola decreciente y un `110+` pequeno respecto a la masa `80+`;
- Peru oficial mantiene continuidad visual entre la cola interna `80:125` y el truncamiento contractual `110+`;
- el subtitulo del portal identifica la fuente efectiva del benchmark de cada estrato.

### Estado final de ejecucion

Ejecucion realizada:

1. pipeline principal completo;
2. `scripts/99_qc_global.R`;
3. `scripts/99_qc_global_hierarchical.R`;
4. `scripts/95_build_qc_demografia_reports.R`;
5. `scripts/97_validate_dictionary_coverage.R`;
6. `quarto render reports/method-report.qmd`;
7. fingerprint post contractual.

Resultado:

- compatibilidad contractual estructural preservada;
- portal QC regenerado;
- cobertura de diccionarios validada sin fallas;
- HTML y figuras consistentes con el metodo realmente implementado.

### Veredicto de esta iteracion

Esta iteracion cierra la correccion metodologica principal de la cola alta:

- sustituye el benchmark libre o puramente WPP por la mejor evidencia oficial regional disponible dentro del ecosistema del proyecto;
- mantiene un fallback explicito y acotado solo donde realmente falta cobertura oficial;
- deja trazabilidad completa de la fuente efectiva por estrato;
- mejora tanto los resultados numericos como la lectura visual de la cola `110+`.

## Iteracion 2026-04-14: exclusion explicita de la fila abierta 110+ de mortalidad

### Diagnostico

Se reviso el repo hermano `tabla-mortalidad-peru` para resolver el riesgo de circularidad semantica:

- no se encontro una tautologia dura de generacion; las referencias a `demografia-poblacion-inei` aparecen como QC externo y no como input de construccion del output `single_age`;
- si existia un riesgo metodologico real en este repo: se estaba tratando la fila abierta `110+` de la tabla de vida `all_years/single_age` como si fuera un nodo cerrado util para el benchmark de cola.

### Correccion implementada

- `R/tail_model_utils.R`: el benchmark oficial ahora usa solo edades cerradas `80:109`;
- la fila abierta `110+` se excluye explicitamente con `age_interval_open == FALSE`;
- la extension interna `110:125` se genera solo con Kannisto ajustado sobre edades cerradas `95:109`;
- el benchmark nacional implicito `location_id=0` agrega solo plantillas regionales ya corregidas, sin reutilizar `110+` abierto.

### QC nuevo de desacople

Se agrego `qc_tail_open_interval_exclusion.csv`, con una fila por `year_id x sex_id x location_id`, para registrar:

- `benchmark_source`
- `used_open_110plus_row`
- `fit_age_min`
- `fit_age_max`

Regla de aceptacion:

- `used_open_110plus_row` debe ser siempre `FALSE`.

### Lectura metodologica resultante

El flujo entre repos queda asi:

1. `tabla-mortalidad-peru` produce su output contractual `single_age` con cierre en `110+`;
2. `demografia-poblacion-inei` consume solo el tramo cerrado `80:109` como benchmark oficial;
3. `demografia-poblacion-inei` reabre y modela por su cuenta `110:125`;
4. la fila abierta `110+` de mortalidad se conserva solo como contexto/QC y no participa en el modelamiento.

### Veredicto de la iteracion

La correccion elimina la contaminacion metodologica detectada sin romper el contrato downstream ni introducir una nueva dependencia circular entre repos.

### Evidencia de ejecucion real

Ejecucion realizada en esta iteracion:

1. `scripts/01_ingesta_raw_inei.R`
2. `scripts/02_normaliza_long_omop.R`
3. `scripts/03_extrapola_80_110.R`
4. `scripts/04_build_national_from_dept.R`
5. `scripts/05_build_population_view_hierarchical.R`
6. `scripts/99_qc_global.R`
7. `scripts/99_qc_global_hierarchical.R`
8. `scripts/98_contract_fingerprint.R`
9. `scripts/95_build_qc_demografia_reports.R`
10. `scripts/97_validate_dictionary_coverage.R`
11. `quarto render reports/method-report.qmd`

Resultados clave:

- `qc_tail_open_interval_exclusion_n_diff = 0`
- `qc_tail_external_alignment_n_diff = 0`
- `qc_tail_mass_n_diff = 0`
- `qc_110plus_collapse_n_diff = 0`
- `dictionary_coverage_ok = TRUE` en el portal final
- fingerprint post estructural compatible con `207792` filas, mismas 5 columnas y tipos enteros

Distribucion de fuentes efectivas por estrato:

- `official_life_table_all_years_regional`: `1550`
- `implicit_national_from_official_regions`: `62`
- `wpp_peru_fallback_2026_2030`: `260`

El QC nuevo de exclusion confirma:

- en benchmark oficial regional e implicito nacional, `used_open_110plus_row = FALSE` en todos los estratos;
- `benchmark_observed_age_max = 109`
- `fit_age_min = 95`
- `fit_age_max = 109`

## Iteracion 2026-04-16: repo autocontenido, portal UX y corrida limpia final

### Cambios implementados

- se desacoplo el benchmark alto de `tabla-mortalidad-peru` como dependencia runtime y se materializo localmente en `data/raw/external_benchmarks/peru_life_table_all_years_closed_80_109.csv`;
- se agrego `scripts/refresh_external_benchmarks.R` para refrescar ese benchmark local de forma explicita, no implicita;
- el build base dejo de autodetectar snapshots cross-repo por rutas relativas vecinas; `death_110plus_summary` solo se activa si la ruta se declara en `config/runtime_paths.yml` o en `DPG_CROSSREPO_DEATH_110PLUS_SNAPSHOT`;
- se adopto una arquitectura reproducible inspirada en `tabla-vida-estandar` con:
  - `config/pipeline_steps.csv`
  - `config/pipeline_profiles.yml`
  - `scripts/run_preflight_checks.R`
  - `scripts/clean_regenerable_outputs.R`
  - `scripts/run_pipeline.R`
- se incorporaron maestros propios adaptados para UX cientifico, release minimo y operacion:
  - `maestros/diseno/01_MASTER_PORTAL_UX_CIENTIFICO.md`
  - `docs/operations_manual.md`
  - `docs/repo_minimal_release_manifest.md`
- se rediseño el portal para:
  - separar portada, tomos QC y coherencia;
  - mostrar anexo metodologico como acceso primario;
  - mejorar scroll horizontal de tablas;
  - incluir glosario/tooltip de terminos;
  - permitir lectura plegable de diccionarios;
  - hacer mas legible el grafico de cola interna `80:125` y el punto contractual `110+`.

### Corrida limpia final

Entry point ejecutado:

1. `Rscript .\\scripts\\run_preflight_checks.R`
2. `Rscript .\\scripts\\run_pipeline.R --profile full --clean-first`

Estado final del log:

- `12/12` pasos exitosos en `data/derived/qc/run_pipeline/pipeline_run_log.csv`
- reporte metodologico HTML renderizado en `reports/method-report.html`
- portal QC renderizado en `reports/qc_demografia_poblacion/index.html`

### Resultado contractual final

Fingerprint post de la corrida limpia final:

- `n_rows = 207792`
- `n_cols = 5`
- columnas: `year_id|age|sex_id|location_id|population`
- schema: `year_id:integer;age:integer;sex_id:integer;location_id:integer;population:integer`
- `pk_duplicate_n = 0`
- `required_missing_n = 0`
- `year_range = 1995|2030`
- `age_range = 0|110`
- `sex_domain = 8507|8532`
- `location_domain = 0|1|2|...|25`
- `population_range = 0|319672`
- `file_md5 = a16f97f3e1bb2dc1f7a2a8a588369fbd`
- `content_sha256 = 761ab7d014948bb144d1ea7c3ba725bfb9514e94c2142cb2e9f676a0a4bf8184`

### Compatibilidad y baseline vs post

La corrida limpia final preserva el contrato estructural downstream:

- mismo path final `data/final/population_inei/population_result.parquet`;
- mismo nombre;
- mismas 5 columnas;
- mismos tipos enteros;
- misma granularidad logica;
- misma semantica contractual vigente (`age = 110` representa `110+`).

En esta iteracion de autocontenimiento no se regenero un baseline local dentro de `data/derived/qc/` antes de la limpieza segura; por eso el portal marca la comparacion baseline/post como `NO DISPONIBLE`, no como fallo. La referencia previa a esta corrida seguia mostrando el mismo contrato estructural (`207792` filas, mismas columnas, mismos tipos, PK unica, sin faltantes requeridos), por lo que el cambio de contenido observado aqui corresponde al rerun limpio del metodo vigente y no a una ruptura estructural del contrato.

### QC y lectura visual final

Resumen QC final de la corrida limpia:

- `qc_tail_mass_n_diff = 0`
- `qc_tail_cap_125_n_diff = 0`
- `qc_tail_external_alignment_n_diff = 0`
- `qc_tail_share_110plus_n_far = 0`
- `qc_tail_open_interval_exclusion_n_diff = 0`
- `qc_110plus_collapse_n_diff = 0`
- `qc_crossrepo_110plus_n_incoherent = 0`
- `qc_crossrepo_110plus_n_floor_applied = 0`
- `qc_crossrepo_110plus_mass_added = 0`

La ultima corrida limpia fue deliberadamente autocontenida, sin snapshot cross-repo configurado. Eso confirma que el repo ya puede construir su contractual base sin depender runtime de `mortalidad-causa-especifica`.

Revision visual humana posterior a la corrida limpia:

- Apurimac 2024 contractual: cola sin spike terminal y `110+` pegado a cero;
- Lima 2024 contractual: cola suave y decreciente, sin salto artificial en `110+`;
- Peru total `9000` 2024: continuidad razonable de la cola final;
- Lima 2024 cola interna: subtitulo abreviado, benchmark legible y punto `110+` contractual destacado visualmente.

### Politica de release minimo

La frontera de publicacion queda asi:

- versionar codigo, `config/`, `docs/`, `maestros/`, raw publico INEI, benchmark local desacoplado y artefactos editoriales publicables;
- ignorar outputs tabulares regenerables pesados (`data/final/`, `data/derived/`, staging, snapshots temporales y debugging local);
- permitir que el repo local conserve historicos fuera del flujo, pero sin que GitHub ni el pipeline dependan de ellos.

### Revision numerica puntual de 110+

Chequeo contractual `age = 110`:

- `1995`: Apurimac `0/0`, Lima `0/0`, Peru oficial `0/0`
- `2024`: Apurimac `0/0`, Lima `43/48`, Peru oficial `76/120`
- `2025`: Apurimac `0/0`, Lima `49/56`, Peru oficial `84/136`
- `2030`: Apurimac `0/0`, Lima `2/7`, Peru oficial `5/17`

El formato es `hombres/mujeres`.

### Revision visual humana

Se revisaron explicitamente los paneles:

- Apurimac 2024, sexo femenino
- Lima 2024, sexo femenino
- Peru oficial 2024, sexo femenino
- Lima 1995, sexo femenino
- Lima 2030, sexo femenino

Hallazgos visuales:

- no aparece un spike artificial en `110+`;
- la cola interna `80:125` es decreciente y continua;
- el benchmark efectivo y el interno esperado quedan practicamente superpuestos;
- el truncamiento contractual en `110+` luce coherente con la masa interna `110:125`;
- el caso fallback `2030` mantiene continuidad visual y no reintroduce el problema que motivó la iteracion.
