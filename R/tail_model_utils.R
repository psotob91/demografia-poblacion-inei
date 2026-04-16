library(data.table)

`%||%` <- function(x, y) if (is.null(x)) y else x

local_official_tail_benchmark_path <- function() {
  file.path("data", "raw", "external_benchmarks", "peru_life_table_all_years_closed_80_109.csv")
}

parse_period_midpoint <- function(period_label) {
  period_label <- as.character(period_label)
  bounds <- strsplit(period_label, "-", fixed = TRUE)[[1]]
  mean(as.numeric(bounds))
}

load_wpp_old_age_mx <- function(country_name = "Peru",
                                ages = c(80L, 85L, 90L, 95L, 100L)) {
  if (!requireNamespace("wpp2019", quietly = TRUE)) {
    stop("Package 'wpp2019' is required for the mortality-calibrated old-age tail.")
  }

  sex_map <- list(
    `8507` = list(data_name = "mxM", sex_label = "M"),
    `8532` = list(data_name = "mxF", sex_label = "F")
  )

  rbindlist(lapply(names(sex_map), function(sex_chr) {
    entry <- sex_map[[sex_chr]]
    src_env <- new.env(parent = globalenv())
    utils::data(list = entry$data_name, package = "wpp2019", envir = src_env)
    x <- as.data.table(get(entry$data_name, envir = src_env))
    x <- x[name == country_name & age %in% ages]
    period_cols <- names(x)[4:ncol(x)]

    long <- melt(
      x,
      id.vars = c("country_code", "name", "age"),
      measure.vars = period_cols,
      variable.name = "period",
      value.name = "mx"
    )
    long[, sex_id := as.integer(sex_chr)]
    long[, sex_source := entry$sex_label]
    long[, period_mid_year := vapply(period, parse_period_midpoint, numeric(1))]
    long[]
  }), use.names = TRUE)
}

interpolate_wpp_old_age_nodes <- function(wpp_dt,
                                          years,
                                          country_name = "Peru",
                                          ages = c(80L, 85L, 90L, 95L, 100L),
                                          eps = 1e-10) {
  years <- sort(unique(as.integer(years)))
  x <- as.data.table(wpp_dt)[name == country_name & age %in% ages]
  if (!nrow(x)) {
    stop("No WPP mortality benchmark rows found for country_name='", country_name, "'.")
  }

  rbindlist(lapply(sort(unique(x$sex_id)), function(sex_id_i) {
    x_sex <- x[sex_id == sex_id_i]
    rbindlist(lapply(ages, function(age_i) {
      age_rows <- x_sex[age == age_i][order(period_mid_year)]
      logit_vals <- qlogis(pmin(pmax(age_rows$mx, eps), 1 - eps))
      interp_vals <- approx(
        x = age_rows$period_mid_year,
        y = logit_vals,
        xout = years,
        method = "linear",
        rule = 2
      )$y
      data.table(
        year_id = years,
        sex_id = as.integer(sex_id_i),
        age = as.integer(age_i),
        mx_input = plogis(interp_vals),
        benchmark_source = "UN WPP 2019 Peru mx (quinquennial) interpolated to annual years"
      )
    }))
  }), use.names = TRUE)
}

load_official_life_table_all_years <- function(
    path = local_official_tail_benchmark_path()) {
  if (!file.exists(path)) {
    return(data.table())
  }
  fread(
    path,
    select = c(
      "year_id", "location_id", "sex_id", "age", "mx", "qx", "lx", "Lx",
      "age_interval_open", "life_table_label", "source_year_left", "source_year_right"
    ),
    showProgress = FALSE
  )[
    ,
    .(
      year_id = as.integer(year_id),
      location_id = as.integer(location_id),
      sex_id = as.integer(sex_id),
      age = as.integer(age),
      mx = as.numeric(mx),
      qx = as.numeric(qx),
      lx = as.numeric(lx),
      Lx = as.numeric(Lx),
      age_interval_open = as.logical(age_interval_open),
      life_table_label = as.character(life_table_label),
      source_year_left = as.integer(source_year_left),
      source_year_right = as.integer(source_year_right)
    )
  ][]
}

