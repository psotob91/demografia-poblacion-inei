# DATA_CONTRACT

## Purpose

This document defines the contractual final output that downstream repositories depend on.

## Contractual principle

Any refactor, audit, cleanup, reorganization, or documentation improvement must preserve the final output contract unless a breaking change is intentionally versioned and explicitly coordinated.

## Primary contractual output

Expected canonical final output:

`data/final/population_inei/population_result.parquet`

## Logical primary key

Logical key:

- `year_id`
- `age`
- `sex_id`
- `location_id`

The combination must be unique.

## Required columns

Required columns:

- `year_id`
- `age`
- `sex_id`
- `location_id`
- `population`

## Column semantics

### `year_id`
Calendar year of the estimate.

### `age`
Single year of age in integer form.

### `sex_id`
OMOP-like concept identifier for sex coding used by the project.

### `location_id`
Project location identifier used for national or department-level geography according to project mapping rules.

### `population`
Population count for the exact stratum defined by year, age, sex, and location.

## Stability requirements

The following must remain stable unless a versioned breaking change is created intentionally:
- file path
- filename
- parquet format
- column names
- column types
- logical grain
- semantic meaning

## Validation expectations

At minimum, validate after any nontrivial change:
- required columns present
- expected column types
- uniqueness of logical key
- no missing values in required fields
- nonnegative population
- compatible value domains for year/age/sex/location
- row count comparison versus baseline
- checksum or deterministic fingerprint comparison where possible

## Additional output of interest

This repository may also produce:
- dictionaries
- staging outputs
- additive national output
- hierarchical view
- QC files
- artifact catalogs

These are important, but the primary contractual output above has the highest stability requirement.