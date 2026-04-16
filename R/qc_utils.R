# R/qc_utils.R
library(data.table)

`%||%` <- function(x, y) if (is.null(x)) y else x

qc_pk_duplicates <- function(dt, pk) {
  dt[, .N, by = pk][N > 1]
}

qc_missing_required <- function(dt, req_cols) {
  data.table(
    column = req_cols,
    n_missing = sapply(req_cols, \(c) sum(is.na(dt[[c]]))),
    pct_missing = sapply(req_cols, \(c) round(100 * mean(is.na(dt[[c]])), 6))
  )
}

qc_nonnegative <- function(dt, col) {
  dt[get(col) < 0]
}

# FIX: setorder(x, by_cols, age_col) -> setorderv con vector de columnas
qc_tail_monotone_flag <- function(dt,
                                  age_col = "age",
                                  pop_col = "population",
                                  start_age = 70L,
                                  by_cols = c("year_id", "sex_id", "location_id"),
                                  tol = 1e-8) {
  x <- as.data.table(dt)[get(age_col) >= start_age]
  if (nrow(x) == 0) return(data.table())
  
  # ordenar por columnas dinámicas
  data.table::setorderv(x, cols = c(by_cols, age_col))
  
  x[, pop_prev := shift(get(pop_col)), by = by_cols]
  x[, inc_flag := !is.na(pop_prev) & (get(pop_col) - pop_prev) > tol]
  
  x[inc_flag == TRUE, .N, by = by_cols]
}

qc_tail_collapse_exact <- function(contract_dt,
                                   bridge_dt,
                                   adjustment_dt = NULL,
                                   terminal_age = 110L,
                                   by_cols = c("year_id", "sex_id", "location_id"),
                                   pop_col = "population",
                                   age_col = "age") {
  x_contract <- as.data.table(contract_dt)
  x_bridge <- as.data.table(bridge_dt)

  final_open <- x_contract[get(age_col) == terminal_age,
                           .(pop_110plus_final = sum(get(pop_col), na.rm = TRUE)),
                           by = by_cols]

  bridge_open <- x_bridge[get(age_col) == terminal_age,
                             .(pop_bridge_110plus = sum(get(pop_col), na.rm = TRUE)),
                             by = by_cols]

  if (!is.null(adjustment_dt) && nrow(adjustment_dt)) {
    adj <- unique(as.data.table(adjustment_dt)[, c(by_cols, "mass_adjustment_from_crossrepo_qc"), with = FALSE])
  } else {
    adj <- unique(bridge_open[, ..by_cols])
    adj[, mass_adjustment_from_crossrepo_qc := 0L]
  }

  out <- merge(final_open, bridge_open, by = by_cols, all = TRUE)
  out <- merge(out, adj, by = by_cols, all.x = TRUE)
  out[is.na(mass_adjustment_from_crossrepo_qc), mass_adjustment_from_crossrepo_qc := 0L]
  out[, pop_bridge_expected_110plus := pop_bridge_110plus + mass_adjustment_from_crossrepo_qc]
  out[, diff := pop_110plus_final - pop_bridge_expected_110plus]
  out[, flag_diff := is.na(pop_110plus_final) | is.na(pop_bridge_expected_110plus) | diff != 0L]
  data.table::setorderv(out, cols = by_cols)
  out[]
}

qc_tail_mass_80plus_exact <- function(internal_dt,
                                      open_obs_dt,
                                      start_age = 80L,
                                      end_age = 125L,
                                      by_cols = c("year_id", "sex_id", "location_id"),
                                      pop_col = "population",
                                      tol = 1e-8) {
  x_internal <- as.data.table(internal_dt)
  x_open <- as.data.table(open_obs_dt)

  internal_mass <- x_internal[get("age") >= start_age & get("age") <= end_age,
                              .(pop_internal_80plus = sum(get(pop_col), na.rm = TRUE)),
                              by = by_cols]
  out <- merge(internal_mass, x_open, by = by_cols, all = TRUE)
  setnames(out, old = "population_open", new = "pop_observed_80plus")
  out[, diff := pop_internal_80plus - pop_observed_80plus]
  out[, flag_diff := is.na(pop_internal_80plus) | is.na(pop_observed_80plus) | abs(diff) > tol]
  data.table::setorderv(out, cols = by_cols)
  out[]
}

