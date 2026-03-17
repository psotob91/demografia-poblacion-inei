# scripts/01_ingesta_raw_inei.R
# ------------------------------------------------------------------------------
# Ingesta RAW INEI (población por depto) + staging long (OMOP-like)
# - Usa maestro_location_dept.csv como source of truth (locations)
# - Usa maestro_sex_omop.csv para mapear sex_id OMOP (M/F) + agrega Total (T=0 convención local)
# - Descarga a data/raw/inei_population/ si falta
# - Parsea excels y genera staging long:
#     data/derived/staging/inei_population/raw_long.parquet
# - Logs:
#     download_log.csv + parse_log.csv
# ------------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(stringr)
  library(readxl)
  library(janitor)
  library(tidyr)
  library(arrow)
  library(tibble)
  library(rlang)
})

# ----------------------------
# Paths
# ----------------------------
project_root <- "."
dir_raw      <- file.path(project_root, "data", "raw", "inei_population")
dir_staging  <- file.path(project_root, "data", "derived", "staging", "inei_population")
dir.create(dir_raw, recursive = TRUE, showWarnings = FALSE)
dir.create(dir_staging, recursive = TRUE, showWarnings = FALSE)

path_master_location <- file.path(project_root, "config", "maestro_location_dept.csv")
path_master_sex      <- file.path(project_root, "config", "maestro_sex_omop.csv")

base_url <- "https://www.inei.gob.pe/media/MenuRecursivo/publicaciones_digitales/Est/Lib1722/cuadros/cap0202/"

if (!file.exists(path_master_location)) stop("No existe: ", path_master_location)
if (!file.exists(path_master_sex))      stop("No existe: ", path_master_sex)

# ----------------------------
# Cargar maestros
# ----------------------------
loc_raw <- read.csv(path_master_location, stringsAsFactors = FALSE) %>% as_tibble()
sex_raw <- read.csv(path_master_sex, stringsAsFactors = FALSE) %>% as_tibble()

loc <- loc_raw %>%
  mutate(
    location_id     = as.integer(location_id),
    location_name   = as.character(location_name),
    ubigeo_dept_str = str_pad(as.character(ubigeo_dept_str), 2, pad = "0"),
    level           = if_else(ubigeo_dept_str == "00", "national", "department"),
    file_name       = if ("file_name" %in% names(loc_raw)) {
      if_else(
        is.na(file_name) | file_name == "",
        paste0("cap", ubigeo_dept_str, ".xlsx"),
        as.character(file_name)
      )
    } else {
      paste0("cap", ubigeo_dept_str, ".xlsx")
    }
  ) %>%
  arrange(location_id)

stopifnot(all(c("location_id","location_name","ubigeo_dept_str","level","file_name") %in% names(loc)))

sex <- sex_raw %>%
  mutate(
    sex_id       = as.integer(sex_id),
    sex_label    = as.character(sex_label),
    sex_label_es = as.character(sex_label_es)
  )

# Agregar Total como convención local
sex_total <- tibble(sex_id = 0L, sex_label = "Total", sex_label_es = "Total")

sex_map <- bind_rows(sex %>% select(sex_id, sex_label, sex_label_es), sex_total) %>%
  distinct(sex_id, .keep_all = TRUE)

# Map M/F según maestro OMOP
sex_code_map <- tibble(
  sex_code = c("M","F","T"),
  sex_id   = c(
    sex %>% filter(str_to_upper(sex_label) == "MALE")   %>% pull(sex_id) %>% .[1],
    sex %>% filter(str_to_upper(sex_label) == "FEMALE") %>% pull(sex_id) %>% .[1],
    0L
  )
)

if (any(is.na(sex_code_map$sex_id))) {
  stop("No pude mapear M/F desde maestro_sex_omop.csv (sex_label debe contener MALE/FEMALE).")
}

# ----------------------------
# URLs y paths locales
# ----------------------------
loc_tbl <- loc %>%
  mutate(
    url        = paste0(base_url, file_name),
    local_path = file.path(dir_raw, file_name)
  )

# ----------------------------
# Descarga (solo si falta local)
# ----------------------------
download_one <- function(url, destfile) {
  start_time <- Sys.time()
  out <- list(
    url = url, destfile = destfile,
    started_at = format(start_time, tz = "UTC", usetz = TRUE),
    status = NA_character_, error_message = NA_character_
  )
  
  if (file.exists(destfile) && file.size(destfile) > 0) {
    out$ended_at <- format(Sys.time(), tz = "UTC", usetz = TRUE)
    out$status <- "SKIPPED_EXISTS"
    return(out)
  }
  
  ok <- tryCatch({
    suppressWarnings(utils::download.file(url, destfile = destfile, mode = "wb", quiet = TRUE))
    TRUE
  }, error = function(e) {
    out$error_message <<- conditionMessage(e)
    FALSE
  })
  
  out$ended_at <- format(Sys.time(), tz = "UTC", usetz = TRUE)
  out$status <- if (ok && file.exists(destfile) && file.size(destfile) > 0) "OK" else "FAILED"
  out
}