fit_kannisto_qx_schedule <- function(age_nodes,
                                     qx_nodes,
                                     ages = 80:125,
                                     eps = 1e-10) {
  age_nodes <- as.integer(age_nodes)
  qx_nodes <- as.numeric(qx_nodes)
  ok <- is.finite(age_nodes) & is.finite(qx_nodes)
  age_nodes <- age_nodes[ok]
  qx_nodes <- qx_nodes[ok]

  if (length(age_nodes) < 4L) {
    stop("Kannisto fit requires at least 4 old-age qx nodes.")
  }

  fit <- stats::lm(qlogis(pmin(pmax(qx_nodes, eps), 1 - eps)) ~ age_nodes)
  coefs <- stats::coef(fit)
  slope <- as.numeric(coefs[2])
  if (!is.finite(slope) || slope <= 0) {
    stop("Kannisto fit produced a non-positive old-age mortality slope.")
  }

  qx_pred <- plogis(coefs[1] + coefs[2] * ages)
  data.table(
    age = as.integer(ages),
    qx_benchmark = as.numeric(qx_pred),
    mx_benchmark = as.numeric(-log(pmax(1 - qx_pred, 1e-12))),
    kannisto_intercept = as.numeric(coefs[1]),
    kannisto_slope = slope
  )
}

qx_to_survivor_weights <- function(qx, eps = 1e-12) {
  qx <- as.numeric(qx)
  n <- length(qx)
  if (!n) return(numeric())

  px <- pmax(1 - pmin(pmax(qx, 0), 1), 0)
  lx <- numeric(n)
  lx[1] <- 1
  if (n > 1L) {
    for (i in 2:n) {
      lx[i] <- lx[i - 1L] * px[i - 1L]
    }
  }
  weights <- lx / sum(lx)
  weights[weights < eps] <- 0
  weights / sum(weights)
}

mx_to_survivor_weights <- function(mx, eps = 1e-12) {
  mx <- as.numeric(mx)
  qx <- 1 - exp(-pmax(mx, 0))
  qx_to_survivor_weights(qx = qx, eps = eps)
}

build_wpp_tail_template <- function(years,
                                    sex_ids = c(8507L, 8532L),
                                    location_ids = 0:25,
                                    ages = 80:125,
                                    country_name = "Peru") {
  node_ages <- c(80L, 85L, 90L, 95L, 100L)
  wpp_raw <- load_wpp_old_age_mx(country_name = country_name, ages = node_ages)
  wpp_nodes <- interpolate_wpp_old_age_nodes(
    wpp_dt = wpp_raw,
    years = years,
    country_name = country_name,
    ages = node_ages
  )

  base <- rbindlist(lapply(as.integer(sort(unique(years))), function(year_i) {
    rbindlist(lapply(as.integer(sort(unique(sex_ids))), function(sex_i) {
      nodes <- wpp_nodes[year_id == year_i & sex_id == sex_i][order(age)]
      fit <- fit_kannisto_qx_schedule(
        age_nodes = nodes$age,
        qx_nodes = 1 - exp(-nodes$mx_input),
        ages = ages
      )
      fit[, tail_weight := qx_to_survivor_weights(qx_benchmark)]
      fit[, `:=`(
        year_id = as.integer(year_i),
        sex_id = as.integer(sex_i),
        benchmark_source = nodes$benchmark_source[1],
        source_effective = "production_independent_wpp_peru",
        benchmark_observed_age_max = max(nodes$age, na.rm = TRUE),
        used_open_110plus_row = FALSE,
        fit_age_min = min(nodes$age, na.rm = TRUE),
        fit_age_max = max(nodes$age, na.rm = TRUE)
      )]
      fit[]
    }), use.names = TRUE)
  }), use.names = TRUE)

  out <- rbindlist(lapply(as.integer(sort(unique(location_ids))), function(loc_i) {
    x <- copy(base)
    x[, location_id := loc_i]
    x[]
  }), use.names = TRUE)
  setcolorder(out, c(
    "year_id", "sex_id", "location_id", "age", "qx_benchmark", "mx_benchmark",
    "tail_weight", "kannisto_intercept", "kannisto_slope",
    "benchmark_source", "source_effective", "benchmark_observed_age_max",
    "used_open_110plus_row", "fit_age_min", "fit_age_max"
  ))
  setorderv(out, c("year_id", "sex_id", "location_id", "age"))
  out[]
}

build_tail_template_production_independent <- function(years,
                                                       sex_ids = c(8507L, 8532L),
                                                       location_ids = 0:25,
                                                       ages = 80:125,
                                                       country_name = "Peru") {
  build_wpp_tail_template(
    years = years,
    sex_ids = sex_ids,
    location_ids = location_ids,
    ages = ages,
    country_name = country_name
  )
}

