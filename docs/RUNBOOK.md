# RUNBOOK

## Goal

This document explains how to execute, validate, and debug the repository.

## Recommended execution order

Current expected script order:

1. `scripts/01_ingesta_raw_inei.R`
2. `scripts/02_normaliza_long_omop.R`
3. `scripts/03_extrapola_80_110.R`
4. `scripts/04_build_national_from_dept.R`
5. `scripts/05_build_population_view_hierarchical.R`
6. `scripts/99_qc_global.R`
7. `scripts/99_qc_global_hierarchical.R`

## Pre-run checks

Before running:
- confirm working directory is repository root;
- confirm required packages are installed;
- confirm raw INEI files exist in the expected raw folder;
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

If a master script is later created, it should become the preferred entry point and this document should be updated.

## Post-run validation

After running:
- verify final contractual output exists;
- verify schema and types;
- verify QC outputs were generated;
- compare post-run output against baseline if this was a refactor or audit task;
- verify report rendering if applicable.

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