download_log <- purrr::pmap_dfr(
  list(loc_tbl$url, loc_tbl$local_path),
  ~ tibble::as_tibble(download_one(..1, ..2))
)

write.csv(
  download_log,
  file.path(dir_staging, "download_log.csv"),
  row.names = FALSE, fileEncoding = "UTF-8"
)

# ----------------------------
# Helpers parseo
# ----------------------------
normalize_cell <- function(x) {
  x %>%
    as.character() %>%
    str_replace_all("\\s+", " ") %>%
    str_trim() %>%
    str_to_upper()
}

find_header_row <- function(df_raw) {
  # df_raw ya tiene nombres seguros por .name_repair="unique"
  m <- df_raw %>% mutate(across(everything(), normalize_cell))
  idx <- which(apply(m, 1, function(r) any(r == "EDAD" | str_starts(r, "EDAD"))))
  if (length(idx) == 0) return(NA_integer_)
  idx[1]
}

extract_sex_code_from_sheet <- function(sheet_name) {
  if (length(sheet_name) == 0) return(NA_character_)
  sheet_name <- sheet_name[1]
  s <- toupper(trimws(gsub("\\s+", " ", sheet_name)))
  
  if (grepl("\\bM\\b|\\bMASC\\b|\\bHOMBRE\\b", s)) return("M")
  if (grepl("\\bF\\b|\\bFEM\\b|\\bMUJER\\b", s))  return("F")
  if (grepl("\\bT\\b|\\bTOTAL\\b|\\bAMBOS\\b", s)) return("T")
  NA_character_
}

read_sheet_tidy <- function(path, sheet) {
  # ✅ name repair unique para evitar NA/"" en nombres
  df_raw <- readxl::read_excel(
    path, sheet = sheet,
    col_names = FALSE,
    .name_repair = "unique"
  )
  
  header_row <- find_header_row(df_raw)
  if (is.na(header_row)) {
    stop("No se encontró encabezado con 'Edad'. Archivo: ", basename(path), " | sheet: ", sheet)
  }
  
  # ✅ name repair unique para que encabezados vacíos no rompan dplyr
  df <- readxl::read_excel(
    path, sheet = sheet,
    skip = header_row - 1,
    .name_repair = "unique"
  ) %>%
    janitor::clean_names()
  
  # columna edad (edad / edad_simple / edad_anios, etc)
  age_col <- names(df)[str_detect(names(df), "^edad")]
  if (length(age_col) < 1) {
    stop("No se pudo identificar columna 'edad'. Archivo: ", basename(path), " | sheet: ", sheet)
  }
  # si hubiera más de una, usa la primera (más robusto)
  age_col <- age_col[1]
  
  # columnas año: 1995 o x1995 (tras clean_names, pueden quedar como x1995)
  year_cols <- names(df)[str_detect(names(df), "^x?\\d{4}$")]
  if (length(year_cols) == 0) {
    stop("No se encontraron columnas año (YYYY o xYYYY). Archivo: ", basename(path), " | sheet: ", sheet)
  }
  
  # ✅ recortar estrictamente a edad + años (ignora columnas basura del excel)
  df2 <- df %>%
    select(all_of(c(age_col, year_cols)))
  
  df2 %>%
    transmute(
      age_label = as.character(.data[[age_col]]),
      !!!df2[year_cols]
    ) %>%
    filter(!is.na(age_label), str_trim(age_label) != "") %>%
    pivot_longer(
      cols = all_of(year_cols),
      names_to = "year_id_raw",
      values_to = "population_raw"
    ) %>%
    mutate(
      year_id = suppressWarnings(as.integer(str_remove(year_id_raw, "^x"))),
      population_raw = suppressWarnings(as.numeric(population_raw))
    ) %>%
    filter(!is.na(year_id)) %>%
    select(age_label, year_id, population_raw)
}

# ----------------------------
# Ingesta a long + parse logs
# ----------------------------
message("📥 Procesando archivos y construyendo staging long...")

files_existing <- loc_tbl %>%
  select(location_id, location_name, ubigeo_dept_str, level, file_name, local_path) %>%
  mutate(exists_local = file.exists(local_path) & file.size(local_path) > 0) %>%
  filter(exists_local)