build_official_regional_tail_template <- function(life_table_dt,
                                                  years,
                                                  sex_ids = c(8507L, 8532L),
                                                  location_ids = 1:25,
                                                  ages = 80:125,
                                                  observed_age_max = 109L,
                                                  fit_age_min = 95L,
                                                  fit_age_max = 109L) {
  lt <- as.data.table(life_table_dt)
  lt <- lt[
    year_id %in% years &
      sex_id %in% sex_ids &
      location_id %in% location_ids &
      age >= min(ages) & age <= observed_age_max &
      age_interval_open == FALSE
  ]
  if (!nrow(lt)) return(data.table())

  out <- rbindlist(lapply(split(
    lt,
    by = c("year_id", "sex_id", "location_id"),
    keep.by = TRUE,
    flatten = TRUE
  ), function(grp) {
    grp <- as.data.table(grp)[order(age)]
    fit_nodes <- grp[age >= fit_age_min & age <= fit_age_max]
    fit <- fit_kannisto_qx_schedule(
      age_nodes = fit_nodes$age,
      qx_nodes = fit_nodes$qx,
      ages = ages
    )
    obs <- grp[, .(
      age,
      qx_benchmark = qx,
      mx_benchmark = mx
    )]
    merged <- merge(
      data.table(age = as.integer(ages)),
      fit,
      by = "age",
      all.x = TRUE,
      suffixes = c("", "_fit")
    )
    merged <- merge(merged, obs, by = "age", all.x = TRUE, suffixes = c("_fit", "_obs"))
    merged[, qx_benchmark := fifelse(!is.na(qx_benchmark_obs), qx_benchmark_obs, qx_benchmark_fit)]
    merged[, mx_benchmark := fifelse(!is.na(mx_benchmark_obs), mx_benchmark_obs, mx_benchmark_fit)]
    merged[, tail_weight := qx_to_survivor_weights(qx_benchmark)]
    merged[, `:=`(
      year_id = as.integer(grp$year_id[1]),
      sex_id = as.integer(grp$sex_id[1]),
      location_id = as.integer(grp$location_id[1]),
      benchmark_source = paste0(
        "benchmark local derivado de tabla-mortalidad-peru all_years single_age cerrado 80-109; ",
        grp$life_table_label[1], "; extension Kannisto on qx ",
        fit_age_min, "-", fit_age_max, " to 125"
      ),
      source_effective = "official_life_table_all_years_regional",
      benchmark_observed_age_max = observed_age_max,
      used_open_110plus_row = FALSE,
      fit_age_min = fit_age_min,
      fit_age_max = fit_age_max
    )]
    merged[, .(
      year_id, sex_id, location_id, age, qx_benchmark, mx_benchmark,
      tail_weight, kannisto_intercept, kannisto_slope,
      benchmark_source, source_effective, benchmark_observed_age_max,
      used_open_110plus_row, fit_age_min, fit_age_max
    )]
  }), use.names = TRUE, fill = TRUE)

  setorderv(out, c("year_id", "sex_id", "location_id", "age"))
  out[]
}

build_implicit_national_tail_template <- function(regional_template_dt,
                                                  open_obs_dt,
                                                  national_location_id = 0L,
                                                  regional_location_ids = 1:25) {
  regional_template <- as.data.table(regional_template_dt)[location_id %in% regional_location_ids]
  open_obs <- as.data.table(open_obs_dt)[location_id %in% regional_location_ids]
  if (!nrow(regional_template) || !nrow(open_obs)) return(data.table())

  weighted <- merge(
    regional_template,
    open_obs[, .(year_id, sex_id, location_id, population_open)],
    by = c("year_id", "sex_id", "location_id"),
    all.x = FALSE,
    all.y = FALSE
  )
  weighted[, benchmark_population := population_open * tail_weight]

  out <- weighted[, .(
    benchmark_population = sum(benchmark_population, na.rm = TRUE),
    total_open = sum(population_open, na.rm = TRUE),
    mx_benchmark = weighted.mean(mx_benchmark, w = pmax(population_open, 1), na.rm = TRUE),
    qx_benchmark = weighted.mean(qx_benchmark, w = pmax(population_open, 1), na.rm = TRUE)
  ), by = .(year_id, sex_id, age)]
  out[, tail_weight := fifelse(total_open > 0, benchmark_population / total_open, NA_real_)]
  out[, `:=`(
    location_id = as.integer(national_location_id),
    benchmark_source = "Implicit national benchmark from official all_years regional life tables weighted by observed 80+ mass; only closed ages 80-109 are used before Kannisto extension",
    source_effective = "implicit_national_from_official_regions",
    kannisto_intercept = NA_real_,
    kannisto_slope = NA_real_,
    benchmark_observed_age_max = 109L,
    used_open_110plus_row = FALSE,
    fit_age_min = 95L,
    fit_age_max = 109L
  )]
  out[, .(
    year_id, sex_id, location_id, age, qx_benchmark, mx_benchmark,
    tail_weight, kannisto_intercept, kannisto_slope,
    benchmark_source, source_effective, benchmark_observed_age_max,
    used_open_110plus_row, fit_age_min, fit_age_max
  )][order(year_id, sex_id, location_id, age)]
}

