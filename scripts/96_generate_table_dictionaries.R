# scripts/96_generate_table_dictionaries.R
# ------------------------------------------------------------------------------
# Generate dictionaries for pipeline tabular artifacts.
# ------------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(here)
})

source(here("R/dictionary_utils.R"))
source(here("R/catalog_utils.R"))

`%||%` <- function(x, y) if (is.null(x)) y else x

dataset_id <- "inei_population_1995_2030"
dataset_version <- "v1.0.0"
run_id <- format(Sys.time(), "%Y%m%d_%H%M%S")

read_table <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "parquet") return(as.data.table(arrow::read_parquet(path)))
  if (ext == "csv") return(data.table::fread(path))
  stop("Unsupported table extension for dictionary: ", path)
}

table_name_from_path <- function(path) {
  tools::file_path_sans_ext(basename(path))
}

base_meta <- data.table(
  column_name = c(
    "year_id", "age", "sex_id", "location_id", "population",
    "location_name", "ubigeo_dept_str", "level", "source_file", "source_sheet",
    "sheet", "age_label", "population_raw", "gender_source_value", "age_type",
    "age_group", "age_group_start", "age_group_end", "age_group_open", "url", "destfile",
    "started_at", "ended_at", "status", "error_message", "parse_status", "parse_error"
  ),
  label = c(
    "Año calendario", "Edad simple", "Sexo", "Ubicación", "Población",
    "Nombre de ubicación", "UBIGEO departamental", "Nivel geográfico", "Archivo fuente", "Hoja fuente",
    "Hoja fuente", "Etiqueta de edad", "Población raw", "Sexo fuente", "Tipo de edad",
    "Grupo de edad", "Inicio de grupo de edad", "Fin de grupo de edad", "Grupo abierto", "URL", "Archivo local",
    "Inicio", "Fin", "Estado", "Mensaje de error", "Estado de parseo", "Error de parseo"
  ),
  description = c(
    "Año calendario de la estimación.",
    "Edad simple en años cumplidos.",
    "Identificador OMOP-like de sexo usado por el proyecto.",
    "Identificador de ubicación del proyecto.",
    "Conteo absoluto de población.",
    "Nombre de la ubicación según maestro del proyecto.",
    "Código departamental en dos dígitos.",
    "Nivel geográfico de la fila.",
    "Archivo Excel fuente del INEI.",
    "Hoja del archivo Excel fuente.",
    "Hoja del archivo Excel fuente.",
    "Etiqueta de edad como aparece en la fuente.",
    "Conteo poblacional antes de normalización final.",
    "Código de sexo inferido desde la hoja fuente.",
    "Clasificación operativa de edad.",
    "Etiqueta de grupo de edad cuando no es edad simple.",
    "Edad inicial del grupo.",
    "Edad final del grupo cuando existe cierre superior explicito.",
    "Indica si el grupo observado es abierto, por ejemplo 80 y +.",
    "URL de descarga.",
    "Ruta local del archivo.",
    "Timestamp de inicio.",
    "Timestamp de término.",
    "Estado de la operación.",
    "Mensaje de error si aplica.",
    "Estado del parseo de hoja.",
    "Error de parseo si aplica."
  ),
  units = c(
    NA, "years", NA, NA, "persons",
    NA, NA, NA, NA, NA,
    NA, NA, "persons", NA, NA,
    NA, "years", "years", NA, NA, NA,
    NA, NA, NA, NA, NA, NA
  ),
  allow_na = NA
)

required_tables <- c(
  "data/derived/staging/inei_population/download_log.csv",
  "data/derived/staging/inei_population/parse_log.csv",
  "data/derived/staging/inei_population/raw_long.parquet",
  "data/derived/staging/inei_population/omop_like_long.parquet",
  "data/derived/staging/inei_population/population_modeled_internal_0_125.parquet",
  "data/derived/staging/inei_population/population_crossrepo_110plus_adjustment.parquet",
  "data/derived/staging/inei_population/population_tail_external_benchmark_peru_80_125.parquet",
  "data/derived/staging/inei_population/population_tail_contract_bridge_80_109_110plus.parquet",
  "data/derived/staging/inei_population/population_national_from_dept.parquet",
  "data/final/population_inei/population_result.parquet",
  "data/final/population_inei/population_result_hierarchical.parquet",
  "data/derived/qc/inei_population/qc_summary.csv",
  "data/derived/qc/inei_population/qc_duplicates.csv",
  "data/derived/qc/inei_population/qc_missing_required.csv",
  "data/derived/qc/inei_population/qc_negative_population.csv",
  "data/derived/qc/inei_population/qc_tail_monotone_flags.csv",
  "data/derived/qc/inei_population/qc_tail_mass_80plus_exact.csv",
  "data/derived/qc/inei_population/qc_tail_cap_125_national.csv",
  "data/derived/qc/inei_population/qc_crossrepo_110plus_coherence.csv",
  "data/derived/qc/inei_population/qc_crossrepo_mass_adjustment.csv",
  "data/derived/qc/inei_population/qc_110plus_collapse_exact.csv",
  "data/derived/qc/inei_population/qc_national_vs_dept_sum.csv",
  "data/derived/qc/inei_population/hierarchical/qc_hierarchical_summary.csv",
  "data/derived/qc/inei_population/hierarchical/qc_hierarchical_missing_required.csv",
  "data/derived/qc/inei_population/hierarchical/qc_hierarchical_duplicates.csv",
  "data/derived/qc/inei_population/hierarchical/qc_hierarchical_negative_population.csv",
  "data/derived/qc/inei_population/hierarchical/qc_hierarchical_national_additive_check.csv",
  "data/_catalog/catalogo_artefactos.csv",
  "data/_catalog/provenance_runs.csv"
)

