# scripts/02_normaliza_long_omop.R
# ------------------------------------------------------------------------------
# Normaliza staging long (raw_long.parquet) a OMOP-like
# - Alineado al output real de scripts/01_ingesta_raw_inei.R:
#   source_sheet, source_file, population_raw, year_id, age_label, etc.
# ------------------------------------------------------------------------------

library(data.table)
library(stringr)
library(arrow)
library(here)

source(here("R/io_utils.R"))
P <- paths_inei()
dir.create(P$STAGE_DIR, recursive = TRUE, showWarnings = FALSE)

raw_long <- as.data.table(
  arrow::read_parquet(file.path(P$STAGE_DIR, "raw_long.parquet"))
)

# ----------------------------
# 0) Alinear nombres esperados
# ----------------------------
# sheet
if (!"sheet" %in% names(raw_long) && "source_sheet" %in% names(raw_long)) {
  setnames(raw_long, "source_sheet", "sheet")
}
# population_raw
if (!"population_raw" %in% names(raw_long) && "population" %in% names(raw_long)) {
  setnames(raw_long, "population", "population_raw")
}

# Validación mínima
req_cols <- c("age_label", "sheet", "year_id", "population_raw",
              "location_id", "location_name", "ubigeo_dept_str", "level",
              "sex_id", "sex_label", "sex_label_es", "source_file")
missing_cols <- setdiff(req_cols, names(raw_long))
if (length(missing_cols) > 0) {
  stop(
    "Faltan columnas requeridas en raw_long.parquet:\n- ",
    paste(missing_cols, collapse = "\n- "),
    "\n\nColumnas disponibles:\n- ",
    paste(names(raw_long), collapse = "\n- ")
  )
}

# ----------------------------
# 1) Estandarizar tipos
# ----------------------------
raw_long[, age_label := trimws(as.character(age_label))]
raw_long[, sheet := trimws(as.character(sheet))]
raw_long[, source_file := as.character(source_file)]
raw_long[, year_id := as.integer(year_id)]
raw_long[, population_raw := suppressWarnings(as.numeric(population_raw))]

# ----------------------------
# 2) Sexo desde sheet (si necesitas “trazabilidad” por nombre de hoja)
#    Nota: ya viene sex_id/sex_label del script 01, pero esto crea gender_source_value.
# ----------------------------
raw_long[, sheet_last_token := toupper(stringr::word(sheet, -1))]

raw_long[, gender_source_value := fifelse(
  sheet_last_token %chin% c("T","M","F"),
  sheet_last_token,
  fifelse(
    str_detect(tolower(sheet), "\\btotal\\b|\\bambos\\b"),
    "T",
    fifelse(
      str_detect(tolower(sheet), "\\bmascul\\b|\\bhombre\\b|\\bvaron\\b"),
      "M",
      fifelse(
        str_detect(tolower(sheet), "\\bfemen\\b|\\bmujer\\b"),
        "F",
        NA_character_
      )
    )
  )
)]

raw_long[, sheet_last_token := NULL]

# ----------------------------
# 3) Parse edad
# ----------------------------
raw_long[, age_label_up := toupper(trimws(age_label))]

raw_long[, age_type := fifelse(
  age_label_up %chin% c("TOTAL", "TOTAL GENERAL", "TOTAL NACIONAL"),
  "total",
  fifelse(str_detect(age_label_up, "^[0-9]+$"), "age_single", "age_group")
)]

raw_long[, age := fifelse(age_type == "age_single", as.integer(age_label_up), NA_integer_)]

# Para grupos: extrae primer número (start) y último número (end) si hay rango
raw_long[, age_group := fifelse(age_type == "age_group", age_label, NA_character_)]

raw_long[, age_group_start := fifelse(
  age_type == "age_group",
  suppressWarnings(as.integer(str_extract(age_label_up, "^[0-9]+"))),
  NA_integer_
)]

raw_long[, age_group_end := fifelse(
  age_type == "age_group",
  suppressWarnings(as.integer(str_extract(age_label_up, "(?<!^)[0-9]+$"))),
  NA_integer_
)]

# Si es tipo "85 y más", "85 A MAS", etc.
raw_long[
  age_type == "age_group" &
    (is.na(age_group_end) | age_group_end < age_group_start) &
    str_detect(age_label_up, "MAS|MÁS|\\+"),
  age_group_end := 110L
]

raw_long[, age_label_up := NULL]

# ----------------------------
# QC: hojas sin inferencia
# ----------------------------
bad_gender <- raw_long[is.na(gender_source_value),
                       .N, by = .(location_id, location_name, sheet)][order(-N)]

if (nrow(bad_gender) > 0) {
  message("⚠ Hay hojas sin sexo inferido (revisar nombres de sheet). Top:")
  print(head(bad_gender, 10))
}

# ----------------------------
# 4) Guardar OMOP-like staging
# ----------------------------
omop_like <- raw_long[]
arrow::write_parquet(omop_like, file.path(P$STAGE_DIR, "omop_like_long.parquet"))
message("✅ Staging OMOP-like guardado: ", file.path(P$STAGE_DIR, "omop_like_long.parquet"))