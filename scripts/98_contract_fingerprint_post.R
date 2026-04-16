#!/usr/bin/env Rscript

args <- c(
  "scripts/98_contract_fingerprint.R",
  "data/final/population_inei/population_result.parquet",
  "data/derived/qc/inei_population/contract_fingerprint_post.csv"
)
status <- system2(file.path(R.home("bin"), "Rscript"), args = shQuote(args))
quit(save = "no", status = as.integer(status))
