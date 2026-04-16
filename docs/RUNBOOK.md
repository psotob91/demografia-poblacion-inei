# RUNBOOK

## Goal

This document explains how to execute, validate, and debug the repository.

## Recommended execution order

Official base entrypoint:

1. `scripts/run_preflight_checks.R`
2. `scripts/run_pipeline.R --profile full --clean-first`

Canonical step order inside the pipeline:

1. `scripts/01_ingesta_raw_inei.R`
2. `scripts/02_normaliza_long_omop.R`
3. `scripts/03_extrapola_80_110.R`
4. `scripts/04_build_national_from_dept.R`
5. `scripts/05_build_population_view_hierarchical.R`
6. `scripts/99_qc_global.R`
7. `scripts/99_qc_global_hierarchical.R`
8. `scripts/96_generate_table_dictionaries.R`
9. `scripts/97_validate_dictionary_coverage.R`
10. `scripts/98_contract_fingerprint_post.R`
11. `scripts/94_render_method_report.R`
12. `scripts/95_build_qc_demografia_reports.R`

## Pre-run checks

Before running:
- confirm working directory is repository root;
- confirm required packages are installed;
- confirm raw INEI files exist in the expected raw folder;
- confirm the local benchmark `data/raw/external_benchmarks/peru_life_table_all_years_closed_80_109.csv` exists;
- confirm config masters and YAML specs are present;
- confirm write permissions for staging, final, QC, and reports folders.

## Baseline before changes

Before modifying code:
1. identify contractual final output;
2. save a copy or snapshot of it;
3. record:
   - schema
   - types
   - row count
   - key uniqueness
   - basic ranges
   - checksum/fingerprint

## Standard execution

Run scripts in the official order from repository root.

The repo is now expected to use `run_pipeline.R` as its preferred entry point.

## Post-run validation

After running:
- verify final contractual output exists;
- verify schema and types;
- verify QC outputs were generated;
- compare post-run output against baseline if this was a refactor or audit task;
- verify report rendering if applicable.

## Optional cross-repo coherence pass

If a valid mortality snapshot exists at the explicitly configured path for `crossrepo_death_110plus_snapshot` or `DPG_CROSSREPO_DEATH_110PLUS_SNAPSHOT`, the demography pipeline performs an additional contractual guard-rail for `110+`. The base build does not auto-discover sibling repositories anymore.

Recommended order in a multi-repo execution:

1. optionally refresh the local benchmark from `tabla-mortalidad-peru`
2. run `demografia-poblacion-inei` base
3. run `mortalidad-causa-especifica`
4. export `death_110plus_summary.parquet`
5. rerun `demografia-poblacion-inei` from the tail-building step onward
6. rerun only downstream mortality steps that consume final population

If the snapshot is absent, demography runs normally and must report `crossrepo_110plus_qc = skipped_no_snapshot`.

## Report rendering

If a Quarto report is added for audit/methodological output, render it after pipeline execution and confirm:
- HTML exists;
- key tables and figures render correctly;
- no broken paths;
- mermaid diagrams render.

## Debugging priorities

If execution fails, debug in this order:
1. file paths
2. raw input availability
3. package/dependency issues
4. malformed Excel parsing
5. config/spec mismatches
6. downstream write failures
7. report rendering issues

## Docker guidance

The repo should support either:
- data stored within the repository, or
- data mounted from an external volume.

If Docker assets are added later, document:
- build command
- run command
- mounted volumes
- environment variables
- expected root paths

## Minimum evidence for completion of an audit task

A task is not complete unless it includes:
- summary of files changed;
- confirmation that final contractual output still exists;
- baseline vs post-change comparison;
- QC status;
- report rendering status.