if (nrow(files_existing) == 0) {
  stop(
    "No hay archivos locales para parsear en: ", dir_raw, "\n",
    "Revisa download_log.csv o coloca manualmente cap00.xlsx/cap15.xlsx ahí."
  )
}

parse_jobs <- files_existing %>%
  mutate(source_sheet = map(local_path, readxl::excel_sheets)) %>%
  tidyr::unnest(source_sheet) %>%
  mutate(
    source_sheet = as.character(source_sheet),
    sex_code     = vapply(source_sheet, extract_sex_code_from_sheet, character(1))
  )

safe_read_sheet <- purrr::safely(read_sheet_tidy, otherwise = NULL)

parsed_jobs <- parse_jobs %>%
  mutate(parsed = pmap(list(local_path, source_sheet), ~ safe_read_sheet(..1, ..2)))

has_error <- function(x) !is.null(x$error)
get_error_msg <- function(x) if (is.null(x$error)) NA_character_ else conditionMessage(x$error)

parse_log <- parsed_jobs %>%
  mutate(
    parse_status = ifelse(vapply(parsed, has_error, logical(1)), "FAILED", "OK"),
    parse_error  = vapply(parsed, get_error_msg, character(1))
  ) %>%
  select(location_id, file_name, source_sheet, sex_code, parse_status, parse_error)

write.csv(
  parse_log,
  file.path(dir_staging, "parse_log.csv"),
  row.names = FALSE, fileEncoding = "UTF-8"
)

ok_jobs <- parsed_jobs %>%
  mutate(data = map(parsed, "result")) %>%
  select(-parsed) %>%
  mutate(data = map(data, ~ if (is.null(.x)) NULL else as_tibble(.x))) %>%
  filter(!vapply(data, is.null, logical(1))) %>%
  left_join(sex_code_map, by = "sex_code") %>%
  left_join(sex_map %>% select(sex_id, sex_label, sex_label_es), by = "sex_id")

if (nrow(ok_jobs) == 0) {
  top_err <- parse_log %>%
    filter(parse_status == "FAILED") %>%
    count(parse_error, sort = TRUE) %>%
    slice_head(n = 10)
  
  msg <- paste0(
    "No se pudo parsear ninguna hoja (ok_jobs = 0).\n",
    "Revisa: ", file.path(dir_staging, "parse_log.csv"), "\n\n",
    "Top errores (más frecuentes):\n",
    paste0("- ", top_err$parse_error, " (n=", top_err$n, ")", collapse = "\n")
  )
  stop(msg)
}

# ----------------------------
# ✅ Construcción LONG SIN unnest() (robusto)
# ----------------------------
all_long <- purrr::pmap_dfr(
  list(
    ok_jobs$location_id,
    ok_jobs$location_name,
    ok_jobs$ubigeo_dept_str,
    ok_jobs$level,
    ok_jobs$file_name,
    ok_jobs$source_sheet,
    ok_jobs$sex_id,
    ok_jobs$sex_label,
    ok_jobs$sex_label_es,
    ok_jobs$data
  ),
  function(location_id, location_name, ubigeo_dept_str, level,
           file_name, source_sheet,
           sex_id, sex_label, sex_label_es,
           data) {
    
    if (is.null(data) || nrow(data) == 0) return(NULL)
    
    req <- c("age_label", "year_id", "population_raw")
    if (!all(req %in% names(data))) {
      stop(
        "El parseo devolvió un data.frame sin columnas esperadas.\n",
        "Archivo: ", file_name, " | sheet: ", source_sheet, "\n",
        "Columnas encontradas:\n- ", paste(names(data), collapse = "\n- ")
      )
    }
    
    data %>%
      transmute(
        location_id       = as.integer(location_id),
        location_name     = as.character(location_name),
        ubigeo_dept_str   = as.character(ubigeo_dept_str),
        level             = as.character(level),
        sex_id            = as.integer(sex_id),
        sex_label         = as.character(sex_label),
        sex_label_es      = as.character(sex_label_es),
        source_file       = as.character(file_name),
        source_sheet      = as.character(source_sheet),
        age_label         = as.character(age_label),
        year_id           = as.integer(year_id),
        population_raw    = as.numeric(population_raw)
      )
  }
)

if (nrow(all_long) == 0) {
  stop(
    "Se encontraron archivos/hojas OK, pero no se extrajo ninguna fila final.\n",
    "Revisa parse_log.csv: ", file.path(dir_staging, "parse_log.csv")
  )
}

# ----------------------------
# Salida staging
# ----------------------------
out_parquet <- file.path(dir_staging, "raw_long.parquet")
arrow::write_parquet(all_long, out_parquet)

message("✅ Staging guardado en: ", out_parquet)
message("✅ Logs: ", dir_staging, " (download_log.csv, parse_log.csv)")