qc_tail_cap_125_national <- function(internal_dt,
                                     national_location_id = 0L,
                                     target_age = 125L,
                                     cap_value = 1.0,
                                     tol = 1e-8) {
  x <- as.data.table(internal_dt)
  out <- x[
    location_id == national_location_id & age == target_age,
    .(national_internal_age125 = sum(population, na.rm = TRUE)),
    by = .(year_id, sex_id)
  ]
  out[, cap_value := cap_value]
  out[, diff := national_internal_age125 - cap_value]
  out[, flag_diff := national_internal_age125 > (cap_value + tol)]
  data.table::setorderv(out, cols = c("year_id", "sex_id"))
  out[]
}

qc_tail_external_alignment_national <- function(internal_dt,
                                                benchmark_dt,
                                                location_ids = NULL,
                                                start_age = 80L,
                                                end_age = 125L,
                                                tol = 1e-8) {
  if (is.null(location_ids)) {
    location_ids <- sort(unique(as.data.table(benchmark_dt)$location_id))
  }
  internal <- as.data.table(internal_dt)[
    location_id %in% location_ids & age >= start_age & age <= end_age,
    .(population_internal = sum(population, na.rm = TRUE)),
    by = .(year_id, sex_id, location_id, age)
  ]
  internal[, internal_share := population_internal / sum(population_internal), by = .(year_id, sex_id, location_id)]

  benchmark <- as.data.table(benchmark_dt)[
    age >= start_age & age <= end_age,
    .(year_id, sex_id, location_id, age, benchmark_tail_weight = tail_weight, mx_benchmark, qx_benchmark, benchmark_source, source_effective, benchmark_observed_age_max)
  ]

  out <- merge(internal, benchmark, by = c("year_id", "sex_id", "location_id", "age"), all = TRUE)
  out[, share_diff := internal_share - benchmark_tail_weight]
  out[, align_required := fifelse(
    source_effective %in% c("official_life_table_all_years_regional", "implicit_national_from_official_regions"),
    age <= benchmark_observed_age_max,
    TRUE
  )]
  out[, flag_diff := fifelse(
    align_required,
    is.na(internal_share) | is.na(benchmark_tail_weight) | abs(share_diff) > tol,
    FALSE
  )]
  data.table::setorderv(out, cols = c("year_id", "sex_id", "location_id", "age"))
  out[]
}

qc_tail_share_110plus <- function(contract_dt,
                                  internal_dt,
                                  open_obs_dt,
                                  benchmark_dt,
                                  terminal_age = 110L,
                                  start_age = 80L,
                                  end_age = 125L,
                                  tol = 1e-8) {
  open_obs <- as.data.table(open_obs_dt)[, .(
    year_id, sex_id, location_id,
    pop_observed_80plus = population_open
  )]

  contract_110 <- as.data.table(contract_dt)[age == terminal_age,
    .(pop_contract_110plus = sum(population, na.rm = TRUE)),
    by = .(year_id, sex_id, location_id)
  ]

  internal_110 <- as.data.table(internal_dt)[age >= terminal_age & age <= end_age,
    .(pop_internal_110plus = sum(population, na.rm = TRUE)),
    by = .(year_id, sex_id, location_id)
  ]

  benchmark_share <- as.data.table(benchmark_dt)[age >= terminal_age & age <= end_age,
    .(benchmark_share_110plus = sum(tail_weight, na.rm = TRUE)),
    by = .(year_id, sex_id, location_id)
  ]

  out <- Reduce(function(x, y) merge(x, y, by = c("year_id", "sex_id", "location_id"), all = TRUE),
                list(open_obs, contract_110, internal_110))
  out <- merge(out, benchmark_share, by = c("year_id", "sex_id", "location_id"), all.x = TRUE)
  out[, contract_share_110plus := fifelse(pop_observed_80plus > 0, pop_contract_110plus / pop_observed_80plus, NA_real_)]
  out[, internal_share_110plus := fifelse(pop_observed_80plus > 0, pop_internal_110plus / pop_observed_80plus, NA_real_)]
  out[, benchmark_pop_110plus := pop_observed_80plus * benchmark_share_110plus]
  out[, contract_vs_benchmark_diff := pop_contract_110plus - benchmark_pop_110plus]
  out[, internal_vs_benchmark_diff := pop_internal_110plus - benchmark_pop_110plus]
  out[, flag_contract_far := is.na(contract_share_110plus) | is.na(benchmark_share_110plus) |
        abs(contract_share_110plus - benchmark_share_110plus) > tol]
  data.table::setorderv(out, cols = c("year_id", "sex_id", "location_id"))
  out[]
}

