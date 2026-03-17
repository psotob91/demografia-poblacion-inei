# scripts/99_qc_global_hierarchical.R
# QC global para la vista jerárquica: population_result_hierarchical
# - NO toca QC del dataset canónico (INEI 00)
# - Foco: consistencia nacional aditivo 9000 y contrato hierarchical

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(yaml)
  library(here)
})

# ----------------------------
# Helpers
# ----------------------------
`%||%` <- function(a, b) if (!is.null(a)) a else b

stop_if_missing <- function(paths) {
  miss <- paths[!file.exists(paths)]
  if (length(miss) > 0) stop("Faltan archivos:\n", paste("-", miss, collapse = "\n"))
}

# ----------------------------
# Load project utils
# ----------------------------
source(here("R/io_utils.R"))
source(here("R/qc_utils.R"))
source(here("R/spec_utils.R"))
source(here("R/catalog_utils.R"))

# ----------------------------
# Config
# ----------------------------
P <- paths_inei()

SPEC_PATH <- here("config/spec_population_inei_hierarchical.yml")
FINAL_PARQUET <- file.path(P$FINAL_DIR, "population_result_hierarchical.parquet")

QC_DIR_H <- file.path(P$QC_DIR, "hierarchical")
dir.create(QC_DIR_H, recursive = TRUE, showWarnings = FALSE)

# outputs QC (jerárquico)
OUT_SUMMARY     <- file.path(QC_DIR_H, "qc_hierarchical_summary.csv")
OUT_MISSING_REQ <- file.path(QC_DIR_H, "qc_hierarchical_missing_required.csv")
OUT_DUPS        <- file.path(QC_DIR_H, "qc_hierarchical_duplicates.csv")
OUT_NEGATIVE    <- file.path(QC_DIR_H, "qc_hierarchical_negative_population.csv")
OUT_NAT_ADDIT   <- file.path(QC_DIR_H, "qc_hierarchical_national_additive_check.csv")

# ----------------------------
# Read spec
# ----------------------------
stop_if_missing(c(SPEC_PATH, FINAL_PARQUET))

spec <- yaml::read_yaml(SPEC_PATH)

pk <- spec$primary_key %||% c("year_id","age","sex_id","location_id")
req_cols <- names(spec$required_columns) %||% c("year_id","age","sex_id","location_id","population")

base_locations <- spec$policy$hierarchical_view$base_locations %||% as.integer(1:25)
national_additive_id <- as.integer(spec$policy$hierarchical_view$national_additive_location_id %||% 9000L)

loc_constraint <- spec$constraints$location_id %||% list()

allowed_locations <- loc_constraint$allowed_values %||%
  loc_constraint$allowed %||%
  loc_constraint$values %||%
  c(base_locations, national_additive_id)

str(spec$constraints$location_id)

allowed_locations <- as.integer(unlist(allowed_locations))

# ----------------------------
# Read data
# ----------------------------
dt <- as.data.table(arrow::read_parquet(FINAL_PARQUET))

# ----------------------------
# QC detectivo básico
# ----------------------------
# Missing required columns
missing_cols <- setdiff(req_cols, names(dt))
qc_missing_required <- data.table(
  required_column = req_cols,
  exists = req_cols %in% names(dt)
)

# Duplicados PK
if (all(pk %in% names(dt))) {
  dt[, pk_hash := do.call(paste, c(.SD, sep = "||")), .SDcols = pk]
  dup_dt <- dt[duplicated(pk_hash) | duplicated(pk_hash, fromLast = TRUE)]
  dup_dt[, pk_hash := NULL]
} else {
  dup_dt <- data.table(note = "No se pudo evaluar duplicados: faltan columnas PK.")
}

# Negativos
neg_dt <- if ("population" %in% names(dt)) dt[population < 0] else data.table(note="No existe population")

# ----------------------------
# QC DURO jerárquico: reglas no negociables
# ----------------------------
# 1) No permitir 0
if ("location_id" %in% names(dt) && any(dt$location_id == 0L, na.rm = TRUE)) {
  stop("QC HARD FAIL: Vista jerárquica contiene location_id=0 (nacional original). Debe excluirse.")
}

# 2) Debe existir 9000
if (!("location_id" %in% names(dt)) || !any(dt$location_id == national_additive_id, na.rm = TRUE)) {
  stop("QC HARD FAIL: Vista jerárquica no contiene location_id=9000 (nacional aditivo).")
}

