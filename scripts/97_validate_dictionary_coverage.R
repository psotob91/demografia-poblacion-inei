# scripts/97_validate_dictionary_coverage.R
# ------------------------------------------------------------------------------
# Validate that expected pipeline tables have dictionaries with exact column cover.
# ------------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
})

source("R/dictionary_utils.R")

read_table_names <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "parquet") return(names(arrow::read_parquet(path)))
  if (ext == "csv") return(names(data.table::fread(path, nrows = 0)))
  stop("Unsupported table extension: ", path)
}

dictionary_path_for_table <- function(table_path) {
  ext <- tools::file_ext(table_path)
  stem <- sub(paste0("\\.", ext, "$"), "", table_path)
  paste0(stem, "_diccionario_ext.csv")
}

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
  "data/derived/qc/inei_population/qc_tail_external_alignment_national.csv",
  "data/derived/qc/inei_population/qc_tail_share_110plus.csv",
  "data/derived/qc/inei_population/qc_tail_visual_priority.csv",
  "data/derived/qc/inei_population/qc_tail_benchmark_source_by_stratum.csv",
  "data/derived/qc/inei_population/qc_tail_open_interval_exclusion.csv",
  "data/derived/qc/inei_population/qc_110plus_collapse_exact.csv",
  "data/derived/qc/inei_population/qc_national_vs_dept_sum.csv",
  "data/derived/qc/inei_population/hierarchical/qc_hierarchical_summary.csv",
  "data/derived/qc/inei_population/hierarchical/qc_hierarchical_missing_required.csv",
  "data/derived/qc/inei_population/hierarchical/qc_hierarchical_duplicates.csv",
  "data/derived/qc/inei_population/hierarchical/qc_hierarchical_negative_population.csv",
  "data/derived/qc/inei_population/hierarchical/qc_hierarchical_national_additive_check.csv",
  "data/derived/qc/inei_population/dictionary_generation_summary.csv",
  "data/_catalog/catalogo_artefactos.csv",
  "data/_catalog/provenance_runs.csv"
)

optional_tables <- c(
  "data/derived/qc/inei_population/contract_fingerprint_baseline.csv",
  "data/derived/qc/inei_population/contract_fingerprint_post.csv"
)

expected_tables <- c(required_tables, optional_tables)

portal_tables <- c(
  "reports/qc_demografia_poblacion/downloads/qc_artifact_inventory.csv",
  "reports/qc_demografia_poblacion/downloads/coherence_curve_manifest.csv",
  "reports/qc_demografia_poblacion/downloads/coherence_trend_manifest.csv",
  "reports/qc_demografia_poblacion/downloads/coherence_heatmap_manifest.csv",
  "reports/qc_demografia_poblacion/downloads/portal_build_summary.csv",
  "reports/qc_demografia_poblacion/downloads/qc_observed_vs_final.csv",
  "reports/qc_demografia_poblacion/downloads/qc_extrapolated_80_125.csv",
  "reports/qc_demografia_poblacion/downloads/qc_tail_mass_80plus_exact.csv",
  "reports/qc_demografia_poblacion/downloads/qc_tail_cap_125_national.csv",
  "reports/qc_demografia_poblacion/downloads/qc_crossrepo_110plus_coherence.csv",
  "reports/qc_demografia_poblacion/downloads/qc_crossrepo_mass_adjustment.csv",
  "reports/qc_demografia_poblacion/downloads/qc_tail_external_alignment_national.csv",
  "reports/qc_demografia_poblacion/downloads/qc_tail_share_110plus.csv",
  "reports/qc_demografia_poblacion/downloads/qc_tail_visual_priority.csv",
  "reports/qc_demografia_poblacion/downloads/qc_tail_benchmark_source_by_stratum.csv",
  "reports/qc_demografia_poblacion/downloads/qc_tail_open_interval_exclusion.csv",
  "reports/qc_demografia_poblacion/downloads/qc_110plus_collapse_exact.csv",
  "reports/qc_demografia_poblacion/downloads/qc_national_modes.csv",
  "reports/qc_demografia_poblacion/downloads/qc_glossary.csv",
  "reports/qc_demografia_poblacion/downloads/qc_observed_vs_final_manifest.csv",
  "reports/qc_demografia_poblacion/downloads/qc_extrapolated_80_125_manifest.csv",
  "reports/qc_demografia_poblacion/downloads/qc_110plus_collapse_manifest.csv",
  "reports/qc_demografia_poblacion/downloads/qc_national_modes_manifest.csv"
)

