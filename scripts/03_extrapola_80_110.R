library(data.table)
library(arrow)
library(here)

source(here("R/io_utils.R"))
source(here("R/spec_utils.R"))
source(here("R/tail_model_utils.R"))

`%||%` <- function(x, y) if (is.null(x)) y else x

P <- ensure_project_dirs_inei()
dir.create(P$FINAL_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(P$STAGE_DIR, recursive = TRUE, showWarnings = FALSE)

SPEC <- read_spec(here("config", "spec_population_inei.yml"))

internal_age_min <- 80L
internal_age_max <- SPEC$policy$extrapolation$internal_age_max %||%
  SPEC$policy$extrapolation$ages_extended_to %||% 125L
contract_terminal_age <- SPEC$policy$extrapolation$contract_terminal_age %||%
  SPEC$constraints$age$max %||% 110L
dt <- as.data.table(arrow::read_parquet(file.path(P$STAGE_DIR, "omop_like_long.parquet")))

simple_obs <- dt[
  age_type == "age_single" &
    !is.na(age) &
    age <= 79L &
    gender_source_value %in% c("M", "F"),
  .(
    population = as.integer(round(population_raw))
  ),
  by = .(
    location_id = as.integer(location_id),
    year_id,
    sex_id = fifelse(gender_source_value == "M", 8507L, 8532L),
    age
  )
]

open_obs <- dt[
  age_type == "age_group" &
    age_group_open == TRUE &
    age_group_start == internal_age_min &
    gender_source_value %in% c("M", "F"),
  .(
    population_open = as.integer(round(population_raw))
  ),
  by = .(
    location_id = as.integer(location_id),
    year_id,
    sex_id = fifelse(gender_source_value == "M", 8507L, 8532L)
  )
]

nat79 <- simple_obs[
  location_id == 0L & age == 79L,
  .(pop79 = sum(population)),
  by = .(year_id, sex_id)
]

nat_open <- open_obs[
  location_id == 0L,
  .(population_open = sum(population_open)),
  by = .(year_id, sex_id)
]

nat_template_inputs <- merge(nat_open, nat79, by = c("year_id", "sex_id"), all.x = TRUE)
nat_template_inputs[is.na(pop79), pop79 := 0]

tail_template <- build_mortality_calibrated_tail_template(
  years = sort(unique(nat_template_inputs$year_id)),
  sex_ids = sort(unique(nat_template_inputs$sex_id)),
  location_ids = sort(unique(open_obs$location_id)),
  ages = internal_age_min:internal_age_max,
  country_name = "Peru",
  open_obs_dt = open_obs,
  official_life_table_path = local_official_tail_benchmark_path()
)

tail_template_compare_mortality <- build_tail_template_diagnostic_compare_with_mortality_repo(
  years = sort(unique(nat_template_inputs$year_id)),
  sex_ids = sort(unique(nat_template_inputs$sex_id)),
  location_ids = sort(unique(open_obs$location_id)),
  ages = internal_age_min:internal_age_max,
  country_name = "Peru",
  open_obs_dt = open_obs,
  official_life_table_path = local_official_tail_benchmark_path()
)

tail_expected <- merge(
  open_obs,
  tail_template,
  by = c("year_id", "sex_id", "location_id"),
  allow.cartesian = TRUE,
  all.x = TRUE
)
tail_expected[, population := population_open * tail_weight]
tail_expected <- tail_expected[, .(
  year_id, age, sex_id, location_id, population,
  qx_benchmark, mx_benchmark, tail_weight, benchmark_source, source_effective,
  kannisto_intercept, kannisto_slope,
  benchmark_observed_age_max, used_open_110plus_row, fit_age_min, fit_age_max
)]

internal_final <- rbindlist(
  list(
    simple_obs[, .(year_id, age, sex_id, location_id, population = as.numeric(population))],
    tail_expected[, .(year_id, age, sex_id, location_id, population)]
  ),
  use.names = TRUE
)
setcolorder(internal_final, c("year_id", "age", "sex_id", "location_id", "population"))
setkey(internal_final, year_id, age, sex_id, location_id)

tail_contract_numeric <- internal_final[
  age >= internal_age_min & age < contract_terminal_age,
  .(year_id, age, sex_id, location_id, population)
]

tail_contract_open <- internal_final[
  age >= contract_terminal_age,
  .(population = sum(population)),
  by = .(year_id, sex_id, location_id)
]
tail_contract_open[, age := as.integer(contract_terminal_age)]

tail_contract_numeric <- rbindlist(
  list(
    tail_contract_numeric,
    tail_contract_open[, .(year_id, age, sex_id, location_id, population)]
  ),
  use.names = TRUE
)

tail_targets <- open_obs[, .(year_id, sex_id, location_id, target_open_total = population_open)]
tail_contract_numeric <- merge(
  tail_contract_numeric,
  tail_targets,
  by = c("year_id", "sex_id", "location_id"),
  all.x = TRUE
)

tail_contract_bridge <- tail_contract_numeric[
  ,
  {
    rounded <- hamilton_round(population, target_open_total[1])
    .(
      age = age,
      population = rounded
    )
  },
  by = .(year_id, sex_id, location_id)
]
setcolorder(tail_contract_bridge, c("year_id", "age", "sex_id", "location_id", "population"))
setkey(tail_contract_bridge, year_id, age, sex_id, location_id)

final <- rbindlist(
  list(
    simple_obs[, .(year_id, age, sex_id, location_id, population)],
    tail_contract_bridge
  ),
  use.names = TRUE
)
setcolorder(final, c("year_id", "age", "sex_id", "location_id", "population"))
setkey(final, year_id, age, sex_id, location_id)

internal_fp <- file.path(P$STAGE_DIR, "population_modeled_internal_0_125.parquet")
bridge_fp <- file.path(P$STAGE_DIR, "population_tail_contract_bridge_80_109_110plus.parquet")
benchmark_fp <- file.path(P$STAGE_DIR, "population_tail_external_benchmark_peru_80_125.parquet")
benchmark_compare_fp <- file.path(P$STAGE_DIR, "benchmark_only", "population_tail_compare_with_local_official_benchmark_80_125.parquet")
crossrepo_adjust_fp <- file.path(P$STAGE_DIR, "population_crossrepo_110plus_adjustment.parquet")
out_fp <- file.path(P$FINAL_DIR, "population_result.parquet")

crossrepo_snapshot_path <- resolve_optional_input_path_inei(
  config_key = "crossrepo_death_110plus_snapshot",
  env_var = "DPG_CROSSREPO_DEATH_110PLUS_SNAPSHOT",
  config_dir = P$CONFIG_DIR,
  use_default_repo_relative = FALSE
)

crossrepo_adjustment <- final[
  age == contract_terminal_age,
  .(
    year_id,
    sex_id,
    location_id,
    population_110plus_before_floor = as.integer(population)
  )
]

if (!is.na(crossrepo_snapshot_path) && file.exists(crossrepo_snapshot_path)) {
  crossrepo_snapshot <- as.data.table(arrow::read_parquet(crossrepo_snapshot_path))
  required_crossrepo_cols <- c(
    "year_id", "sex_id", "location_id",
    "death_count_110plus_observed", "has_death_110plus_observed",
    "source_dataset_version", "source_run_id"
  )
  missing_crossrepo_cols <- setdiff(required_crossrepo_cols, names(crossrepo_snapshot))
  if (length(missing_crossrepo_cols) > 0L) {
    stop("Snapshot cruzado 110+ incompleto. Faltan columnas: ", paste(missing_crossrepo_cols, collapse = ", "))
  }
  crossrepo_snapshot <- unique(crossrepo_snapshot[, ..required_crossrepo_cols])
  if (nrow(crossrepo_snapshot[, .N, by = .(year_id, sex_id, location_id)][N > 1L]) > 0L) {
    stop("Snapshot cruzado 110+ tiene duplicados por year_id, sex_id, location_id: ", crossrepo_snapshot_path)
  }
  crossrepo_adjustment <- merge(
    crossrepo_adjustment,
    crossrepo_snapshot,
    by = c("year_id", "sex_id", "location_id"),
    all.x = TRUE
  )
  crossrepo_adjustment[, snapshot_row_available := !is.na(source_run_id)]
  crossrepo_adjustment[
    snapshot_row_available == TRUE,
    `:=`(
      death_count_110plus_observed = as.integer(fcoalesce(death_count_110plus_observed, 0L)),
      has_death_110plus_observed = fcoalesce(as.logical(has_death_110plus_observed), FALSE),
      crossrepo_110plus_qc_status = "applied_or_checked"
    )
  ]
  crossrepo_adjustment[
    snapshot_row_available == FALSE,
    `:=`(
      death_count_110plus_observed = 0L,
      has_death_110plus_observed = FALSE,
      source_dataset_version = NA_character_,
      source_run_id = NA_character_,
      crossrepo_110plus_qc_status = "skipped_no_snapshot"
    )
  ]
  crossrepo_adjustment[, snapshot_row_available := NULL]
} else {
  crossrepo_adjustment[
    ,
    `:=`(
      death_count_110plus_observed = 0L,
      has_death_110plus_observed = FALSE,
      source_dataset_version = NA_character_,
      source_run_id = NA_character_,
      crossrepo_110plus_qc_status = "skipped_no_snapshot"
    )
  ]
}

crossrepo_adjustment[
  ,
  `:=`(
    coherence_floor_required = has_death_110plus_observed & population_110plus_before_floor == 0L,
    coherence_floor_applied = has_death_110plus_observed & population_110plus_before_floor == 0L
  )
]
crossrepo_adjustment[
  ,
  population_110plus_after_floor := as.integer(fifelse(coherence_floor_applied, 1L, population_110plus_before_floor))
]
crossrepo_adjustment[
  ,
  mass_adjustment_from_crossrepo_qc := as.integer(population_110plus_after_floor - population_110plus_before_floor)
]
crossrepo_adjustment[
  ,
  flag_incoherent := has_death_110plus_observed & population_110plus_after_floor == 0L
]
setorderv(crossrepo_adjustment, c("year_id", "sex_id", "location_id"))

final <- rbindlist(
  list(
    final[age != contract_terminal_age],
    crossrepo_adjustment[, .(
      year_id,
      age = as.integer(contract_terminal_age),
      sex_id,
      location_id,
      population = population_110plus_after_floor
    )]
  ),
  use.names = TRUE
)
setcolorder(final, c("year_id", "age", "sex_id", "location_id", "population"))
setkey(final, year_id, age, sex_id, location_id)

arrow::write_parquet(internal_final, internal_fp)
arrow::write_parquet(tail_contract_bridge, bridge_fp)
arrow::write_parquet(
  unique(tail_expected[, .(
    year_id, sex_id, location_id, age, qx_benchmark, mx_benchmark, tail_weight,
    benchmark_source, source_effective, kannisto_intercept, kannisto_slope,
    benchmark_observed_age_max, used_open_110plus_row, fit_age_min, fit_age_max
  )]),
  benchmark_fp
)
if (nrow(tail_template_compare_mortality) > 0) {
  dir.create(dirname(benchmark_compare_fp), recursive = TRUE, showWarnings = FALSE)
  arrow::write_parquet(
    unique(tail_template_compare_mortality[, .(
      year_id, sex_id, location_id, age, qx_benchmark, mx_benchmark, tail_weight,
      benchmark_source, source_effective, kannisto_intercept, kannisto_slope,
      benchmark_observed_age_max, used_open_110plus_row, fit_age_min, fit_age_max
    )]),
    benchmark_compare_fp
  )
}
arrow::write_parquet(crossrepo_adjustment, crossrepo_adjust_fp)
arrow::write_parquet(final, out_fp)

message("Modelo interno guardado: ", internal_fp)
message("Puente contractual de cola guardado: ", bridge_fp)
message("Benchmark externo de cola guardado: ", benchmark_fp)
if (file.exists(benchmark_compare_fp)) {
  message("Benchmark diagnostico contra benchmark local oficial guardado: ", benchmark_compare_fp)
}
message("Ajuste cross-repo 110+ guardado: ", crossrepo_adjust_fp)
message("FINAL contractual guardado: ", out_fp)
