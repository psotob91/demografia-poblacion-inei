# Manifiesto de version minima final para GitHub

## Objetivo

Este documento define la version minima final que debe subirse a GitHub para que una persona analista pueda clonar el repo, correr el pipeline base desde cero y obtener el contractual, QC y reportes sin depender runtime de repos hermanos.

## Debe quedar en GitHub

- `AGENTS.md`
- `README.md`
- `README.qmd`
- `R/`
- `scripts/`
- `config/`
- `docs/`
- `maestros/`
- `reports/*.qmd`
- `data/raw/inei_population/`
- `data/raw/external_benchmarks/`
- `.gitignore`
- `renv.lock`

## No debe quedar en GitHub

- `data/final/`
- `data/derived/`
- `outputs/`
- `reports/method-report.html`
- `reports/qc_demografia_poblacion/`
- `reports/*_files/`
- snapshots locales de baseline
- backups humanos locales
- archivos de debugging puntual no regenerables

## Regla operativa

Un archivo solo debe quedar si sirve al menos para una de estas tres funciones:

1. ejecutar el pipeline
2. entender o auditar el metodo
3. sostener continuidad con una persona analista o con un agente

## Regla para los HTML regenerables

Los HTML del anexo metodologico y del portal QC son entregables importantes, pero no se versionan en GitHub. Deben reconstruirse en cada corrida oficial del perfil `full` y verificarse visualmente antes de un release.
