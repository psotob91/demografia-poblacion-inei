# R/io_utils.R
library(here)
library(yaml)

paths_inei <- function() {
  list(
    RAW_DIR     = here("data", "raw", "inei_population"),
    BENCHMARK_DIR = here("data", "raw", "external_benchmarks"),
    STAGE_DIR   = here("data", "derived", "staging", "inei_population"),
    QC_DIR      = here("data", "derived", "qc", "inei_population"),
    FINAL_DIR   = here("data", "final", "population_inei"),
    CATALOG_DIR = here("data", "_catalog"),
    CONFIG_DIR  = here("config"),
    REPORTS_DIR = here("reports"),
    OUTPUTS_DIR = here("outputs"),
    MAESTROS_DIR = here("maestros")
  )
}

ensure_project_dirs_inei <- function() {
  p <- paths_inei()
  dir.create(p$RAW_DIR, recursive = TRUE, showWarnings = FALSE)
  dir.create(p$BENCHMARK_DIR, recursive = TRUE, showWarnings = FALSE)
  dir.create(p$STAGE_DIR, recursive = TRUE, showWarnings = FALSE)
  dir.create(p$QC_DIR, recursive = TRUE, showWarnings = FALSE)
  dir.create(p$FINAL_DIR, recursive = TRUE, showWarnings = FALSE)
  dir.create(p$CATALOG_DIR, recursive = TRUE, showWarnings = FALSE)
  dir.create(p$REPORTS_DIR, recursive = TRUE, showWarnings = FALSE)
  dir.create(p$OUTPUTS_DIR, recursive = TRUE, showWarnings = FALSE)
  dir.create(p$MAESTROS_DIR, recursive = TRUE, showWarnings = FALSE)
  invisible(p)
}

read_runtime_paths_inei <- function(config_dir = here("config")) {
  path <- file.path(config_dir, "runtime_paths.yml")
  if (!file.exists(path)) return(list())
  yaml::read_yaml(path)
}

is_absolute_path_inei <- function(path) {
  if (is.null(path) || length(path) == 0L || is.na(path) || !nzchar(path)) return(FALSE)
  grepl("^([A-Za-z]:[\\\\/]|/)", path)
}

normalize_runtime_path_inei <- function(path, base_root = here()) {
  if (is.null(path) || length(path) == 0L || is.na(path) || !nzchar(path)) return(NA_character_)
  candidate <- if (is_absolute_path_inei(path)) path else file.path(base_root, path)
  normalizePath(candidate, winslash = "/", mustWork = FALSE)
}

resolve_optional_input_path_inei <- function(config_key,
                                             default_repo_relative = NULL,
                                             env_var = NULL,
                                             config_dir = here("config"),
                                             use_default_repo_relative = TRUE) {
  runtime_cfg <- read_runtime_paths_inei(config_dir)
  cfg_override <- if (!is.null(runtime_cfg[[config_key]]) && nzchar(as.character(runtime_cfg[[config_key]]))) {
    as.character(runtime_cfg[[config_key]])
  } else NA_character_
  env_path <- if (!is.null(env_var) && nzchar(env_var)) Sys.getenv(env_var, unset = "") else ""

  candidates <- c(
    if (nzchar(env_path)) normalize_runtime_path_inei(env_path) else NA_character_,
    if (!is.na(cfg_override)) normalize_runtime_path_inei(cfg_override) else NA_character_,
    if (isTRUE(use_default_repo_relative) && !is.null(default_repo_relative) && nzchar(default_repo_relative)) {
      normalize_runtime_path_inei(default_repo_relative)
    } else {
      NA_character_
    }
  )
  candidates <- unique(stats::na.omit(candidates))
  hit <- candidates[file.exists(candidates)][1]
  if (length(hit) == 0L || is.na(hit)) return(NA_character_)
  normalizePath(hit, winslash = "/", mustWork = FALSE)
}