qc_tail_visual_priority <- function(qc_tail_share_dt,
                                    location_weights = c(`0` = 4, `15` = 3),
                                    top_n = 25L) {
  x <- copy(as.data.table(qc_tail_share_dt))
  x[, visual_priority_score :=
      fifelse(location_id == 0L, location_weights[["0"]] %||% 4, 1) *
      fifelse(location_id == 15L, location_weights[["15"]] %||% 3, 1) *
      (abs(contract_vs_benchmark_diff) + pop_contract_110plus + 1000 * abs(contract_share_110plus - benchmark_share_110plus))]
  x[, rank_visual_priority := frank(-visual_priority_score, ties.method = "dense")]
  data.table::setorderv(x, cols = c("rank_visual_priority", "year_id", "sex_id", "location_id"))
  x[seq_len(min(top_n, .N))]
}

qc_tail_benchmark_source_by_stratum <- function(benchmark_dt) {
  x <- unique(as.data.table(benchmark_dt)[, .(
    year_id, sex_id, location_id, benchmark_source, source_effective,
    benchmark_observed_age_max, used_open_110plus_row, fit_age_min, fit_age_max
  )])
  data.table::setorderv(x, cols = c("year_id", "sex_id", "location_id"))
  x[]
}

qc_tail_open_interval_exclusion <- function(benchmark_dt) {
  x <- unique(as.data.table(benchmark_dt)[, .(
    year_id, sex_id, location_id, benchmark_source, source_effective,
    benchmark_observed_age_max, used_open_110plus_row, fit_age_min, fit_age_max
  )])
  x[, flag_diff := used_open_110plus_row %in% TRUE]
  data.table::setorderv(x, cols = c("year_id", "sex_id", "location_id"))
  x[]
}

# QC detectivo: national (00) vs suma deptos (01–25)
qc_national_vs_dept_sum <- function(dt,
                                    location_col = "location_id",
                                    national_id = 0L,
                                    dept_ids = 1:25,
                                    by_cols = c("year_id", "sex_id", "age"),
                                    pop_col = "population",
                                    pct_tol = 0.001) {
  x <- as.data.table(dt)
  
  nat <- x[get(location_col) == national_id,
           .(pop_national = sum(get(pop_col), na.rm = TRUE)),
           by = by_cols]
  
  dep <- x[get(location_col) %in% dept_ids,
           .(pop_dept_sum = sum(get(pop_col), na.rm = TRUE)),
           by = by_cols]
  
  out <- merge(nat, dep, by = by_cols, all = TRUE)
  
  out[, diff_abs := pop_national - pop_dept_sum]
  out[, diff_pct := fifelse(!is.na(pop_dept_sum) & pop_dept_sum > 0,
                            100 * diff_abs / pop_dept_sum,
                            NA_real_)]
  
  out[, flag_diff := fifelse(!is.na(diff_pct) & abs(diff_pct) > (pct_tol * 100), TRUE, FALSE)]
  out[, flag_missing := is.na(pop_national) | is.na(pop_dept_sum)]
  
  data.table::setorderv(out, cols = by_cols)
  out[]
}

