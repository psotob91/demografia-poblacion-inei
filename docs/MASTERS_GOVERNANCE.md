# MASTERS_GOVERNANCE

## Purpose

This document defines which files are normative for execution, which are contextual, and which should be archived.

## Principle

Codex and future maintainers should not have to infer project truth from many overlapping narrative files.

The repository should distinguish clearly between:
1. normative operational files;
2. technical documentation files;
3. continuity and UX masters;
4. legacy narrative files.

## Normative operational files

These should drive execution and validation:

- `config/`
  - mapping masters
  - YAML specs
  - project parameters
- `R/`
  - reusable utility functions
- `scripts/`
  - executable pipeline logic
- `data/final/`
  - contractual outputs
- `data/_catalog/`
  - provenance and artifact metadata
- `maestros/`
  - continuity and UX masters that govern the final portal/release behavior

## Normative documentation files

These should guide agents and maintainers:

- `AGENTS.md`
- `docs/PROJECT_CONTEXT.md`
- `docs/DATA_CONTRACT.md`
- `docs/RUNBOOK.md`
- `docs/MASTERS_GOVERNANCE.md`

## Legacy/contextual files

Narrative or historical files that may contain useful context but should not govern execution belong in:

`docs/archive/masters_legacy/`

Examples:
- prior scope statements
- writing-only masters
- historical terminology notes
- draft discrepancy logs
- roadmap notes

## Decision rules for old masters

### Keep and migrate
Keep the information if it helps explain:
- real methodological decisions;
- important terminology;
- output semantics;
- known divergences between documentation and code;
- technical debt and future roadmap.

### Archive
Archive files whose content is useful historically but should not act as live instructions.

### Delete
Delete only files that are fully redundant, clearly obsolete, and preserved elsewhere.

## Recommended handling of current legacy masters

Suggested approach:
- move legacy `.txt` masters into `docs/archive/masters_legacy/`;
- preserve history;
- rewrite only the normative docs above as the active instruction set.

## Current consolidation status

As of the 2026-04-12 audit/refactor, active `MASTER_*` files at the top of `docs/` are treated as legacy/contextual and should not govern execution. Their historical copies live under `docs/archive/masters_legacy/`.

Current normative guidance remains limited to:
- `AGENTS.md`
- `docs/PROJECT_CONTEXT.md`
- `docs/DATA_CONTRACT.md`
- `docs/RUNBOOK.md`
- `docs/MASTERS_GOVERNANCE.md`
- `docs/operations_manual.md`
- `docs/repo_minimal_release_manifest.md`
- `maestros/diseno/01_MASTER_PORTAL_UX_CIENTIFICO.md`

Future master-like additions should be proposed first as recommendations in the technical report or audit notes. They should become operational only if implemented as explicit config/spec/data-dictionary artifacts and validated without changing the contractual final output.

Recommended future masters/config additions:
- explicit INEI sheet-to-sex mapping;
- age and age-group reference table for downstream aggregation;
- dictionaries for `raw_long.parquet` and `omop_like_long.parquet`;
- methodological debt log separated from execution instructions.

## Rule for future additions

Any new “master” should only be added if it is clearly one of:
- execution norm;
- data contract;
- runbook;
- project context;
- methodological debt log.

Avoid creating multiple overlapping instruction files.
