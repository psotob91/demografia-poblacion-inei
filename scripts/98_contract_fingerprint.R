# scripts/98_contract_fingerprint.R
# ------------------------------------------------------------------------------
# Contract fingerprint utility for parquet outputs.
# Writes a compact CSV with structural checks and deterministic content hash.
# ------------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(digest)
})

args <- commandArgs(trailingOnly = TRUE)

input_path <- if (length(args) >= 1L) args[[1L]] else "data/final/population_inei/population_result.parquet"
output_path <- if (length(args) >= 2L) args[[2L]] else NA_character_

required_cols <- c("year_id", "age", "sex_id", "location_id", "population")
pk_cols <- c("year_id", "age", "sex_id", "location_id")

if (!file.exists(input_path)) {
  stop("Input parquet does not exist: ", input_path)
}

dt <- as.data.table(arrow::read_parquet(input_path))

missing_required_cols <- setdiff(required_cols, names(dt))
available_required_cols <- intersect(required_cols, names(dt))
available_pk_cols <- intersect(pk_cols, names(dt))

classes <- vapply(dt, function(x) paste(class(x), collapse = "|"), character(1))
schema <- paste(paste(names(classes), classes, sep = ":"), collapse = ";")

pk_unique_n <- if (length(available_pk_cols) == length(pk_cols)) {
  data.table::uniqueN(dt, by = pk_cols)
} else {
  NA_integer_
}

pk_duplicate_n <- if (length(available_pk_cols) == length(pk_cols)) {
  nrow(dt[, .N, by = pk_cols][N > 1L])
} else {
  NA_integer_
}

required_missing_n <- if (length(available_required_cols) > 0L) {
  sum(vapply(available_required_cols, function(col) sum(is.na(dt[[col]])), integer(1)))
} else {
  NA_integer_
}

range_text <- function(col) {
  if (!col %in% names(dt)) return(NA_character_)
  x <- dt[[col]]
  if (all(is.na(x))) return("all_missing")
  paste0(min(x, na.rm = TRUE), "|", max(x, na.rm = TRUE))
}

domain_text <- function(col) {
  if (!col %in% names(dt)) return(NA_character_)
  paste(sort(unique(dt[[col]])), collapse = "|")
}

content_hash <- NA_character_
if (length(available_required_cols) == length(required_cols) && length(available_pk_cols) == length(pk_cols)) {
  sorted <- copy(dt)
  data.table::setorderv(sorted, pk_cols)
  sorted <- sorted[, ..required_cols]
  content_hash <- digest::digest(sorted, algo = "sha256")
}

fingerprint <- data.table(
  input_path = normalizePath(input_path, winslash = "/", mustWork = TRUE),
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  n_rows = nrow(dt),
  n_cols = ncol(dt),
  columns = paste(names(dt), collapse = "|"),
  schema = schema,
  missing_required_cols = paste(missing_required_cols, collapse = "|"),
  pk_unique_n = pk_unique_n,
  pk_duplicate_n = pk_duplicate_n,
  required_missing_n = required_missing_n,
  year_range = range_text("year_id"),
  age_range = range_text("age"),
  sex_domain = domain_text("sex_id"),
  location_domain = domain_text("location_id"),
  population_range = range_text("population"),
  file_md5 = digest::digest(file = input_path, algo = "md5"),
  content_sha256 = content_hash
)

print(fingerprint)

if (!is.na(output_path) && nzchar(output_path)) {
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(fingerprint, output_path)
  message("Fingerprint written: ", output_path)
}