# 3) Debe cubrir base locations
missing_base <- setdiff(base_locations, unique(dt$location_id))
if (length(missing_base) > 0) {
  stop("QC HARD FAIL: faltan deptos base en vista jerárquica: ", paste(missing_base, collapse = ", "))
}

# 4) Debe estar dentro de allowed_locations
bad_loc <- setdiff(unique(dt$location_id), allowed_locations)
if (length(bad_loc) > 0) {
  stop("QC HARD FAIL: location_id fuera de allowed_values: ", paste(bad_loc, collapse = ", "))
}

# 5) Nacional aditivo exacto: 9000 == suma deptos por celda
# (guardamos tabla de chequeo + stop si hay diferencias)
dt_dept <- dt[location_id %in% base_locations,
              .(dept_sum = sum(population)), by = .(year_id, age, sex_id)]

dt_nat <- dt[location_id == national_additive_id,
             .(nat_pop = population), by = .(year_id, age, sex_id)]

chk <- merge(dt_dept, dt_nat, by = c("year_id","age","sex_id"), all = TRUE)

# Cobertura completa requerida
if (anyNA(chk$dept_sum) || anyNA(chk$nat_pop)) {
  fwrite(chk, OUT_NAT_ADDIT)
  stop("QC HARD FAIL: cobertura incompleta en chequeo de 9000 (hay NA en dept_sum o nat_pop). Ver: ", OUT_NAT_ADDIT)
}

chk[, diff := nat_pop - dept_sum]
chk[, diff_pct := fifelse(dept_sum == 0, NA_real_, diff / dept_sum)]
chk[, flag_diff := diff != 0]

# escribimos siempre el chequeo (es audit trail)
fwrite(chk, OUT_NAT_ADDIT)

if (any(chk$flag_diff)) {
  top <- chk[flag_diff == TRUE][order(-abs(diff))][1:min(.N, 20)]
  stop(
    "QC HARD FAIL: nacional aditivo (9000) NO es suma exacta de deptos.\n",
    "Top 20 discrepancias (|diff|):\n",
    paste(capture.output(print(top)), collapse = "\n"),
    "\nArchivo completo: ", OUT_NAT_ADDIT
  )
}

# ----------------------------
# QC summary (jerárquico)
# ----------------------------
qc_summary <- data.table(
  dataset = "population_result_hierarchical",
  n_rows = nrow(dt),
  n_cols = ncol(dt),
  n_missing_required_cols = sum(!qc_missing_required$exists),
  n_pk_dups = if (all(pk %in% names(dt))) nrow(dup_dt) else NA_integer_,
  n_negative_pop = if ("population" %in% names(dt)) nrow(neg_dt) else NA_integer_,
  has_location_9000 = any(dt$location_id == national_additive_id),
  has_location_0 = any(dt$location_id == 0L),
  run_ts = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
)

# ----------------------------
# Write outputs
# ----------------------------
fwrite(qc_summary, OUT_SUMMARY)
fwrite(qc_missing_required, OUT_MISSING_REQ)
fwrite(dup_dt, OUT_DUPS)
fwrite(neg_dt, OUT_NEGATIVE)

message("==> QC jerárquico OK. Outputs en: ", QC_DIR_H)
message(" - ", basename(OUT_SUMMARY))
message(" - ", basename(OUT_NAT_ADDIT))

# ----------------------------
# Register artefacts in _catalog (si tus utils lo soportan)
# ----------------------------
# Nota: aquí uso nombres genéricos; ajusta a tus funciones reales si difieren.
# La idea: registrar spec usada + parquet leído + qc outputs generados.

try({
  run_id <- register_run_start(
    pipeline_id = "demografia-poblacion-inei",
    stage = "qc_global_hierarchical",
    notes = "QC duro + detectivo para vista jerárquica (9000 aditivo; no permite 0)."
  )
  
  artefacts <- c(
    SPEC_PATH,
    FINAL_PARQUET,
    OUT_SUMMARY,
    OUT_MISSING_REQ,
    OUT_DUPS,
    OUT_NEGATIVE,
    OUT_NAT_ADDIT
  )
  
  for (fp in artefacts) {
    register_artefact(
      run_id = run_id,
      file_path = fp,
      dataset_id = spec$dataset_id %||% "inei_population_1995_2030_hierarchical"
    )
  }
  
  register_run_finish(run_id = run_id, status = "success")
}, silent = TRUE)
