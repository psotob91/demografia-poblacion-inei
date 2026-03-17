# scripts/99_qc_global.R
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
DICT_FP  <- file.path(P$FINAL_DIR, "population_result_diccionario_ext.csv")

QC_SUMMARY_FP   <- file.path(P$QC_DIR, "qc_summary.csv")
QC_DUP_FP       <- file.path(P$QC_DIR, "qc_duplicates.csv")
QC_MISS_FP      <- file.path(P$QC_DIR, "qc_missing_required.csv")
QC_NEG_FP       <- file.path(P$QC_DIR, "qc_negative_population.csv")
QC_TAIL_FP      <- file.path(P$QC_DIR, "qc_tail_monotone_flags.csv")
QC_NAT_VS_DEPFP <- file.path(P$QC_DIR, "qc_national_vs_dept_sum.csv")

register_run_start(run_id, dataset_id, dataset_version)

tryCatch({
  
  if (!file.exists(FINAL_FP)) stop("No existe FINAL: ", FINAL_FP, " (corre scripts 01-03 primero).")
  
  dt <- as.data.table(arrow::read_parquet(FINAL_FP))
  
  # 1) Validación dura contra spec (falla si rompe no-negociables)
  validate_population_result(dt, SPEC)
  
  # 2) QC outputs detallados
  req_cols <- names(SPEC$required_columns)
  pk <- SPEC$primary_key
  
  qc_missing <- qc_missing_required(dt, req_cols)
  fwrite(qc_missing, QC_MISS_FP)
  
  qc_dups <- qc_pk_duplicates(dt, pk)
  fwrite(qc_dups, QC_DUP_FP)
  
  qc_neg <- qc_nonnegative(dt, "population")
  fwrite(qc_neg, QC_NEG_FP)
  
  tail_start <- SPEC$policy$extrapolation$fit_age_min %||% 70L
  qc_tail <- qc_tail_monotone_flag(dt, start_age = tail_start)
  fwrite(qc_tail, QC_TAIL_FP)
  
  # 2.1) NUEVO: QC national (00) vs suma deptos (01–25)
  # tolerancia relativa: 0.1% por defecto (pct_tol=0.001)
  qc_nat_vs_dep <- qc_national_vs_dept_sum(dt, pct_tol = 0.001)
  fwrite(qc_nat_vs_dep, QC_NAT_VS_DEPFP)
  
  # Resumen de QC national vs dept
  nat_n_missing <- sum(qc_nat_vs_dep$flag_missing, na.rm = TRUE)
  nat_n_diff    <- sum(qc_nat_vs_dep$flag_diff, na.rm = TRUE)
  
  # Summary global
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
    qc_nat_vs_dep_n_missing = nat_n_missing,
    qc_nat_vs_dep_n_diff = nat_n_diff
  )
  fwrite(qc_summary, QC_SUMMARY_FP)
  
  # 3) Diccionario_ext (spec -> dict) + labels de location + stats observados
  dict <- dict_from_spec(SPEC, dataset_version = dataset_version, run_id = run_id, config_dir = P$CONFIG_DIR)
  dict_ext <- enrich_dict_with_stats(dict, dt)
  fwrite(dict_ext, DICT_FP)
  
  # 4) Registrar artefactos en _catalog
  register_artifact(dataset_id, table_name, dataset_version, run_id,
                    artifact_type = "final_dataset",
                    artifact_path = FINAL_FP,
                    n_rows = nrow(dt), n_cols = ncol(dt),
                    notes = "Dataset final canónico: UBIGEO depto (00=Perú), edad simple 0-110, sex_id M/F, población conteo.")
  
  register_artifact(dataset_id, table_name, dataset_version, run_id,
                    artifact_type = "dictionary_ext",
                    artifact_path = DICT_FP,
                    n_rows = nrow(dict_ext), n_cols = ncol(dict_ext),
                    notes = "Diccionario generado desde spec + maestro_location_dept + stats observados del final.")
  
  register_artifact(dataset_id, table_name, dataset_version, run_id,
                    artifact_type = "qc",
                    artifact_path = QC_SUMMARY_FP,
                    notes = "QC summary del run.")
  
  register_artifact(dataset_id, table_name, dataset_version, run_id,
                    artifact_type = "qc",
                    artifact_path = QC_NAT_VS_DEPFP,
                    notes = "QC detectivo: national (00) vs suma deptos (01–25) por año/sexo/edad.")
  
  register_artifact(dataset_id, table_name, dataset_version, run_id,
                    artifact_type = "spec",
                    artifact_path = SPEC_PATH,
                    notes = "Spec YAML usado para validar y generar diccionario.")
  
  # también registra el maestro de locations si existe
  loc_fp <- file.path(P$CONFIG_DIR, "maestro_location_dept.csv")
  if (file.exists(loc_fp)) {
    register_artifact(dataset_id, table_name, dataset_version, run_id,
                      artifact_type = "master",
                      artifact_path = loc_fp,
                      notes = "Maestro UBIGEO depto usado para labels en diccionario_ext.")
  }
  
  register_run_finish(run_id, status = "success")
  
  # 5) Consola amigable
  cat("\n=== QC SUMMARY (", dataset_id, ") ===\n", sep = "")
  print(qc_summary)
  
  # Top discrepancias national vs dept (para inspección rápida)
  top_diff <- qc_nat_vs_dep[flag_missing == TRUE | flag_diff == TRUE][
    order(-abs(diff_pct))
  ]
  if (nrow(top_diff) > 0) {
    cat("\n=== QC National vs Dept Sum: TOP discrepancias ===\n")
    print(head(top_diff, 15))
    cat("\nArchivo completo: ", QC_NAT_VS_DEPFP, "\n", sep = "")
  } else {
    cat("\nQC National vs Dept Sum: sin discrepancias fuera de tolerancia.\n")
  }
  
  cat("\nArtefactos:\n")
  cat(" - FINAL: ", FINAL_FP, "\n", sep="")
  cat(" - DICT : ", DICT_FP, "\n", sep="")
  cat(" - QC   : ", QC_SUMMARY_FP, "\n", sep="")
  cat(" - QC N : ", QC_NAT_VS_DEPFP, "\n", sep="")
  cat(" - CATA : ", here("data/_catalog/catalogo_artefactos.csv"), "\n", sep="")
  cat(" - RUNS : ", here("data/_catalog/provenance_runs.csv"), "\n", sep="")
  
}, error = function(e) {
  register_run_finish(run_id, status = "failed", message = as.character(e$message))
  stop(e)
})