if (file.exists("reports/qc_demografia_poblacion/downloads/portal_build_summary.csv")) {
  expected_tables <- c(expected_tables, portal_tables)
}

coverage <- rbindlist(lapply(expected_tables, function(path) {
  dict_path <- dictionary_path_for_table(path)
  table_exists <- file.exists(path)
  dict_exists <- file.exists(dict_path)
  
  if (!table_exists || !dict_exists) {
    status <- if (!table_exists && path %in% optional_tables) "SKIPPED_OPTIONAL_MISSING_TABLE" else "FAIL"
    return(data.table(
      table_path = path,
      dictionary_path = dict_path,
      table_exists = table_exists,
      dictionary_exists = dict_exists,
      table_n_cols = NA_integer_,
      dictionary_n_rows = NA_integer_,
      missing_in_dictionary = NA_character_,
      extra_in_dictionary = NA_character_,
      status = status
    ))
  }
  
  table_cols <- read_table_names(path)
  dict <- fread(dict_path)
  dict_cols <- dict[!startsWith(column_name, "META:"), column_name]
  missing_in_dictionary <- setdiff(table_cols, dict_cols)
  extra_in_dictionary <- setdiff(dict_cols, table_cols)
  ok <- length(missing_in_dictionary) == 0L && length(extra_in_dictionary) == 0L
  
  data.table(
    table_path = path,
    dictionary_path = dict_path,
    table_exists = TRUE,
    dictionary_exists = TRUE,
    table_n_cols = length(table_cols),
    dictionary_n_rows = length(dict_cols),
    missing_in_dictionary = paste(missing_in_dictionary, collapse = "|"),
    extra_in_dictionary = paste(extra_in_dictionary, collapse = "|"),
    status = if (ok) "OK" else "FAIL"
  )
}), fill = TRUE)

out_path <- "data/derived/qc/inei_population/dictionary_coverage_summary.csv"
dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)

if (any(coverage[table_path %in% required_tables]$status != "OK")) {
  fwrite(coverage, out_path)
  print(coverage)
  stop("Dictionary coverage validation failed. See: ", out_path)
}

fwrite(coverage, out_path)

self_dict <- make_table_dictionary(
  data = coverage,
  table_name = tools::file_path_sans_ext(basename(out_path)),
  metadata = data.table(
    column_name = c(
      "table_path", "dictionary_path", "table_exists", "dictionary_exists",
      "table_n_cols", "dictionary_n_rows", "missing_in_dictionary",
      "extra_in_dictionary", "status"
    ),
    label = c(
      "Ruta de tabla", "Ruta de diccionario", "Tabla existe", "Diccionario existe",
      "Columnas de tabla", "Filas de diccionario", "Columnas faltantes en diccionario",
      "Columnas extra en diccionario", "Estado"
    ),
    description = c(
      "Artefacto tabular validado.",
      "Diccionario esperado para el artefacto tabular.",
      "Indica si la tabla existe.",
      "Indica si el diccionario existe.",
      "Numero de columnas de la tabla.",
      "Numero de filas de columnas cubiertas por el diccionario.",
      "Columnas presentes en la tabla y ausentes del diccionario.",
      "Columnas presentes en el diccionario y ausentes de la tabla.",
      "Resultado de validacion de cobertura."
    )
  )
)
self_dict_path <- dictionary_path_for_table(out_path)
fwrite(self_dict, self_dict_path)

fwrite(coverage, out_path)
print(coverage)

if (any(coverage[table_path %in% required_tables]$status != "OK")) {
  stop("Dictionary coverage validation failed. See: ", out_path)
}
