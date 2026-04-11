# MASTERS_GOVERNANCE

## Purpose

This document defines which files are normative for execution, which are contextual, and which should be archived.

## Principle

Codex and future maintainers should not have to infer project truth from many overlapping narrative files.

The repository should distinguish clearly between:
1. normative operational files;
2. technical documentation files;
3. legacy narrative files.

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

## Rule for future additions

Any new “master” should only be added if it is clearly one of:
- execution norm;
- data contract;
- runbook;
- project context;
- methodological debt log.

Avoid creating multiple overlapping instruction files.