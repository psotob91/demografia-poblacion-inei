library(data.table)
library(arrow)
library(here)

source(here("R/io_utils.R"))
source(here("R/spec_utils.R"))
source(here("R/dictionary_utils.R"))
source(here("R/catalog_utils.R"))
source(here("R/qc_utils.R"))

`%||%` <- function(x, y) if (is.null(x)) y else x

P <- paths_inei()
dir.create(P$QC_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(P$FINAL_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(P$CONFIG_DIR, recursive = TRUE, showWarnings = FALSE)

SPEC_PATH <- here("config", "spec_population_inei.yml")
SPEC <- read_spec(SPEC_PATH)

dataset_id <- SPEC$dataset_id
table_name <- SPEC$table_name
dataset_version <- "v1.0.0"
run_id <- format(Sys.time(), "%Y%m%d_%H%M%S")

FINAL_FP <- file.path(P$FINAL_DIR, "population_result.parquet")
INTERNAL_FP <- file.path(P$STAGE_DIR, "population_modeled_internal_0_125.parquet")
BRIDGE_FP <- file.path(P$STAGE_DIR, "population_tail_contract_bridge_80_109_110plus.parquet")
BENCHMARK_FP <- file.path(P$STAGE_DIR, "population_tail_external_benchmark_peru_80_125.parquet")
ADJUST_FP <- file.path(P$STAGE_DIR, "population_crossrepo_110plus_adjustment.parquet")
DICT_FP <- file.path(P$FINAL_DIR, "population_result_diccionario_ext.csv")
INTERNAL_DICT_FP <- file.path(P$STAGE_DIR, "population_modeled_internal_0_125_diccionario_ext.csv")
BRIDGE_DICT_FP <- file.path(P$STAGE_DIR, "population_tail_contract_bridge_80_109_110plus_diccionario_ext.csv")
BENCHMARK_DICT_FP <- file.path(P$STAGE_DIR, "population_tail_external_benchmark_peru_80_125_diccionario_ext.csv")
ADJUST_DICT_FP <- file.path(P$STAGE_DIR, "population_crossrepo_110plus_adjustment_diccionario_ext.csv")

QC_SUMMARY_FP <- file.path(P$QC_DIR, "qc_summary.csv")
QC_DUP_FP <- file.path(P$QC_DIR, "qc_duplicates.csv")
QC_MISS_FP <- file.path(P$QC_DIR, "qc_missing_required.csv")
QC_NEG_FP <- file.path(P$QC_DIR, "qc_negative_population.csv")
QC_TAIL_FP <- file.path(P$QC_DIR, "qc_tail_monotone_flags.csv")
QC_TAIL_MASS_FP <- file.path(P$QC_DIR, "qc_tail_mass_80plus_exact.csv")
QC_TAIL_CAP_FP <- file.path(P$QC_DIR, "qc_tail_cap_125_national.csv")
QC_TAIL_ALIGN_FP <- file.path(P$QC_DIR, "qc_tail_external_alignment_national.csv")
QC_TAIL_SHARE_FP <- file.path(P$QC_DIR, "qc_tail_share_110plus.csv")
QC_TAIL_PRIORITY_FP <- file.path(P$QC_DIR, "qc_tail_visual_priority.csv")
QC_TAIL_SOURCE_FP <- file.path(P$QC_DIR, "qc_tail_benchmark_source_by_stratum.csv")
QC_TAIL_OPEN_EXCL_FP <- file.path(P$QC_DIR, "qc_tail_open_interval_exclusion.csv")
QC_NAT_VS_DEPFP <- file.path(P$QC_DIR, "qc_national_vs_dept_sum.csv")
QC_COLLAPSE_FP <- file.path(P$QC_DIR, "qc_110plus_collapse_exact.csv")
QC_CROSSREPO_COH_FP <- file.path(P$QC_DIR, "qc_crossrepo_110plus_coherence.csv")
QC_CROSSREPO_MASS_FP <- file.path(P$QC_DIR, "qc_crossrepo_mass_adjustment.csv")

register_run_start(run_id, dataset_id, dataset_version)

tryCatch({
  if (!file.exists(FINAL_FP)) stop("No existe FINAL: ", FINAL_FP)
  if (!file.exists(INTERNAL_FP)) stop("No existe modelo interno: ", INTERNAL_FP)
  if (!file.exists(BRIDGE_FP)) stop("No existe puente contractual de cola: ", BRIDGE_FP)
  if (!file.exists(BENCHMARK_FP)) stop("No existe benchmark externo de cola: ", BENCHMARK_FP)
  if (!file.exists(ADJUST_FP)) stop("No existe ajuste cross-repo 110+: ", ADJUST_FP)

  dt <- as.data.table(arrow::read_parquet(FINAL_FP))
  internal_dt <- as.data.table(arrow::read_parquet(INTERNAL_FP))
  bridge_dt <- as.data.table(arrow::read_parquet(BRIDGE_FP))
  benchmark_dt <- as.data.table(arrow::read_parquet(BENCHMARK_FP))
  adjust_dt <- as.data.table(arrow::read_parquet(ADJUST_FP))
  omop_dt <- as.data.table(arrow::read_parquet(file.path(P$STAGE_DIR, "omop_like_long.parquet")))

  validate_population_result(dt, SPEC)

  req_cols <- names(SPEC$required_columns)
  pk <- SPEC$primary_key
  fit_age_min <- SPEC$policy$extrapolation$fit_age_min %||% 95L
  tail_start <- if (nrow(omop_dt[age_type == "age_group" & age_group_open == TRUE & !is.na(age_group_start)])) {
    as.integer(min(omop_dt[age_type == "age_group" & age_group_open == TRUE, age_group_start], na.rm = TRUE))
  } else {
    80L
  }
  internal_age_max <- SPEC$policy$extrapolation$internal_age_max %||% 125L
  terminal_age <- SPEC$policy$extrapolation$contract_terminal_age %||% 110L
  target_age_cap <- SPEC$policy$extrapolation$internal_age_max %||% 125L
  cap_value <- SPEC$policy$extrapolation$internal_tail_cap_125_per_sex_per_year %||% 1.0

  open_obs <- omop_dt[
    age_type == "age_group" &
      age_group_open == TRUE &
      age_group_start == tail_start &
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

  qc_missing <- qc_missing_required(dt, req_cols)
  fwrite(qc_missing, QC_MISS_FP)

  qc_dups <- qc_pk_duplicates(dt, pk)
  fwrite(qc_dups, QC_DUP_FP)

  qc_neg <- qc_nonnegative(dt, "population")
  fwrite(qc_neg, QC_NEG_FP)

  qc_tail <- qc_tail_monotone_flag(internal_dt, start_age = tail_start, tol = 1e-8)
  fwrite(qc_tail, QC_TAIL_FP)

  qc_tail_mass <- qc_tail_mass_80plus_exact(
    internal_dt = internal_dt,
    open_obs_dt = open_obs,
    start_age = tail_start,
    end_age = internal_age_max,
    tol = 1e-8
  )
  fwrite(qc_tail_mass, QC_TAIL_MASS_FP)
  if (any(qc_tail_mass$flag_diff)) {
    stop("QC HARD FAIL: la cola interna 80:125 no preserva exactamente la masa observada 80 y +. Ver: ", QC_TAIL_MASS_FP)
  }

  qc_nat_cap <- qc_tail_cap_125_national(
    internal_dt = internal_dt,
    national_location_id = 0L,
    target_age = target_age_cap,
    cap_value = cap_value,
    tol = 1e-8
  )
  fwrite(qc_nat_cap, QC_TAIL_CAP_FP)
  if (any(qc_nat_cap$flag_diff)) {
    stop("QC HARD FAIL: la edad interna ", target_age_cap, " excede el tope nacional por sexo-ano. Ver: ", QC_TAIL_CAP_FP)
  }

  qc_tail_align <- qc_tail_external_alignment_national(
    internal_dt = internal_dt,
    benchmark_dt = benchmark_dt,
    location_ids = sort(unique(benchmark_dt$location_id)),
    start_age = tail_start,
    end_age = internal_age_max,
    tol = 1e-8
  )
  fwrite(qc_tail_align, QC_TAIL_ALIGN_FP)
  if (any(qc_tail_align$flag_diff)) {
    stop("QC HARD FAIL: la cola interna nacional no coincide con el benchmark externo por edad. Ver: ", QC_TAIL_ALIGN_FP)
  }

  qc_nat_vs_dep <- qc_national_vs_dept_sum(dt, pct_tol = 0.001)
  fwrite(qc_nat_vs_dep, QC_NAT_VS_DEPFP)

  qc_collapse <- qc_tail_collapse_exact(
    contract_dt = dt,
    bridge_dt = bridge_dt,
    adjustment_dt = adjust_dt,
    terminal_age = terminal_age
  )
  fwrite(qc_collapse, QC_COLLAPSE_FP)
  if (any(qc_collapse$flag_diff)) {
    stop("QC HARD FAIL: age=110 contractual no coincide exactamente con el puente contractual 110+. Ver: ", QC_COLLAPSE_FP)
  }

  qc_tail_share <- qc_tail_share_110plus(
    contract_dt = dt,
    internal_dt = internal_dt,
    open_obs_dt = open_obs,
    benchmark_dt = benchmark_dt,
    terminal_age = terminal_age,
    start_age = tail_start,
    end_age = internal_age_max,
    tol = 0.01
  )
  fwrite(qc_tail_share, QC_TAIL_SHARE_FP)

  qc_tail_priority <- qc_tail_visual_priority(qc_tail_share, top_n = 50L)
  fwrite(qc_tail_priority, QC_TAIL_PRIORITY_FP)

  qc_tail_source <- qc_tail_benchmark_source_by_stratum(benchmark_dt)
  fwrite(qc_tail_source, QC_TAIL_SOURCE_FP)
  qc_tail_open_excl <- qc_tail_open_interval_exclusion(benchmark_dt)
  fwrite(qc_tail_open_excl, QC_TAIL_OPEN_EXCL_FP)
  if (any(qc_tail_open_excl$flag_diff)) {
    stop("QC HARD FAIL: el benchmark de cola uso la fila abierta 110+ como input de modelamiento. Ver: ", QC_TAIL_OPEN_EXCL_FP)
  }

  qc_crossrepo_coh <- qc_crossrepo_110plus_coherence(adjust_dt)
  fwrite(qc_crossrepo_coh, QC_CROSSREPO_COH_FP)
  if (any(qc_crossrepo_coh$flag_incoherent, na.rm = TRUE)) {
    stop("QC HARD FAIL: existen estratos con muertes observadas 110+ y poblacion contractual 110+ igual a cero. Ver: ", QC_CROSSREPO_COH_FP)
  }

  qc_crossrepo_mass <- qc_crossrepo_mass_adjustment(adjust_dt)
  fwrite(qc_crossrepo_mass, QC_CROSSREPO_MASS_FP)

  nat_n_missing <- sum(qc_nat_vs_dep$flag_missing, na.rm = TRUE)
  nat_n_diff <- sum(qc_nat_vs_dep$flag_diff, na.rm = TRUE)
  collapse_n_diff <- sum(qc_collapse$flag_diff, na.rm = TRUE)
  mass_n_diff <- sum(qc_tail_mass$flag_diff, na.rm = TRUE)
  cap_n_diff <- sum(qc_nat_cap$flag_diff, na.rm = TRUE)
  align_n_diff <- sum(qc_tail_align$flag_diff, na.rm = TRUE)
  share_n_far <- sum(qc_tail_share$flag_contract_far, na.rm = TRUE)
  open_excl_n_diff <- sum(qc_tail_open_excl$flag_diff, na.rm = TRUE)
  crossrepo_n_incoherent <- sum(qc_crossrepo_coh$flag_incoherent, na.rm = TRUE)
  crossrepo_n_floor <- sum(qc_crossrepo_coh$coherence_floor_applied, na.rm = TRUE)
  crossrepo_mass_added <- sum(qc_crossrepo_coh$mass_adjustment_from_crossrepo_qc, na.rm = TRUE)

  qc_summary <- data.table(
    dataset_id = dataset_id,
    table_name = table_name,
    version = dataset_version,
    run_id = run_id,
    n_rows = nrow(dt),
    n_cols = ncol(dt),
    year_min = min(dt$year_id),
    year_max = max(dt$year_id),
    age_min = min(dt$age),
    age_max = max(dt$age),
    n_pk_dups = nrow(qc_dups),
    n_negative_pop = nrow(qc_neg),
    n_tail_increase_flags = if (nrow(qc_tail) == 0) 0L else sum(qc_tail$N),
    qc_tail_mass_n_diff = mass_n_diff,
    qc_tail_cap_125_n_diff = cap_n_diff,
    qc_tail_external_alignment_n_diff = align_n_diff,
    qc_tail_share_110plus_n_far = share_n_far,
    qc_tail_benchmark_source_n_strata = nrow(qc_tail_source),
    qc_tail_open_interval_exclusion_n_diff = open_excl_n_diff,
    qc_crossrepo_110plus_n_incoherent = crossrepo_n_incoherent,
    qc_crossrepo_110plus_n_floor_applied = crossrepo_n_floor,
    qc_crossrepo_110plus_mass_added = crossrepo_mass_added,
    qc_nat_vs_dep_n_missing = nat_n_missing,
    qc_nat_vs_dep_n_diff = nat_n_diff,
    qc_110plus_collapse_n_diff = collapse_n_diff
  )
  fwrite(qc_summary, QC_SUMMARY_FP)
  qc_summary_dict <- make_table_dictionary(
    data = qc_summary,
    table_name = "qc_summary",
    dataset_id = dataset_id,
    version = dataset_version,
    run_id = run_id,
    metadata = data.table(
      column_name = c(
        "dataset_id", "table_name", "version", "run_id", "n_rows", "n_cols",
        "year_min", "year_max", "age_min", "age_max", "n_pk_dups",
        "n_negative_pop", "n_tail_increase_flags", "qc_tail_mass_n_diff",
        "qc_tail_cap_125_n_diff", "qc_tail_external_alignment_n_diff",
        "qc_tail_share_110plus_n_far", "qc_tail_benchmark_source_n_strata", "qc_tail_open_interval_exclusion_n_diff",
        "qc_crossrepo_110plus_n_incoherent", "qc_crossrepo_110plus_n_floor_applied", "qc_crossrepo_110plus_mass_added", "qc_nat_vs_dep_n_missing",
        "qc_nat_vs_dep_n_diff", "qc_110plus_collapse_n_diff"
      ),
      label = c(
        "Dataset", "Tabla", "Version", "Run", "Filas", "Columnas",
        "Ano minimo", "Ano maximo", "Edad minima", "Edad maxima", "Duplicados PK",
        "Negativos", "Flags de aumento en cola", "Dif. masa 80+",
        "Dif. tope 125", "Dif. alineacion benchmark",
        "Estratos con share 110+ lejos", "Estratos con fuente benchmark", "Uso indebido de 110+ abierto",
        "Estratos incoherentes cross-repo", "Estratos con piso aplicado", "Masa agregada por coherencia", "Faltantes nacional vs deptos",
        "Dif. nacional vs deptos", "Dif. colapso 110+"
      ),
      description = c(
        "Identificador del dataset auditado.",
        "Nombre de la tabla contractual auditada.",
        "Version interna del dataset.",
        "Run de QC que genero este resumen.",
        "Numero de filas del contractual final.",
        "Numero de columnas del contractual final.",
        "Ano minimo observado.",
        "Ano maximo observado.",
        "Edad minima contractual.",
        "Edad maxima contractual.",
        "Numero de duplicados detectados en la PK.",
        "Numero de filas con poblacion negativa.",
        "Numero de estratos con aumentos en la cola interna 80-125.",
        "Numero de estratos donde la masa interna 80-125 no coincide con el observado 80+.",
        "Numero de sexo-ano donde age 125 supera el tope permitido.",
        "Numero de filas edad a edad donde la cola interna no coincide con el benchmark externo del estrato.",
        "Numero de estratos donde el share contractual 110+ se aleja demasiado del benchmark.",
        "Numero de estratos year_id x sex_id x location_id con fuente benchmark efectiva registrada.",
        "Numero de estratos donde se detecto uso de la fila abierta 110+ de mortalidad como input de modelamiento.",
        "Numero de estratos con muertes observadas 110+ y poblacion contractual 110+ igual a cero despues del ajuste minimo.",
        "Numero de estratos donde se aplico el piso minimo contractual de 110+ por coherencia cross-repo.",
        "Masa total agregada al contractual 110+ por la salvaguarda de coherencia cross-repo.",
        "Numero de celdas faltantes en la comparacion nacional oficial vs suma departamental.",
        "Numero de celdas con diferencia detectiva entre nacional oficial y suma departamental.",
        "Numero de estratos donde age=110 contractual no coincide con el colapso exacto 110+."
      )
    )
  )
  fwrite(qc_summary_dict, sub("\\.csv$", "_diccionario_ext.csv", QC_SUMMARY_FP))

  dict <- dict_from_spec(SPEC, dataset_version = dataset_version, run_id = run_id, config_dir = P$CONFIG_DIR)
  dict_ext <- enrich_dict_with_stats(dict, dt)
  fwrite(dict_ext, DICT_FP)

  internal_meta <- data.table(
    column_name = c("age", "population"),
    label = c("Edad simple interna 0-125", "Poblacion esperada interna"),
    description = c(
      "Edad simple del modelo interno. Se exporta 0-109 y age=110 como 110+ en el contractual.",
      "Conteo esperado interno, puede incluir fracciones menores que 1 en edades extremas."
    ),
    units = c("years", "persons"),
    allow_na = c(FALSE, FALSE)
  )
  internal_dict <- make_table_dictionary(
    data = internal_dt,
    table_name = "population_modeled_internal_0_125",
    dataset_id = dataset_id,
    version = dataset_version,
    run_id = run_id,
    key_cols = pk,
    metadata = internal_meta
  )
  fwrite(internal_dict, INTERNAL_DICT_FP)

  bridge_meta <- data.table(
    column_name = c("age", "population"),
    label = c("Edad contractual en cola", "Poblacion contractual puente"),
    description = c(
      "Edades 80-109 simples y age=110 como 110+ despues del redondeo Hamilton.",
      "Conteo entero contractual usado para construir la cola final exportada."
    ),
    units = c("years", "persons"),
    allow_na = c(FALSE, FALSE)
  )
  bridge_dict <- make_table_dictionary(
    data = bridge_dt,
    table_name = "population_tail_contract_bridge_80_109_110plus",
    dataset_id = dataset_id,
    version = dataset_version,
    run_id = run_id,
    key_cols = pk,
    metadata = bridge_meta
  )
  fwrite(bridge_dict, BRIDGE_DICT_FP)

  benchmark_meta <- data.table(
    column_name = c("location_id", "age", "qx_benchmark", "mx_benchmark", "tail_weight", "benchmark_source", "source_effective", "kannisto_intercept", "kannisto_slope", "benchmark_observed_age_max", "used_open_110plus_row", "fit_age_min", "fit_age_max"),
    label = c("Ubicacion benchmark", "Edad simple interna 80-125", "qx benchmark", "mx benchmark", "Peso de cola benchmark", "Fuente benchmark", "Fuente efectiva", "Intercepto Kannisto", "Pendiente Kannisto", "Edad maxima cerrada usada", "Uso de 110+ abierto", "Edad minima de ajuste", "Edad maxima de ajuste"),
    description = c(
      "Ubicacion para la que se construyo el benchmark de cola alta.",
      "Edad simple del benchmark externo anual usado para distribuir la masa 80 y +.",
      "Probabilidad anual de morir usada para derivar la supervivencia de la cola.",
      "Tasa central de mortalidad anual implicita para el benchmark de cola.",
      "Peso de supervivencia normalizado que reparte la masa observada 80 y +.",
      "Fuente o regla usada para construir el benchmark anual.",
      "Clasificacion operativa: tabla oficial regional, nacional implicito o fallback WPP.",
      "Intercepto del ajuste logit(qx) ~ age usado para extender la cola.",
      "Pendiente del ajuste Kannisto usado para extender la cola.",
      "Ultima edad cerrada de mortalidad usada directamente antes de la extension interna.",
      "TRUE si se hubiera usado la fila abierta 110+ de mortalidad como input de modelamiento; debe ser FALSE.",
      "Edad minima de las filas cerradas usadas en el ajuste Kannisto.",
      "Edad maxima de las filas cerradas usadas en el ajuste Kannisto."
    ),
    units = c(NA_character_, "years", "probability", "rate", "share", NA_character_, NA_character_, NA_character_, NA_character_, "years", NA_character_, "years", "years"),
    allow_na = c(FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, TRUE, FALSE, FALSE, FALSE, FALSE)
  )
  benchmark_dict <- make_table_dictionary(
    data = benchmark_dt,
    table_name = "population_tail_external_benchmark_peru_80_125",
    dataset_id = dataset_id,
    version = dataset_version,
    run_id = run_id,
    key_cols = c("year_id", "sex_id", "location_id", "age"),
    metadata = benchmark_meta
  )
  fwrite(benchmark_dict, BENCHMARK_DICT_FP)

  adjust_dict <- make_table_dictionary(
    data = adjust_dt,
    table_name = "population_crossrepo_110plus_adjustment",
    dataset_id = dataset_id,
    version = dataset_version,
    run_id = run_id,
    key_cols = c("year_id", "sex_id", "location_id"),
    metadata = data.table(
      column_name = c("population_110plus_before_floor", "death_count_110plus_observed", "has_death_110plus_observed", "source_dataset_version", "source_run_id", "crossrepo_110plus_qc_status", "coherence_floor_required", "coherence_floor_applied", "population_110plus_after_floor", "mass_adjustment_from_crossrepo_qc", "flag_incoherent"),
      label = c("Poblacion 110+ antes del piso", "Muertes observadas 110+", "Hay muertes observadas 110+", "Version dataset fuente", "Run fuente", "Estado QC cross-repo", "Piso requerido", "Piso aplicado", "Poblacion 110+ despues del piso", "Masa agregada por coherencia", "Flag incoherente"),
      description = c(
        "Conteo contractual original en age=110 antes de aplicar la salvaguarda cross-repo.",
        "Numero de muertes observadas 110+ en el snapshot agregado de mortalidad.",
        "TRUE si el snapshot de mortalidad reporta al menos una muerte observada 110+ en el estrato.",
        "Version declarada del snapshot externo usado para la coherencia 110+.",
        "Run ID del snapshot externo usado para la coherencia 110+.",
        "Indica si el chequeo cross-repo fue aplicado o se omitiÃ³ por falta de snapshot.",
        "TRUE si el estrato tenia muertes observadas 110+ y poblacion contractual 110+ igual a cero.",
        "TRUE si se elevo el contractual 110+ al minimo entero 1.",
        "Conteo contractual final en age=110 despues de aplicar la salvaguarda cross-repo.",
        "Ajuste neto agregado al contractual 110+ por coherencia cross-repo.",
        "TRUE si aun quedan muertes observadas 110+ con poblacion contractual 110+ igual a cero."
      )
    )
  )
  fwrite(adjust_dict, ADJUST_DICT_FP)

  qc_align_dict <- make_table_dictionary(
    data = qc_tail_align,
    table_name = "qc_tail_external_alignment_national",
    dataset_id = dataset_id,
    version = dataset_version,
    run_id = run_id,
    key_cols = c("year_id", "sex_id", "location_id", "age"),
    metadata = data.table(
      column_name = c("population_internal", "internal_share", "benchmark_tail_weight", "qx_benchmark", "mx_benchmark", "benchmark_source", "source_effective", "share_diff", "flag_diff"),
      label = c("Poblacion interna", "Share interno", "Share benchmark", "qx benchmark", "mx benchmark", "Fuente benchmark", "Fuente efectiva", "Diferencia de share", "Flag de diferencia"),
      description = c(
        "Poblacion interna del estrato para la edad exacta.",
        "Participacion de la edad dentro de la masa interna 80-125 del estrato.",
        "Participacion benchmark derivada de la schedule externa 80-125 del estrato.",
        "Probabilidad benchmark anual de morir usada en la cola alta.",
        "Tasa central de mortalidad benchmark usada en la extension.",
        "Fuente o regla usada para construir la schedule anual.",
        "Clasificacion operativa del benchmark del estrato.",
        "Diferencia entre el share interno y el share benchmark.",
        "TRUE si la cola interna del estrato se desvía del benchmark."
      )
    )
  )
  fwrite(qc_align_dict, sub("\\.csv$", "_diccionario_ext.csv", QC_TAIL_ALIGN_FP))

  qc_align_dict <- make_table_dictionary(
    data = qc_tail_align,
    table_name = "qc_tail_external_alignment_national",
    dataset_id = dataset_id,
    version = dataset_version,
    run_id = run_id,
    key_cols = c("year_id", "sex_id", "location_id", "age"),
    metadata = data.table(
      column_name = c("population_internal", "internal_share", "benchmark_tail_weight", "qx_benchmark", "mx_benchmark", "benchmark_source", "source_effective", "benchmark_observed_age_max", "align_required", "share_diff", "flag_diff"),
      label = c("Poblacion interna", "Share interno", "Share benchmark", "qx benchmark", "mx benchmark", "Fuente benchmark", "Fuente efectiva", "Edad maxima cerrada benchmark", "Fila evaluada en alineacion", "Diferencia de share", "Flag de diferencia"),
      description = c(
        "Poblacion interna del estrato para la edad exacta.",
        "Participacion de la edad dentro de la masa interna 80-125 del estrato.",
        "Participacion benchmark derivada de la schedule externa 80-125 del estrato.",
        "Probabilidad benchmark anual de morir usada en la cola alta.",
        "Tasa central de mortalidad benchmark usada en la extension.",
        "Fuente o regla usada para construir la schedule anual.",
        "Clasificacion operativa del benchmark del estrato.",
        "Ultima edad cerrada tomada del benchmark externo antes de extender la cola.",
        "TRUE cuando la fila debe entrar al chequeo de alineacion; en benchmarks oficiales se limita a 80-109.",
        "Diferencia entre el share interno y el share benchmark.",
        "TRUE si la cola interna del estrato se desvia del benchmark."
      )
    )
  )
  fwrite(qc_align_dict, sub("\\.csv$", "_diccionario_ext.csv", QC_TAIL_ALIGN_FP))

  qc_share_dict <- make_table_dictionary(
    data = qc_tail_share,
    table_name = "qc_tail_share_110plus",
    dataset_id = dataset_id,
    version = dataset_version,
    run_id = run_id,
    key_cols = c("year_id", "sex_id", "location_id"),
    metadata = data.table(
      column_name = c("pop_observed_80plus", "pop_contract_110plus", "pop_internal_110plus", "benchmark_share_110plus", "benchmark_pop_110plus", "contract_share_110plus", "internal_share_110plus", "contract_vs_benchmark_diff", "internal_vs_benchmark_diff", "flag_contract_far"),
      label = c("Masa observada 80+", "Poblacion contractual 110+", "Poblacion interna 110+", "Share benchmark 110+", "Poblacion benchmark 110+", "Share contractual 110+", "Share interno 110+", "Delta contractual vs benchmark", "Delta interno vs benchmark", "Flag contractual lejos"),
      description = c(
        "Grupo abierto observado 80 y + antes de redistribuir la cola.",
        "Conteo contractual publicado en age=110.",
        "Suma interna 110-125 antes del redondeo contractual final.",
        "Participacion benchmark esperada de 110+ dentro de 80+ para ese estrato.",
        "Conteo benchmark esperado de 110+ si se aplica la schedule externa al estrato.",
        "Participacion contractual observada de 110+ dentro de la masa 80+.",
        "Participacion interna de 110+ dentro de la masa 80+.",
        "Diferencia entre el conteo contractual 110+ y el benchmark del estrato.",
        "Diferencia entre el conteo interno 110+ y el benchmark del estrato.",
        "TRUE si el share contractual queda demasiado lejos del benchmark."
      )
    )
  )
  fwrite(qc_share_dict, sub("\\.csv$", "_diccionario_ext.csv", QC_TAIL_SHARE_FP))

  qc_priority_dict <- make_table_dictionary(
    data = qc_tail_priority,
    table_name = "qc_tail_visual_priority",
    dataset_id = dataset_id,
    version = dataset_version,
    run_id = run_id,
    key_cols = c("year_id", "sex_id", "location_id"),
    metadata = data.table(
      column_name = c("visual_priority_score", "rank_visual_priority"),
      label = c("Score de prioridad visual", "Rank de prioridad visual"),
      description = c(
        "Puntaje heuristico para decidir que estratos revisar primero en inspeccion humana.",
        "Orden sugerido de revision visual, de mayor a menor prioridad."
      )
    )
  )
  fwrite(qc_priority_dict, sub("\\.csv$", "_diccionario_ext.csv", QC_TAIL_PRIORITY_FP))

  qc_source_dict <- make_table_dictionary(
    data = qc_tail_source,
    table_name = "qc_tail_benchmark_source_by_stratum",
    dataset_id = dataset_id,
    version = dataset_version,
    run_id = run_id,
    key_cols = c("year_id", "sex_id", "location_id"),
    metadata = data.table(
      column_name = c("benchmark_source", "source_effective"),
      label = c("Fuente benchmark", "Fuente efectiva"),
      description = c(
        "Descripcion de la fuente o regla usada para construir la schedule de cola alta.",
        "Clasificacion operativa del benchmark del estrato: oficial regional, nacional implicito o fallback WPP."
      )
    )
  )
  fwrite(qc_source_dict, sub("\\.csv$", "_diccionario_ext.csv", QC_TAIL_SOURCE_FP))

  qc_source_dict <- make_table_dictionary(
    data = qc_tail_source,
    table_name = "qc_tail_benchmark_source_by_stratum",
    dataset_id = dataset_id,
    version = dataset_version,
    run_id = run_id,
    key_cols = c("year_id", "sex_id", "location_id"),
    metadata = data.table(
      column_name = c("benchmark_source", "source_effective", "benchmark_observed_age_max", "used_open_110plus_row", "fit_age_min", "fit_age_max"),
      label = c("Fuente benchmark", "Fuente efectiva", "Edad maxima cerrada usada", "Uso de 110+ abierto", "Edad minima de ajuste", "Edad maxima de ajuste"),
      description = c(
        "Descripcion de la fuente o regla usada para construir la schedule de cola alta.",
        "Clasificacion operativa del benchmark del estrato: oficial regional, nacional implicito o fallback WPP.",
        "Ultima edad cerrada tomada del benchmark externo antes de la extension interna.",
        "TRUE si se hubiera usado la fila abierta 110+ de mortalidad como input de modelamiento; debe ser FALSE.",
        "Edad minima de las filas cerradas usadas en el ajuste Kannisto.",
        "Edad maxima de las filas cerradas usadas en el ajuste Kannisto."
      )
    )
  )
  fwrite(qc_source_dict, sub("\\.csv$", "_diccionario_ext.csv", QC_TAIL_SOURCE_FP))

  qc_open_excl_dict <- make_table_dictionary(
    data = qc_tail_open_excl,
    table_name = "qc_tail_open_interval_exclusion",
    dataset_id = dataset_id,
    version = dataset_version,
    run_id = run_id,
    key_cols = c("year_id", "sex_id", "location_id"),
    metadata = data.table(
      column_name = c("benchmark_source", "source_effective", "benchmark_observed_age_max", "used_open_110plus_row", "fit_age_min", "fit_age_max", "flag_diff"),
      label = c("Fuente benchmark", "Fuente efectiva", "Edad maxima cerrada usada", "Uso de 110+ abierto", "Edad minima de ajuste", "Edad maxima de ajuste", "Flag de diferencia"),
      description = c(
        "Descripcion de la fuente usada para construir la cola benchmark del estrato.",
        "Clasificacion operativa del benchmark del estrato.",
        "Ultima edad cerrada tomada del benchmark externo antes de la extension interna.",
        "TRUE si se detecta uso de la fila abierta 110+ como input de modelamiento; debe ser FALSE.",
        "Edad minima de las filas cerradas usadas en el ajuste Kannisto.",
        "Edad maxima de las filas cerradas usadas en el ajuste Kannisto.",
        "TRUE si el estrato viola la regla de exclusion del intervalo abierto."
      )
    )
  )
  fwrite(qc_open_excl_dict, sub("\\.csv$", "_diccionario_ext.csv", QC_TAIL_OPEN_EXCL_FP))

  qc_crossrepo_coh_dict <- make_table_dictionary(
    data = qc_crossrepo_coh,
    table_name = "qc_crossrepo_110plus_coherence",
    dataset_id = dataset_id,
    version = dataset_version,
    run_id = run_id,
    key_cols = c("year_id", "sex_id", "location_id"),
    metadata = data.table(
      column_name = c("death_count_110plus_observed", "has_death_110plus_observed", "population_110plus_contract", "coherence_floor_required", "coherence_floor_applied", "mass_adjustment_from_crossrepo_qc", "crossrepo_110plus_qc_status", "source_dataset_version", "source_run_id", "flag_incoherent"),
      label = c("Muertes observadas 110+", "Hay muertes observadas 110+", "Poblacion contractual 110+", "Piso requerido", "Piso aplicado", "Masa agregada por coherencia", "Estado QC cross-repo", "Version dataset fuente", "Run fuente", "Flag incoherente"),
      description = c(
        "Conteo agregado de muertes observadas 110+ del snapshot externo de mortalidad.",
        "TRUE si existe al menos una muerte observada 110+ en el estrato.",
        "Conteo contractual final publicado en age=110.",
        "TRUE si habia muertes observadas 110+ y la poblacion contractual previa era cero.",
        "TRUE si se elevo el contractual 110+ al minimo entero 1.",
        "Masa agregada al contractual 110+ por la salvaguarda de coherencia cross-repo.",
        "Estado del chequeo cross-repo: aplicado/revisado o skipped_no_snapshot.",
        "Version del snapshot externo de mortalidad usado.",
        "Run ID del snapshot externo de mortalidad usado.",
        "TRUE si persisten muertes observadas 110+ con poblacion contractual 110+ igual a cero."
      )
    )
  )
  fwrite(qc_crossrepo_coh_dict, sub("\\.csv$", "_diccionario_ext.csv", QC_CROSSREPO_COH_FP))

  qc_crossrepo_mass_dict <- make_table_dictionary(
    data = qc_crossrepo_mass,
    table_name = "qc_crossrepo_mass_adjustment",
    dataset_id = dataset_id,
    version = dataset_version,
    run_id = run_id,
    metadata = data.table(
      column_name = c("n_strata", "n_snapshot_rows", "n_snapshot_skipped", "n_floor_required", "n_floor_applied", "total_mass_adjustment", "n_incoherent_after_floor"),
      label = c("Estratos evaluados", "Estratos con snapshot", "Estratos sin snapshot", "Estratos con piso requerido", "Estratos con piso aplicado", "Masa agregada total", "Estratos incoherentes tras ajuste"),
      description = c(
        "Numero total de estratos year_id x sex_id x location_id evaluados en la salvaguarda 110+.",
        "Numero de estratos evaluados usando un snapshot externo valido.",
        "Numero de estratos donde no hubo snapshot y el chequeo cross-repo se reporto como omitido.",
        "Numero de estratos donde habia muertes observadas 110+ y poblacion contractual 110+ igual a cero antes del ajuste.",
        "Numero de estratos donde se aplico el piso minimo entero 1.",
        "Cantidad total agregada a la masa contractual 110+ por coherencia cross-repo.",
        "Numero de estratos que seguirian incoherentes luego del ajuste; debe ser cero."
      )
    )
  )
  fwrite(qc_crossrepo_mass_dict, sub("\\.csv$", "_diccionario_ext.csv", QC_CROSSREPO_MASS_FP))

  register_artifact(dataset_id, table_name, dataset_version, run_id,
                    artifact_type = "final_dataset",
                    artifact_path = FINAL_FP,
                    n_rows = nrow(dt), n_cols = ncol(dt),
                    notes = "Dataset contractual: edades 0-109 simples y age=110 como grupo abierto 110+.")

  register_artifact(dataset_id, "population_modeled_internal_0_125", dataset_version, run_id,
                    artifact_type = "derived_dataset",
                    artifact_path = INTERNAL_FP,
                    n_rows = nrow(internal_dt), n_cols = ncol(internal_dt),
                    notes = "Modelo interno esperado de cola 80-125 con tope nacional en edad 125.")

  register_artifact(dataset_id, "population_tail_contract_bridge_80_109_110plus", dataset_version, run_id,
                    artifact_type = "derived_dataset",
                    artifact_path = BRIDGE_FP,
                    n_rows = nrow(bridge_dt), n_cols = ncol(bridge_dt),
                    notes = "Puente contractual entero de cola 80-109 y 110+ despues del redondeo Hamilton.")

  register_artifact(dataset_id, "population_tail_external_benchmark_peru_80_125", dataset_version, run_id,
                    artifact_type = "derived_dataset",
                    artifact_path = BENCHMARK_FP,
                    n_rows = nrow(benchmark_dt), n_cols = ncol(benchmark_dt),
                    notes = "Benchmark de cola 80-125 por estrato: tabla oficial regional all_years usada solo en edades cerradas 80-109 cuando existe, nacional implicito para location_id=0 y fallback WPP solo cuando falta cobertura. La fila abierta 110+ de mortalidad no se usa como input de modelamiento.")

  register_artifact(dataset_id, "population_crossrepo_110plus_adjustment", dataset_version, run_id,
                    artifact_type = "derived_dataset",
                    artifact_path = ADJUST_FP,
                    n_rows = nrow(adjust_dt), n_cols = ncol(adjust_dt),
                    notes = "Trazabilidad del piso minimo contractual 110+ aplicado por coherencia cross-repo con mortalidad observada.")

  register_artifact(dataset_id, table_name, dataset_version, run_id,
                    artifact_type = "dictionary_ext",
                    artifact_path = DICT_FP,
                    n_rows = nrow(dict_ext), n_cols = ncol(dict_ext),
                    notes = "Diccionario contractual con age=110 documentado como 110+.")

  register_artifact(dataset_id, "population_modeled_internal_0_125", dataset_version, run_id,
                    artifact_type = "dictionary_ext",
                    artifact_path = INTERNAL_DICT_FP,
                    n_rows = nrow(internal_dict), n_cols = ncol(internal_dict),
                    notes = "Diccionario del modelo interno 0-125.")

  register_artifact(dataset_id, "population_tail_contract_bridge_80_109_110plus", dataset_version, run_id,
                    artifact_type = "dictionary_ext",
                    artifact_path = BRIDGE_DICT_FP,
                    n_rows = nrow(bridge_dict), n_cols = ncol(bridge_dict),
                    notes = "Diccionario del puente contractual de cola.")

  register_artifact(dataset_id, "population_tail_external_benchmark_peru_80_125", dataset_version, run_id,
                    artifact_type = "dictionary_ext",
                    artifact_path = BENCHMARK_DICT_FP,
                    n_rows = nrow(benchmark_dict), n_cols = ncol(benchmark_dict),
                    notes = "Diccionario del benchmark externo Peru 80-125.")

  register_artifact(dataset_id, "population_crossrepo_110plus_adjustment", dataset_version, run_id,
                    artifact_type = "dictionary_ext",
                    artifact_path = ADJUST_DICT_FP,
                    n_rows = nrow(adjust_dict), n_cols = ncol(adjust_dict),
                    notes = "Diccionario de la trazabilidad del ajuste cross-repo 110+.")

  for (fp in c(QC_SUMMARY_FP, QC_DUP_FP, QC_MISS_FP, QC_NEG_FP, QC_TAIL_FP, QC_TAIL_MASS_FP,
               QC_TAIL_CAP_FP, QC_TAIL_ALIGN_FP, QC_TAIL_SHARE_FP, QC_TAIL_PRIORITY_FP, QC_TAIL_SOURCE_FP, QC_TAIL_OPEN_EXCL_FP,
               QC_CROSSREPO_COH_FP, QC_CROSSREPO_MASS_FP, QC_NAT_VS_DEPFP, QC_COLLAPSE_FP)) {
    register_artifact(dataset_id, table_name, dataset_version, run_id,
                      artifact_type = "qc",
                      artifact_path = fp,
                      notes = paste("QC del dataset contractual:", basename(fp)))
  }

  register_artifact(dataset_id, table_name, dataset_version, run_id,
                    artifact_type = "spec",
                    artifact_path = SPEC_PATH,
                    notes = "Spec YAML usado para validar contrato y semantica 110+.")

  loc_fp <- file.path(P$CONFIG_DIR, "maestro_location_dept.csv")
  if (file.exists(loc_fp)) {
    register_artifact(dataset_id, table_name, dataset_version, run_id,
                      artifact_type = "master",
                      artifact_path = loc_fp,
                      notes = "Maestro UBIGEO depto usado para labels en diccionario_ext.")
  }

  register_run_finish(run_id, status = "success")

  cat("\n=== QC SUMMARY (", dataset_id, ") ===\n", sep = "")
  print(qc_summary)
  cat("\nArtefactos:\n")
  cat(" - FINAL contractual     : ", FINAL_FP, "\n", sep = "")
  cat(" - INTERNO 0-125         : ", INTERNAL_FP, "\n", sep = "")
  cat(" - PUENTE contractual    : ", BRIDGE_FP, "\n", sep = "")
  cat(" - BENCHMARK externo     : ", BENCHMARK_FP, "\n", sep = "")
  cat(" - AJUSTE cross-repo     : ", ADJUST_FP, "\n", sep = "")
  cat(" - QC masa 80+ exacta    : ", QC_TAIL_MASS_FP, "\n", sep = "")
  cat(" - QC tope nacional 125  : ", QC_TAIL_CAP_FP, "\n", sep = "")
  cat(" - QC alineacion externa : ", QC_TAIL_ALIGN_FP, "\n", sep = "")
  cat(" - QC share 110+         : ", QC_TAIL_SHARE_FP, "\n", sep = "")
  cat(" - QC exclusion 110+     : ", QC_TAIL_OPEN_EXCL_FP, "\n", sep = "")
  cat(" - QC coherencia xrepo   : ", QC_CROSSREPO_COH_FP, "\n", sep = "")
  cat(" - QC colapso 110+ exact : ", QC_COLLAPSE_FP, "\n", sep = "")
}, error = function(e) {
  register_run_finish(run_id, status = "failed", message = as.character(e$message))
  stop(e)
})
