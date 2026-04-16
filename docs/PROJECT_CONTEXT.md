# PROJECT_CONTEXT

## Purpose

`demografia-poblacion-inei` is the upstream demographic component that builds the canonical population denominator used by downstream epidemiologic and burden-of-disease pipelines.

Its role is not to produce a novel demographic projection system. Its role is to transform public INEI inputs into an analytic population dataset that is reproducible, structured, traceable, and stable for downstream consumption.

## Downstream role

This repository is consumed by `mortalidad-causa-especifica` and possibly other burden pipelines. Therefore, output stability is a first-order requirement.

The final contractual output must remain stable in:
- path
- filename
- schema
- types
- logical grain
- semantic interpretation

## Current repository behavior to prioritize

Documentation and audit work must prioritize:
1. what the scripts actually do;
2. what the specs/YAML actually enforce;
3. what the final outputs actually contain.

If README, methodological drafts, or older masters differ from the implemented code, the implemented code should be treated as the source of truth for technical documentation, while differences should be documented explicitly.

## Methodological stance

When documenting methods:
- describe the real implemented workflow;
- distinguish observed data from modeled or extrapolated data;
- document practical conventions and local mappings;
- document limitations honestly.

## Terminology preferred in this repo

Preferred terms:
- canonical dataset
- raw staging
- OMOP-like staging
- high-age extrapolation
- official national population
- additive national population
- hierarchical consistent view
- data contract
- YAML spec
- artifact catalog
- provenance

## Expected technical outcomes of an audit/refactor

A successful audit/refactor should leave:
- reproducible execution;
- clearer repo structure;
- explicit runbook;
- explicit data contract;
- useful dictionaries;
- reportable QC;
- a main HTML technical/methodological report;
- preserved downstream compatibility.

## Legacy notes

Older files in `docs/archive/masters_legacy/` may contain useful wording or context, but they are not normative instructions for execution.