#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(here)
})

qmd <- here("reports", "method-report.qmd")
if (!file.exists(qmd)) {
  stop("No se encontro el QMD metodologico: ", qmd)
}

status <- system2("quarto", c("render", shQuote(qmd)))
if (!identical(as.integer(status), 0L)) {
  stop("Fallo el render de reports/method-report.qmd")
}

html <- here("reports", "method-report.html")
if (!file.exists(html)) {
  stop("El render termino sin generar reports/method-report.html")
}

message("Reporte metodologico renderizado: ", html)