build_mortality_calibrated_tail_template <- function(years,
                                                     sex_ids = c(8507L, 8532L),
                                                     location_ids = 0:25,
                                                     ages = 80:125,
                                                     country_name = "Peru",
                                                     open_obs_dt = NULL,
                                                     official_life_table_path = local_official_tail_benchmark_path()) {
  years <- sort(unique(as.integer(years)))
  sex_ids <- sort(unique(as.integer(sex_ids)))
  location_ids <- sort(unique(as.integer(location_ids)))

  official_lt <- load_official_life_table_all_years(official_life_table_path)
  official_years <- intersect(years, sort(unique(official_lt$year_id)))
  official_locations <- intersect(location_ids, intersect(1:25, sort(unique(official_lt$location_id))))

  regional_official <- build_official_regional_tail_template(
    life_table_dt = official_lt,
    years = official_years,
    sex_ids = sex_ids,
    location_ids = official_locations,
    ages = ages
  )

  implicit_national <- data.table()
  if (!is.null(open_obs_dt)) {
    implicit_national <- build_implicit_national_tail_template(
      regional_template_dt = regional_official,
      open_obs_dt = open_obs_dt,
      national_location_id = 0L,
      regional_location_ids = official_locations
    )
  }

  wpp_all <- build_wpp_tail_template(
    years = years,
    sex_ids = sex_ids,
    location_ids = location_ids,
    ages = ages,
    country_name = country_name
  )

  preferred <- rbindlist(list(regional_official, implicit_national), use.names = TRUE, fill = TRUE)
  if (!nrow(preferred)) return(wpp_all[])

  idx <- CJ(
    year_id = years,
    sex_id = sex_ids,
    location_id = location_ids,
    age = as.integer(ages)
  )
  out <- merge(
    idx,
    preferred,
    by = c("year_id", "sex_id", "location_id", "age"),
    all.x = TRUE
  )
  out <- merge(
    out,
    wpp_all,
    by = c("year_id", "sex_id", "location_id", "age"),
    all.x = TRUE,
    suffixes = c("", "_fallback")
  )

  fill_cols <- c("qx_benchmark", "mx_benchmark", "tail_weight", "kannisto_intercept",
                 "kannisto_slope", "benchmark_source", "source_effective")
  for (col in fill_cols) {
    fallback_col <- paste0(col, "_fallback")
    out[is.na(get(col)), (col) := get(fallback_col)]
    out[, (fallback_col) := NULL]
  }

  setcolorder(out, c(
    "year_id", "sex_id", "location_id", "age", "qx_benchmark", "mx_benchmark",
    "tail_weight", "kannisto_intercept", "kannisto_slope",
    "benchmark_source", "source_effective", "benchmark_observed_age_max",
    "used_open_110plus_row", "fit_age_min", "fit_age_max"
  ))
  setorderv(out, c("year_id", "sex_id", "location_id", "age"))
  out[]
}

build_tail_template_diagnostic_compare_with_mortality_repo <- function(years,
                                                                       sex_ids = c(8507L, 8532L),
                                                                       location_ids = 0:25,
                                                                       ages = 80:125,
                                                                       country_name = "Peru",
                                                                       open_obs_dt = NULL,
                                                                       official_life_table_path = local_official_tail_benchmark_path()) {
  build_mortality_calibrated_tail_template(
    years = years,
    sex_ids = sex_ids,
    location_ids = location_ids,
    ages = ages,
    country_name = country_name,
    open_obs_dt = open_obs_dt,
    official_life_table_path = official_life_table_path
  )
}

hamilton_round <- function(values, target_total) {
  x <- as.numeric(values)
  target_total <- as.integer(round(target_total))

  if (!length(x)) return(integer())
  if (any(is.na(x))) stop("hamilton_round received NA values.")
  if (target_total < 0L) stop("target_total must be non-negative.")

  floored <- floor(x + 1e-12)
  frac <- x - floored
  remainder <- target_total - sum(floored)

  if (remainder > 0L) {
    ord <- order(frac, decreasing = TRUE, na.last = TRUE)
    if (remainder > length(ord)) stop("Hamilton rounding remainder is larger than vector length.")
    floored[ord[seq_len(remainder)]] <- floored[ord[seq_len(remainder)]] + 1L
  } else if (remainder < 0L) {
    ord <- order(frac, decreasing = FALSE, na.last = TRUE)
    need <- abs(remainder)
    idx <- ord[floored[ord] > 0]
    if (need > length(idx)) stop("Hamilton rounding cannot remove the required remainder.")
    floored[idx[seq_len(need)]] <- floored[idx[seq_len(need)]] - 1L
  }

  as.integer(floored)
}