qc_hierarchical_national_additive_hard <- function(dt,
                                                   base_locations = 1:25,
                                                   national_additive_id = 9000L) {
  stopifnot(all(c("year_id","age","sex_id","location_id","population") %in% names(dt)))
  
  # 1) No permitir location_id = 0
  if (any(dt$location_id == 0L)) {
    stop("QC HARD FAIL: Vista jerárquica contiene location_id=0 (nacional original). Debe excluirse.")
  }
  
  # 2) Debe existir 9000
  if (!any(dt$location_id == national_additive_id)) {
    stop("QC HARD FAIL: Vista jerárquica no contiene location_id=9000 (nacional aditivo).")
  }
  
  # 3) Debe cubrir exactamente base_locations
  missing_base <- setdiff(base_locations, unique(dt$location_id))
  if (length(missing_base) > 0) {
    stop("QC HARD FAIL: faltan deptos base en vista jerárquica: ", paste(missing_base, collapse = ", "))
  }
  
  # 4) Chequeo exacto: 9000 == suma deptos por celda
  dt_dept <- dt[location_id %in% base_locations,
                .(dept_sum = sum(population)), by = .(year_id, age, sex_id)]
  
  dt_nat <- dt[location_id == national_additive_id,
               .(nat_pop = population), by = .(year_id, age, sex_id)]
  
  chk <- merge(dt_dept, dt_nat, by = c("year_id","age","sex_id"), all = TRUE)
  
  # NAs son errores de cobertura
  if (anyNA(chk$dept_sum) || anyNA(chk$nat_pop)) {
    stop("QC HARD FAIL: hay celdas donde falta dept_sum o nat_pop (cobertura incompleta).")
  }
  
  chk[, diff := nat_pop - dept_sum]
  bad <- chk[diff != 0]
  
  if (nrow(bad) > 0) {
    # no guardamos silenciosamente; fallamos mostrando un resumen
    top <- bad[order(-abs(diff))][1:min(20, .N)]
    stop(
      "QC HARD FAIL: nacional aditivo (9000) NO es suma exacta de deptos.\n",
      "Ejemplos (top 20 por |diff|):\n",
      paste(capture.output(print(top)), collapse = "\n")
    )
  }
  
  invisible(TRUE)
}

qc_crossrepo_110plus_coherence <- function(adjustment_dt) {
  x <- as.data.table(adjustment_dt)
  if (!nrow(x)) return(data.table())
  out <- unique(x[, .(
    year_id,
    sex_id,
    location_id,
    death_count_110plus_observed = as.integer(death_count_110plus_observed),
    has_death_110plus_observed = as.logical(has_death_110plus_observed),
    population_110plus_contract = as.integer(population_110plus_after_floor),
    coherence_floor_required = as.logical(coherence_floor_required),
    coherence_floor_applied = as.logical(coherence_floor_applied),
    mass_adjustment_from_crossrepo_qc = as.integer(mass_adjustment_from_crossrepo_qc),
    crossrepo_110plus_qc_status = as.character(crossrepo_110plus_qc_status),
    source_dataset_version = as.character(source_dataset_version),
    source_run_id = as.character(source_run_id)
  )])
  out[, flag_incoherent := has_death_110plus_observed & population_110plus_contract == 0L]
  setorderv(out, c("year_id", "sex_id", "location_id"))
  out[]
}

qc_crossrepo_mass_adjustment <- function(adjustment_dt) {
  x <- as.data.table(adjustment_dt)
  if (!nrow(x)) return(data.table())
  x[, .(
    n_strata = .N,
    n_snapshot_rows = sum(crossrepo_110plus_qc_status == "applied_or_checked", na.rm = TRUE),
    n_snapshot_skipped = sum(crossrepo_110plus_qc_status == "skipped_no_snapshot", na.rm = TRUE),
    n_floor_required = sum(coherence_floor_required, na.rm = TRUE),
    n_floor_applied = sum(coherence_floor_applied, na.rm = TRUE),
    total_mass_adjustment = sum(mass_adjustment_from_crossrepo_qc, na.rm = TRUE),
    n_incoherent_after_floor = sum(has_death_110plus_observed & population_110plus_after_floor == 0L, na.rm = TRUE)
  )]
}
