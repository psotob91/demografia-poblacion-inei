# Manual de operaciones

## Para que sirve

Este manual esta pensado para una persona que quiere clonar el repo, correrlo desde cero y obtener los mismos outputs contractuales, QC y reportes sin depender de un repo vecino durante el build base.

Los HTML generados del anexo metodologico y del portal QC forman parte de la verificacion operativa, pero no se versionan en GitHub dentro del release minimo. Se regeneran en cada corrida `full`.

## Secuencia oficial

```powershell
Rscript .\scripts\run_preflight_checks.R
Rscript .\scripts\run_pipeline.R --profile full --clean-first
```

## Perfiles de corrida

- `full`: pipeline completo, QC, anexo y portal
- `core`: construccion contractual y QC bloqueante
- `reports`: solo anexo metodologico y portal

## Entry points oficiales

- `scripts/refresh_external_benchmarks.R`: refresca el benchmark local desde `tabla-mortalidad-peru` cuando se quiere actualizar esa copia desacoplada
- `scripts/run_preflight_checks.R`: valida prerequisitos locales
- `scripts/clean_regenerable_outputs.R`: limpia solo regenerables
- `scripts/run_pipeline.R`: orquesta la corrida oficial del repo

## Politica de benchmark

- el build base consume `data/raw/external_benchmarks/peru_life_table_all_years_closed_80_109.csv`;
- ese benchmark local usa solo edades cerradas `80:109`;
- la fila abierta `110+` de mortalidad no se usa como input de modelamiento;
- `110:125` se reconstruye internamente con Kannisto sobre `95:109`.

## Integracion opcional cross-repo

Si existe un snapshot valido configurado en `config/runtime_paths.yml` para `crossrepo_death_110plus_snapshot`, el repo aplica el piso contractual minimo `110+ -> 1` cuando hay muertes observadas `110+` y la poblacion contractual habria quedado en cero.

Si el snapshot no existe, el build base sigue siendo valido y debe reportar `skipped_no_snapshot`.
