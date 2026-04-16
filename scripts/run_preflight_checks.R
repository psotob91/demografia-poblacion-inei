#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(here)
})

source(here("R", "io_utils.R"))

out_dir <- here("data", "derived", "qc", "run_pipeline")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

checks <- list()
add_check <- function(check_id, severity, status, path = NA_character_, detail = NA_character_) {
  checks[[length(checks) + 1L]] <<- data.table(
    check_id = check_id,
    severity = severity,
    status = status,
    resolved_path = path,
    detail = detail
  )
}

is_readable <- function(path) file.exists(path) && file.access(path, 4) == 0
is_writable_dir <- function(path) dir.exists(path) && file.access(path, 2) == 0

P <- ensure_project_dirs_inei()
benchmark_fp <- file.path(P$BENCHMARK_DIR, "peru_life_table_all_years_closed_80_109.csv")
method_qmd <- here("reports", "method-report.qmd")

add_check("project_root", "blocking", if (dir.exists(here())) "ok" else "fail", here(), "Raiz detectada por here().")
add_check("raw_inei_dir", "blocking", if (dir.exists(P$RAW_DIR)) "ok" else "fail", P$RAW_DIR, "Directorio raw INEI.")
add_check("local_tail_benchmark", "blocking", if (is_readable(benchmark_fp)) "ok" else "fail", benchmark_fp, "Benchmark local desacoplado cerrado 80:109.")
add_check("method_qmd", "blocking", if (is_readable(method_qmd)) "ok" else "fail", method_qmd, "Anexo metodologico principal.")

for (cfg in c(
  file.path(P$CONFIG_DIR, "spec_population_inei.yml"),
  file.path(P$CONFIG_DIR, "spec_population_inei_hierarchical.yml"),
  file.path(P$CONFIG_DIR, "pipeline_steps.csv"),
  file.path(P$CONFIG_DIR, "pipeline_profiles.yml"),
  file.path(P$CONFIG_DIR, "maestro_location_dept.csv"),
  file.path(P$CONFIG_DIR, "maestro_location_hierarchical.csv"),
  file.path(P$CONFIG_DIR, "maestro_sex_omop.csv")
) ) {
  add_check(paste0("config_", basename(cfg)), "blocking", if (is_readable(cfg)) "ok" else "fail", cfg, "Archivo de configuracion requerido.")
}

for (wd in c(P$STAGE_DIR, P$QC_DIR, P$FINAL_DIR, P$REPORTS_DIR, P$OUTPUTS_DIR, here("data", "_catalog"))) {
  dir.create(wd, recursive = TRUE, showWarnings = FALSE)
  add_check(paste0("writable_", basename(wd)), "blocking", if (is_writable_dir(wd)) "ok" else "fail", wd, "Directorio escribible.")
}

runtime_cfg <- read_runtime_paths_inei(P$CONFIG_DIR)
snapshot_cfg <- runtime_cfg[["crossrepo_death_110plus_snapshot"]]
if (!is.null(snapshot_cfg) && nzchar(as.character(snapshot_cfg))) {
  resolved <- normalize_runtime_path_inei(as.character(snapshot_cfg))
  add_check(
    "crossrepo_snapshot_optional",
    "warning",
    if (is_readable(resolved)) "ok" else "warn",
    resolved,
    "Snapshot cross-repo opcional para coherencia 110+."
  )
} else {
  add_check(
    "crossrepo_snapshot_optional",
    "warning",
    "ok",
    NA_character_,
    "No hay snapshot cross-repo configurado. El build base seguira en modo autocontenido."
  )
}

checks_dt <- rbindlist(checks, fill = TRUE)
summary_dt <- checks_dt[, .N, by = .(severity, status)][order(severity, status)]
fwrite(checks_dt, file.path(out_dir, "preflight_checks.csv"))
fwrite(summary_dt, file.path(out_dir, "preflight_summary.csv"))

blocking_bad <- checks_dt[severity == "blocking" & status != "ok"]
if (nrow(blocking_bad) > 0L) {
  message("Preflight NO APROBADO. Revisar data/derived/qc/run_pipeline/preflight_checks.csv")
  quit(save = "no", status = 1)
}

message("Preflight APROBADO.")
