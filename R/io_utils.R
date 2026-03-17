# R/io_utils.R
library(here)

paths_inei <- function() {
  list(
    RAW_DIR     = here("data", "raw", "inei_population"),
    STAGE_DIR   = here("data", "derived", "staging", "inei_population"),
    QC_DIR      = here("data", "derived", "qc", "inei_population"),
    FINAL_DIR   = here("data", "final", "population_inei"),
    CATALOG_DIR = here("data", "_catalog"),
    CONFIG_DIR  = here("config")
  )
}
