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
Contractual age field in integer form. Ages `0` to `109` represent single completed years of age. `age = 110` represents the open-ended age group `110+`.

### `sex_id`
OMOP-like concept identifier for sex coding used by the project.

### `location_id`
Project location identifier used for national or department-level geography according to project mapping rules.

### `population`
Population count for the exact stratum defined by year, age, sex, and location.

## Local benchmark and self-contained build

The contractual dataset is built from a self-contained base pipeline. High-age tail anchoring uses a local benchmark file stored inside this repository:

- `data/raw/external_benchmarks/peru_life_table_all_years_closed_80_109.csv`

That benchmark:
- is a local, versioned copy derived from `tabla-mortalidad-peru`;
- includes only closed ages `80:109`;
- excludes the open `110+` mortality row by design;
- allows the base build to run without a runtime dependency on sibling repositories.

## Cross-repo coherence exception

This repository may optionally consume a non-sensitive external snapshot from `mortalidad-causa-especifica` summarizing observed deaths in `110+` by `year_id`, `sex_id`, and `location_id`.

If that snapshot exists and is structurally valid, the contractual output applies one narrow guard-rail:

- when observed deaths `110+ > 0`
- and contractual `age = 110` would otherwise be `0`

then `population(age = 110)` is raised to `1`.

This exception:
- is downstream-visible by design;
- is recorded in QC as `coherence_floor_applied` and `mass_adjustment_from_crossrepo_qc`;
- does not change ages `0:109`;
- does not replace the main demographic tail model.

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
