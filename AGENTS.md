# AGENTS.md

## Scope
This file governs the whole repository unless a deeper AGENTS.md overrides it.

## Repository purpose
This repository builds the canonical demographic population dataset used downstream by burden-of-disease pipelines, especially `mortalidad-causa-especifica`.

## Critical invariant: do not break downstream compatibility
The contractual final output must not be broken.

Preserve strictly:
- output path;
- file name;
- column names;
- column types;
- row-level granularity;
- semantic meaning of fields;
- any assumptions required by downstream consumers.

If you identify a better design that would break compatibility, implement it only as an additional versioned output or document it as a future recommendation.

## Files to read first
Before making changes, read:
- `README.qmd`
- `docs/PROJECT_CONTEXT.md`
- `docs/DATA_CONTRACT.md`
- `docs/RUNBOOK.md`
- `docs/MASTERS_GOVERNANCE.md`

## Working style
- Prefer small, verifiable changes.
- Describe the real implemented method, not an idealized one.
- Be explicit about uncertainty.
- Prioritize reproducibility, auditability, and data-contract stability.
- Do not silently change the statistical meaning of outputs.

## Required workflow
1. Inspect repository structure and execution flow.
2. Identify the contractual final output and baseline it.
3. Save pre-change fingerprints:
   - schema
   - types
   - row count
   - key uniqueness
   - basic domain/range checks
   - file checksum if possible
4. Make changes.
5. Re-run the pipeline.
6. Compare baseline vs post-change output.
7. Report whether compatibility was preserved.

## Validation requirements
Best effort run all relevant checks after changes:
- pipeline execution
- QC scripts
- report rendering
- schema comparison
- baseline vs post-change comparison

## Documentation requirements
Keep or create:
- code comments only where they add meaning
- pseudocode sections in the report
- data dictionaries for final and important intermediate tables
- deployment/run instructions

## Preferred deliverables
- a main HTML report
- updated repo docs
- explicit baseline-vs-post comparison
- clear inventory of masters/config/specs
- recommendations separated from implemented changes

## Files and folders
Treat these as normative unless evidence shows otherwise:
- `config/`
- `R/`
- `scripts/`
- `data/final/`
- `data/_catalog/`

Treat legacy narrative files under `docs/archive/masters_legacy/` or older notes as contextual, not normative.