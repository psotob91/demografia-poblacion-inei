#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(yaml)
  library(here)
})

source(here("R", "io_utils.R"))
source(here("R", "catalog_utils.R"))
source(here("R", "dictionary_utils.R"))

run_id <- paste0("refresh_external_benchmarks_", format(Sys.time(), "%Y%m%d_%H%M%S"))
dataset_id <- "inei_population_1995_2030"
dataset_version <- "v1.0.0"
run_ok <- FALSE

register_run_start(run_id, dataset_id, dataset_version)
on.exit({
  if (!run_ok) {
    register_run_finish(run_id, "failed", "refresh_external_benchmarks aborted")
  }
}, add = TRUE)

P <- ensure_project_dirs_inei()

source_fp <- file.path(
  "..", "tabla-mortalidad-peru", "data", "final",
  "life_table_mortality", "all_years", "single_age",
  "ref_life_table_mortality_single_age.csv"
)

if (!file.exists(source_fp)) {
  stop("No se encontro la fuente externa esperada para refrescar benchmarks: ", normalizePath(source_fp, winslash = "/", mustWork = FALSE))
}

target_fp <- file.path(P$BENCHMARK_DIR, "peru_life_table_all_years_closed_80_109.csv")
meta_fp <- file.path(P$BENCHMARK_DIR, "peru_life_table_all_years_closed_80_109_source.yml")

src <- fread(
  source_fp,
  select = c(
    "year_id", "location_id", "sex_id", "age_start", "mx", "qx", "lx", "Lx",
    "age_interval_open", "life_table_label", "source_year_left", "source_year_right"
  ),
  showProgress = FALSE
)

bench <- src[
  location_id %in% 1:25 &
    age_start >= 80 & age_start <= 109 &
    age_interval_open == FALSE,
  .(
    year_id = as.integer(year_id),
    location_id = as.integer(location_id),
    sex_id = as.integer(sex_id),
    age = as.integer(age_start),
    mx = as.numeric(mx),
    qx = as.numeric(qx),
    lx = as.numeric(lx),
    Lx = as.numeric(Lx),
    age_interval_open = FALSE,
    life_table_label = as.character(life_table_label),
    source_year_left = as.integer(source_year_left),
    source_year_right = as.integer(source_year_right)
  )
][order(year_id, location_id, sex_id, age)]

expected_rows <- 31L * 25L * 2L * 30L
if (nrow(bench) != expected_rows) {
  stop("Benchmark externo filtrado tiene ", nrow(bench), " filas; se esperaban ", expected_rows, ".")
}

dup_n <- nrow(bench[, .N, by = .(year_id, location_id, sex_id, age)][N > 1L])
if (dup_n > 0L) {
  stop("Benchmark externo filtrado tiene duplicados por year_id, location_id, sex_id, age.")
}

fwrite(bench, target_fp)

meta <- list(
  benchmark_id = "peru_life_table_all_years_closed_80_109",
  source_repo = "tabla-mortalidad-peru",
  source_path = normalizePath(source_fp, winslash = "/", mustWork = TRUE),
  extracted_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  coverage = list(
    year_id = "1995:2025",
    location_id = "1:25",
    sex_id = c(8507L, 8532L),
    age = "80:109"
  ),
  semantics = list(
    open_interval_used = FALSE,
    note = "Benchmark local cerrado 80:109 derivado desde tabla-mortalidad-peru. La fila abierta 110+ no se copia ni se usa como input de modelamiento."
  )
)
yaml::write_yaml(meta, meta_fp)

dict <- make_table_dictionary(
  data = bench,
  table_name = "peru_life_table_all_years_closed_80_109",
  dataset_id = dataset_id,
  version = dataset_version,
  run_id = run_id,
  key_cols = c("year_id", "location_id", "sex_id", "age"),
  metadata = data.table(
    column_name = c("year_id", "location_id", "sex_id", "age", "mx", "qx", "lx", "Lx", "age_interval_open", "life_table_label", "source_year_left", "source_year_right"),
    label = c("Ano calendario", "Departamento", "Sexo", "Edad cerrada", "mx benchmark", "qx benchmark", "lx benchmark", "Lx benchmark", "Intervalo abierto", "Etiqueta de tabla de vida", "Ano fuente izquierdo", "Ano fuente derecho"),
    description = c(
      "Ano calendario del benchmark oficial regional.",
      "Identificador departamental 1:25 del benchmark oficial regional.",
      "Sexo OMOP-like del benchmark oficial regional.",
      "Edad cerrada usada como benchmark de cola alta.",
      "Tasa central de mortalidad tomada del benchmark oficial regional.",
      "Probabilidad anual de morir tomada del benchmark oficial regional.",
      "Sobrevivientes de la tabla de vida oficial regional.",
      "Exposicion/sobrevivientes promedio de la tabla de vida oficial regional.",
      "Indicador de intervalo abierto; en este benchmark debe ser siempre FALSE.",
      "Etiqueta de la tabla de vida de origen.",
      "Ano izquierdo del bloque fuente usado upstream.",
      "Ano derecho del bloque fuente usado upstream."
    ),
    units = c(NA, NA, NA, "years", NA, NA, "survivors", "person-years", NA, NA, NA, NA),
    allow_na = c(FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE)
  )
)
fwrite(dict, dictionary_path_for_table(target_fp))

register_artifact(
  dataset_id = dataset_id,
  table_name = "peru_life_table_all_years_closed_80_109",
  version = dataset_version,
  run_id = run_id,
  artifact_type = "raw_benchmark",
  artifact_path = target_fp,
  n_rows = nrow(bench),
  n_cols = ncol(bench),
  notes = "Benchmark local cerrado 80:109 derivado desde tabla-mortalidad-peru para desacoplar dependencia runtime."
)
register_artifact(
  dataset_id = dataset_id,
  table_name = "peru_life_table_all_years_closed_80_109",
  version = dataset_version,
  run_id = run_id,
  artifact_type = "dictionary_ext",
  artifact_path = dictionary_path_for_table(target_fp),
  n_rows = nrow(dict),
  n_cols = ncol(dict),
  notes = "Diccionario extendido del benchmark local desacoplado."
)
register_artifact(
  dataset_id = dataset_id,
  table_name = "peru_life_table_all_years_closed_80_109_source",
  version = dataset_version,
  run_id = run_id,
  artifact_type = "spec",
  artifact_path = meta_fp,
  n_rows = NA_integer_,
  n_cols = NA_integer_,
  notes = "Metadata de origen del benchmark local desacoplado."
)

run_ok <- TRUE
register_run_finish(run_id, "success", "refresh_external_benchmarks completed")
message("Benchmark local refrescado: ", target_fp)
