library(data.table)
library(arrow)
library(here)

source(here("R/io_utils.R"))
source(here("R/dictionary_utils.R"))
source(here("R/catalog_utils.R"))

P <- paths_inei()
dir.create(P$FINAL_DIR, recursive = TRUE, showWarnings = FALSE)

CORE_FP <- file.path(P$FINAL_DIR, "population_result.parquet")
ALT_FP <- file.path(P$STAGE_DIR, "population_national_from_dept.parquet")

OUT_FP <- file.path(P$FINAL_DIR, "population_result_hierarchical.parquet")
DICT_FP <- file.path(P$FINAL_DIR, "population_result_hierarchical_diccionario_ext.csv")

core <- as.data.table(arrow::read_parquet(CORE_FP))
alt <- as.data.table(arrow::read_parquet(ALT_FP))

core_no_nat <- core[location_id != 0]
final <- rbindlist(list(core_no_nat, alt), use.names = TRUE)
setkey(final, year_id, age, sex_id, location_id)

arrow::write_parquet(final, OUT_FP)

dict <- data.table(
  column_name = c("year_id", "age", "sex_id", "location_id", "population"),
  label = c(
    "Ano calendario",
    "Edad 0-109 simple; 110 = 110+",
    "Sexo (OMOP concept_id)",
    "Ubicacion (1-25 deptos, 9000 nacional aditivo)",
    "Poblacion (conteo de personas)"
  ),
  data_type = c("integer", "integer", "integer", "integer", "integer"),
  units = c(NA, "years", NA, NA, "persons"),
  allow_na = FALSE,
  description = c(
    "Ano calendario",
    "Edad contractual: 0-109 simple y 110 como grupo abierto 110+",
    "OMOP concept_id",
    "Vista jerarquica consistente (nacional = suma deptos)",
    "Conteo absoluto de poblacion"
  )
)

dict_ext <- enrich_dict_with_stats(dict, final)
fwrite(dict_ext, DICT_FP)

dataset_id <- "inei_population_1995_2030"
version <- "v1.0.0"
run_id <- format(Sys.time(), "%Y%m%d_%H%M%S")

register_artifact(
  dataset_id = dataset_id,
  table_name = "population_result_hierarchical",
  version = version,
  run_id = run_id,
  artifact_type = "final_dataset",
  artifact_path = OUT_FP,
  n_rows = nrow(final),
  n_cols = ncol(final),
  notes = "Vista final jerarquicamente consistente: deptos + nacional aditivo; age=110 representa 110+."
)

register_artifact(
  dataset_id = dataset_id,
  table_name = "population_result_hierarchical",
  version = version,
  run_id = run_id,
  artifact_type = "dictionary_ext",
  artifact_path = DICT_FP,
  n_rows = nrow(dict_ext),
  n_cols = ncol(dict_ext),
  notes = "Diccionario extendido de la vista jerarquica consistente."
)

message("Vista jerarquica consistente creada y registrada")