optional_tables <- c(
  "data/derived/qc/inei_population/contract_fingerprint_baseline.csv",
  "data/derived/qc/inei_population/contract_fingerprint_post.csv"
)

expected_tables <- c(required_tables, optional_tables)

key_map <- list(
  population_result = c("year_id", "age", "sex_id", "location_id"),
  population_result_hierarchical = c("year_id", "age", "sex_id", "location_id"),
  population_national_from_dept = c("year_id", "age", "sex_id", "location_id"),
  population_modeled_internal_0_125 = c("year_id", "age", "sex_id", "location_id"),
  population_crossrepo_110plus_adjustment = c("year_id", "sex_id", "location_id"),
  population_tail_contract_bridge_80_109_110plus = c("year_id", "age", "sex_id", "location_id")
)

register_run_start(run_id, dataset_id, dataset_version)

summary <- rbindlist(lapply(expected_tables, function(path) {
  if (!file.exists(path)) {
    status <- if (path %in% optional_tables) "SKIPPED_OPTIONAL_MISSING_TABLE" else "MISSING_TABLE"
    return(data.table(table_path = path, dictionary_path = NA_character_, status = status))
  }
  dt <- read_table(path)
  table_name <- table_name_from_path(path)
  dict <- make_table_dictionary(
    data = dt,
    table_name = table_name,
    dataset_id = dataset_id,
    version = dataset_version,
    run_id = run_id,
    key_cols = key_map[[table_name]] %||% character(),
    metadata = base_meta
  )
  dict_path <- dictionary_path_for_table(path)
  dir.create(dirname(dict_path), recursive = TRUE, showWarnings = FALSE)
  fwrite(dict, dict_path)
  
  register_artifact(
    dataset_id = dataset_id,
    table_name = table_name,
    version = dataset_version,
    run_id = run_id,
    artifact_type = "dictionary_ext",
    artifact_path = dict_path,
    n_rows = nrow(dict),
    n_cols = ncol(dict),
    notes = paste("Diccionario extendido generado para", path)
  )
  
  data.table(table_path = path, dictionary_path = dict_path, status = "OK")
}), fill = TRUE)

out_summary <- "data/derived/qc/inei_population/dictionary_generation_summary.csv"
dir.create(dirname(out_summary), recursive = TRUE, showWarnings = FALSE)
fwrite(summary, out_summary)

summary_dict <- make_table_dictionary(
  data = summary,
  table_name = table_name_from_path(out_summary),
  dataset_id = dataset_id,
  version = dataset_version,
  run_id = run_id
)
summary_dict_path <- dictionary_path_for_table(out_summary)
fwrite(summary_dict, summary_dict_path)

register_artifact(
  dataset_id = dataset_id,
  table_name = "dictionary_generation_summary",
  version = dataset_version,
  run_id = run_id,
  artifact_type = "qc",
  artifact_path = out_summary,
  n_rows = nrow(summary),
  n_cols = ncol(summary),
  notes = "Resumen de generación de diccionarios tabulares."
)

register_artifact(
  dataset_id = dataset_id,
  table_name = "dictionary_generation_summary",
  version = dataset_version,
  run_id = run_id,
  artifact_type = "dictionary_ext",
  artifact_path = summary_dict_path,
  n_rows = nrow(summary_dict),
  n_cols = ncol(summary_dict),
  notes = "Diccionario extendido del resumen de generación de diccionarios."
)

if (any(summary[table_path %in% required_tables]$status != "OK")) {
  register_run_finish(run_id, status = "failed", message = "Missing tables during dictionary generation.")
  stop(
    "Dictionary generation found missing required tables:\n",
    paste(summary[table_path %in% required_tables & status != "OK"]$table_path, collapse = "\n")
  )
}

register_run_finish(run_id, status = "success")
print(summary)
