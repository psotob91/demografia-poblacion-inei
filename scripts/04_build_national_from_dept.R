library(data.table)
library(arrow)
library(here)

source(here("R/io_utils.R"))
source(here("R/dictionary_utils.R"))
source(here("R/catalog_utils.R"))

P <- paths_inei()
dir.create(P$STAGE_DIR, recursive = TRUE, showWarnings = FALSE)

IN_FP <- file.path(P$FINAL_DIR, "population_result.parquet")
OUT_FP <- file.path(P$STAGE_DIR, "population_national_from_dept.parquet")
DICT_FP <- file.path(P$STAGE_DIR, "population_national_from_dept_diccionario_ext.csv")

dt <- as.data.table(arrow::read_parquet(IN_FP))

nat <- dt[location_id %in% 1:25,
          .(population = sum(population, na.rm = TRUE)),
          by = .(year_id, age, sex_id)]
nat[, location_id := 9000L]
setkey(nat, year_id, age, sex_id, location_id)

arrow::write_parquet(nat, OUT_FP)

dict <- data.table(
  column_name = c("year_id", "age", "sex_id", "location_id", "population"),
  label = c(
    "Ano calendario",
    "Edad 0-109 simple; 110 = 110+",
    "Sexo (OMOP concept_id)",
    "Ubicacion (9000 = Peru aditivo desde departamentos)",
    "Poblacion (conteo de personas)"
  ),
  data_type = c("integer", "integer", "integer", "integer", "integer"),
  units = c(NA, "years", NA, NA, "persons"),
  allow_na = FALSE,
  description = c(
    "Ano calendario",
    "Edad contractual: 0-109 simple y 110 como grupo abierto 110+",
    "OMOP concept_id (8507=M, 8532=F)",
    "Nacional alternativo construido como suma de departamentos",
    "Conteo absoluto de poblacion"
  )
)

dict_ext <- enrich_dict_with_stats(dict, nat)
fwrite(dict_ext, DICT_FP)

dataset_id <- "inei_population_1995_2030"
version <- "v1.0.0"
run_id <- format(Sys.time(), "%Y%m%d_%H%M%S")

register_artifact(
  dataset_id = dataset_id,
  table_name = "population_national_from_dept",
  version = version,
  run_id = run_id,
  artifact_type = "derived_dataset",
  artifact_path = OUT_FP,
  n_rows = nrow(nat),
  n_cols = ncol(nat),
  notes = "Nacional alternativo aditivo construido como suma de departamentos (01-25) con age=110 como 110+."
)

register_artifact(
  dataset_id = dataset_id,
  table_name = "population_national_from_dept",
  version = version,
  run_id = run_id,
  artifact_type = "dictionary_ext",
  artifact_path = DICT_FP,
  n_rows = nrow(dict_ext),
  n_cols = ncol(dict_ext),
  notes = "Diccionario extendido del nacional alternativo aditivo."
)

message("Nacional alternativo + diccionario registrados correctamente")
