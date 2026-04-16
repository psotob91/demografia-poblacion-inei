# ------------------------------------------------------------------------------
# Static QC and demographic coherence portal.
# Additional audit evidence only; it does not modify the contractual parquet.
# ------------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(ggplot2)
  library(scales)
})

source("R/catalog_utils.R")
source("R/dictionary_utils.R")

dataset_id <- "inei_population_1995_2030"
version <- "v1.0.0"
run_id <- paste0("portal-qc-demografia-", format(Sys.time(), "%Y%m%d-%H%M%S"))
force_rebuild_figures <- identical(toupper(Sys.getenv("FORCE_QC_PORTAL_FIGURES", "FALSE")), "TRUE")

portal_root <- file.path("reports", "qc_demografia_poblacion")
assets_dir <- file.path(portal_root, "assets")
downloads_dir <- file.path(portal_root, "downloads")
pipeline_dir <- file.path(portal_root, "modules", "pipeline-qc")
coherence_dir <- file.path(portal_root, "modules", "coherencia-demografica")
pipeline_pages_dir <- file.path(pipeline_dir, "tomos")
curve_dir <- file.path(coherence_dir, "figures", "curvas_edad")
heatmap_dir <- file.path(coherence_dir, "figures", "heatmaps_edad_anio")
trend_dir <- file.path(coherence_dir, "figures", "tendencias")
qc_fig_dir <- file.path(pipeline_dir, "figures")
qc_observed_fig_dir <- file.path(qc_fig_dir, "observado_final")
qc_extrap_fig_dir <- file.path(qc_fig_dir, "cola_interna_80_125")
qc_national_fig_dir <- file.path(qc_fig_dir, "nacionalidad")
qc_collapse_fig_dir <- file.path(qc_fig_dir, "colapso_110plus")
dir_list <- c(portal_root, assets_dir, downloads_dir, pipeline_dir, pipeline_pages_dir,
              coherence_dir, curve_dir, heatmap_dir, trend_dir, qc_fig_dir,
              qc_observed_fig_dir, qc_extrap_fig_dir, qc_national_fig_dir, qc_collapse_fig_dir)
invisible(lapply(dir_list, dir.create, recursive = TRUE, showWarnings = FALSE))
legacy_qc_extrap_dir <- file.path(qc_fig_dir, "extrapolacion_80_110")
if (dir.exists(legacy_qc_extrap_dir)) unlink(legacy_qc_extrap_dir, recursive = TRUE, force = TRUE)

norm_path <- function(x) gsub("\\\\", "/", x)
esc <- function(x) {
  x <- as.character(ifelse(is.na(x), "", x))
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  gsub("\"", "&quot;", x, fixed = TRUE)
}
write_text <- function(path, x) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(x, path, useBytes = TRUE)
}
read_csv <- function(path) if (file.exists(path)) fread(path, encoding = "UTF-8", showProgress = FALSE) else data.table()
href_from_module <- function(path, module_dir) norm_path(file.path("..", "..", "..", path))
href_from_root <- function(path) norm_path(file.path(path))
href_from_pipeline <- function(path) norm_path(file.path("..", "..", "..", path))
href_from_coherence <- function(path) norm_path(file.path("..", "..", "..", path))
benchmark_source_label <- function(x) {
  out <- fifelse(
    x == "official_life_table_all_years_regional",
    "Tabla de vida oficial regional all_years",
    fifelse(
      x == "implicit_national_from_official_regions",
      "Nacional implicito agregado desde regiones oficiales",
      fifelse(
        x == "wpp_peru_fallback_2026_2030",
        "Fallback Peru WPP 2026-2030",
        x
      )
    )
  )
  out[is.na(out)] <- "Fuente no especificada"
  out
}
benchmark_source_label_short <- function(x) {
  out <- fifelse(
    x == "official_life_table_all_years_regional",
    "oficial regional",
    fifelse(
      x == "implicit_national_from_official_regions",
      "nacional implicito",
      fifelse(
        x == "wpp_peru_fallback_2026_2030",
        "fallback WPP",
        x
      )
    )
  )
  out[is.na(out)] <- "fuente no especificada"
  out
}

html_table <- function(dt, max_rows = 60L) {
  x <- as.data.table(copy(dt))
  if (!nrow(x) || !ncol(x)) return("<p class=\"muted\">Sin filas para mostrar.</p>")
  note <- ""
  if (nrow(x) > max_rows) {
    note <- sprintf("<p class=\"muted\">Vista previa: primeras %s de %s filas.</p>", max_rows, nrow(x))
    x <- x[seq_len(max_rows)]
  }
  head_html <- paste(sprintf("<th>%s</th>", esc(names(x))), collapse = "")
  row_html <- vapply(seq_len(nrow(x)), function(i) {
    vals <- vapply(x[i], function(z) paste(z, collapse = "|"), character(1))
    paste0("<tr>", paste(sprintf("<td>%s</td>", esc(vals)), collapse = ""), "</tr>")
  }, character(1))
  paste0(note, "<div class=\"table-wrap\"><table><thead><tr>", head_html,
         "</tr></thead><tbody>", paste(row_html, collapse = ""), "</tbody></table></div>")
}

term <- function(x) sprintf("<button class=\"term\" type=\"button\" data-term=\"%s\">%s</button>", esc(x), esc(x))

table_explain <- function(text, dict = NULL, max_rows = 40L) {
  dict_html <- if (!is.null(dict) && nrow(dict)) {
    keep <- intersect(c("column_name", "label", "description", "data_type", "example_values"), names(dict))
    paste0("<details class=\"dict-box\"><summary>Diccionario de columnas</summary>",
           html_table(dict[, ..keep], max_rows), "</details>")
  } else ""
  paste0("<div class=\"reading-note\"><strong>Como leer esta tabla.</strong> ", text, "</div>", dict_html)
}

dashboard_html <- function(group, controls, panels_html) {
  ctrl <- paste(vapply(names(controls), function(key) {
    vals <- controls[[key]]
    opts <- paste(sprintf("<option value=\"%s\">%s</option>", esc(vals$value), esc(vals$label)), collapse = "")
    sprintf("<label>%s<select data-qc-filter=\"%s\" data-qc-key=\"%s\">%s</select></label>",
            esc(vals$title[1]), esc(group), esc(key), opts)
  }, character(1)), collapse = "")
  paste0("<div class=\"figure-controls\">", ctrl, "</div>", panels_html)
}

card <- function(title, body, eyebrow = NULL) {
  eye <- if (is.null(eyebrow)) "" else sprintf("<div class=\"eyebrow\">%s</div>", esc(eyebrow))
  paste0("<section class=\"card\">", eye, "<h2>", esc(title), "</h2>", body, "</section>")
}

write_page <- function(path, title, intro, body, rel_root) {
  actions <- paste0(
    "<div class=\"quick-actions\">",
    sprintf("<a class=\"btn\" href=\"%s/method-report.html\">Abrir anexo metodologico</a>", rel_root),
    "</div>"
  )
  write_text(path, c(
    "<!doctype html><html lang=\"es\"><head><meta charset=\"utf-8\">",
    "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
    sprintf("<title>%s</title>", esc(title)),
    sprintf("<link rel=\"stylesheet\" href=\"%s/assets/portal.css\">", rel_root),
    sprintf("<script defer src=\"%s/assets/portal.js\"></script>", rel_root),
    "</head><body><div class=\"portal-shell\"><section class=\"hero\">",
    sprintf("<div class=\"eyebrow\">Portal tecnico reproducible</div><h1>%s</h1><p>%s</p>", esc(title), esc(intro)),
    sprintf("<div class=\"hero-meta\"><span>Run: %s</span><span>Generado: %s</span></div>", esc(run_id), format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    actions,
    "</section><main class=\"content-stack\">",
    body,
    "<p class=\"footer-note\">Generado automaticamente desde scripts/95_build_qc_demografia_reports.R.</p>",
    "</main></div></body></html>"
  ))
}

write_assets <- function() {
  css <- c(
    ":root{--bg:#f7f8fb;--surface:#fff;--ink:#16212a;--muted:#5a6672;--line:#d8dee6;--brand:#0f5b66;--accent:#2d7d4f;--warn:#9a6700;--bad:#b42318}",
    "body{margin:0;background:var(--bg);color:var(--ink);font-family:Segoe UI,Aptos,Arial,sans-serif;line-height:1.55}a{color:var(--brand);text-decoration:none}a:hover{text-decoration:underline}",
    ".portal-shell{max-width:1480px;margin:0 auto;padding:28px}.hero{background:#0f5b66;color:#fff;border-radius:8px;padding:28px;margin-bottom:20px}.hero h1{margin:0 0 8px;font-size:2rem}.hero p{margin:0;color:#eef7f6;max-width:1000px}.hero-meta{display:flex;flex-wrap:wrap;gap:10px;margin-top:16px}.hero-meta span{border:1px solid rgba(255,255,255,.35);border-radius:8px;padding:7px 10px;background:rgba(255,255,255,.12)}.quick-actions{display:flex;flex-wrap:wrap;gap:8px;margin-top:16px}",
    ".content-stack{display:grid;gap:18px}.card{background:var(--surface);border:1px solid var(--line);border-radius:8px;padding:20px;box-shadow:0 10px 24px rgba(20,30,40,.08)}.card h2,.card h3{margin-top:0}.eyebrow{text-transform:uppercase;letter-spacing:.06em;font-size:.78rem;color:var(--brand);font-weight:700;margin-bottom:6px}.muted{color:var(--muted)}.footer-note{text-align:center;color:var(--muted);padding:18px}",
    ".module-grid,.kpi-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:14px}.module-card,.kpi-card{border:1px solid var(--line);border-radius:8px;background:#fff;padding:16px}.pill-row{display:flex;flex-wrap:wrap;gap:8px}.pill{border:1px solid var(--line);border-radius:8px;background:#eef4f7;padding:6px 9px}.btn{display:inline-flex;border-radius:8px;background:var(--brand);color:#fff;padding:9px 13px;font-weight:700;margin:4px 6px 4px 0}.btn:hover{text-decoration:none;background:#0a4750}.btn-ghost{background:#ffffff;color:var(--brand)}.btn-ghost:hover{background:#eef6f7}",
    ".table-wrap{overflow:auto;border:1px solid var(--line);border-radius:8px;background:#fff;max-width:100%}.table-wrap table{width:max-content;min-width:100%;border-collapse:collapse;font-size:.92rem;table-layout:auto}.table-wrap td,.table-wrap th{min-width:120px;white-space:normal;word-break:break-word}.table-wrap th:first-child,.table-wrap td:first-child{position:sticky;left:0;background:#fff;z-index:1}.table-wrap th:first-child{background:#eaf2f3}.table-wrap .num{text-align:right;font-variant-numeric:tabular-nums}table{width:100%;border-collapse:collapse;font-size:.92rem}th,td{padding:8px 10px;border-bottom:1px solid #e9edf2;text-align:left;vertical-align:top}th{background:#eaf2f3;color:#14343a}",
    ".figure-controls{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:10px;margin:10px 0 16px}.figure-controls label{display:grid;gap:5px;color:var(--muted);font-weight:700}.figure-controls select{border:1px solid var(--line);border-radius:8px;padding:9px 10px;background:#fff;font-size:1rem}.figure-panel{display:none}.figure-panel.is-active{display:block}.image-card{border:1px solid var(--line);border-radius:8px;background:#fff;padding:12px}.image-card img{width:100%;height:auto;border:1px solid var(--line);border-radius:8px;cursor:zoom-in}",
    ".badge{display:inline-block;border-radius:8px;padding:5px 9px;color:#fff;font-weight:800}.ok{background:var(--accent)}.bad{background:var(--bad)}.warn{background:var(--warn)}.reading-note{border-left:4px solid var(--brand);background:#eef6f7;border-radius:8px;padding:12px 14px;margin:10px 0}.dict-box{border:1px solid var(--line);border-radius:8px;background:#fbfdff;padding:10px 12px;margin:12px 0}.dict-box summary{cursor:pointer;font-weight:800;color:var(--brand)}.term{border:1px solid var(--line);border-radius:8px;background:#fff;color:var(--brand);font-weight:800;padding:2px 6px;cursor:help}.term:focus{outline:2px solid var(--brand)}.term-popover{position:fixed;right:18px;bottom:18px;max-width:460px;background:#fff;border:1px solid var(--line);border-radius:8px;padding:14px;box-shadow:0 12px 30px rgba(10,20,30,.18);z-index:9998}.term-popover h3{margin:.1rem 0 .4rem}.term-popover button{float:right;border:0;background:var(--brand);color:#fff;border-radius:8px;padding:5px 8px}.page-nav{display:flex;flex-wrap:wrap;gap:8px;align-items:center}.page-nav a{border:1px solid var(--line);border-radius:8px;background:#fff;padding:8px 10px;font-weight:800}.lightbox{position:fixed;inset:0;background:rgba(5,15,20,.86);display:none;align-items:center;justify-content:center;z-index:9999;padding:22px}.lightbox.is-open{display:flex}.lightbox img{max-width:96vw;max-height:92vh;background:#fff;border-radius:8px}.lightbox button{position:absolute;top:18px;right:22px;border:0;border-radius:8px;background:#fff;padding:9px 12px;font-weight:800;cursor:pointer}",
    "@media(max-width:760px){.portal-shell{padding:14px}.hero h1{font-size:1.55rem}.table-wrap th:first-child,.table-wrap td:first-child{position:static}.quick-actions{flex-direction:column;align-items:flex-start}}"
  )
  js <- c(
    "document.addEventListener('DOMContentLoaded',function(){",
    "var glossary={\"PK\":\"Llave primaria logica: combinacion de year_id, age, sex_id y location_id que debe identificar una sola fila.\",\"content_sha256\":\"Hash deterministico calculado despues de ordenar por la PK. Es la prueba principal de compatibilidad de contenido.\",\"file_md5\":\"Checksum del archivo parquet fisico. Puede cambiar por metadatos del writer.\",\"flag_diff\":\"Indicador booleano de diferencia detectada en una comparacion QC.\",\"diff_abs\":\"Diferencia absoluta entre dos conteos poblacionales comparados.\",\"location_id=9000\":\"Nacional aditivo construido como suma exacta de departamentos 1-25. No reemplaza el nacional oficial contractual 0.\",\"location_id=0\":\"Nacional oficial proveniente de la fuente INEI y preservado en el output contractual.\",\"n_tail_increase_flags\":\"Numero de estratos donde la cola interna 80-125 muestra un aumento detectado en edades altas.\",\"observed\":\"Valor observado normalizado desde la fuente INEI antes del modelamiento interno de cola.\",\"final\":\"Valor publicado en el parquet contractual final.\",\"extrapolated\":\"Valor esperado generado por el modelo interno de cola para edades 80-125.\",\"expected_counts\":\"Conteos esperados internos que pueden incluir fracciones menores que 1 en edades extremas.\",\"mass_preserved_80plus\":\"Propiedad de QC: la suma interna 80-125 coincide exactamente con la masa observada 80 y + del estrato.\",\"cap_125\":\"Restriccion nacional por sexo y ano: a los 125 anos no puede haber mas de 1.0 persona esperada.\",\"largest_remainder_rounding\":\"Redondeo Hamilton: asigna enteros preservando la suma total del estrato.\",\"110+\":\"Grupo abierto contractual representado por age=110, construido como suma exacta de la cola contractual 110-125 despues del redondeo Hamilton.\",\"hierarchical\":\"Vista que excluye 0 e incluye 9000 para que el nacional sea suma exacta de departamentos.\",\"observed_preserved\":\"Estado que indica que el valor observado y el final coinciden despues de redondeo.\",\"missing_observed\":\"Estado que indica que no hay edad simple observada para esa fila final.\",\"contract_only\":\"Estado de seguridad para filas finales sin equivalente observado claro.\",\"additive_national\":\"Nacional 9000 calculado como suma departamental.\",\"benchmark\":\"Schedule efectiva usada para anclar la cola alta: oficial regional all_years solo en edades cerradas 80-109, nacional implicito agregado o fallback WPP.\",\"Kannisto\":\"Extension logit(qx) usada para prolongar la mortalidad en edades avanzadas usando solo edades cerradas, nunca la fila abierta 110+.\",\"mx_benchmark\":\"Tasa central de mortalidad anual usada para derivar la supervivencia de la cola alta.\",\"benchmark_share_110plus\":\"Proporcion esperada de 110+ dentro del grupo 80+ segun la schedule benchmark.\",\"source_effective\":\"Clasificacion operativa de la fuente efectiva del benchmark del estrato.\",\"coherence_floor\":\"Piso minimo contractual aplicado solo cuando un snapshot externo valido reporta muertes observadas en 110+ y la poblacion contractual 110+ habria quedado en 0. El ajuste sube 110+ a 1 persona.\",\"cross-repo QC\":\"Chequeo de coherencia entre repos mediante snapshots agregados y no sensibles. No es el motor principal del modelo demografico.\",\"death_110plus_summary\":\"Snapshot agregado producido por mortalidad-causa-especifica con muertes observadas 110+ por year_id, sex_id y location_id.\",\"mass_adjustment_from_crossrepo_qc\":\"Ajuste entero agregado al contractual 110+ por la regla de coherencia cruzada. En esta politica solo puede ser 0 o 1 por estrato.\"};",
    "function showTerm(t){var old=document.querySelector('.term-popover');if(old)old.remove();var d=document.createElement('div');d.className='term-popover';d.innerHTML='<button type=\"button\">Cerrar</button><h3>'+t+'</h3><p>'+(glossary[t]||'Termino pendiente de definicion local.')+'</p>';document.body.appendChild(d);d.querySelector('button').addEventListener('click',function(){d.remove();});}",
    "document.querySelectorAll('[data-term]').forEach(function(b){b.addEventListener('click',function(){showTerm(b.getAttribute('data-term'));});});",
    "function syncQ(group){var qs=document.querySelectorAll('[data-qc-filter=\"'+group+'\"]');if(!qs.length)return;var vals={};qs.forEach(function(s){vals[s.getAttribute('data-qc-key')]=s.value;});document.querySelectorAll('[data-qc-panel=\"'+group+'\"]').forEach(function(p){var ok=true;Object.keys(vals).forEach(function(k){if(p.getAttribute('data-'+k)!==vals[k])ok=false;});p.classList.toggle('is-active',ok);});}",
    "document.querySelectorAll('[data-qc-filter]').forEach(function(s){var g=s.getAttribute('data-qc-filter');s.addEventListener('change',function(){syncQ(g);});syncQ(g);});",
    "function syncC(){var y=document.querySelector('[data-coh-year]'),l=document.querySelector('[data-coh-location]');if(!y||!l)return;var k=y.value+'|'+l.value;document.querySelectorAll('[data-coh-panel]').forEach(function(p){p.classList.toggle('is-active',p.getAttribute('data-coh-panel')===k);});}",
    "document.querySelectorAll('[data-coh-year],[data-coh-location]').forEach(function(s){s.addEventListener('change',syncC);});syncC();",
    "document.querySelectorAll('[data-figure-switch]').forEach(function(s){var g=s.getAttribute('data-figure-switch');var f=function(){document.querySelectorAll('[data-figure-panel=\"'+g+'\"]').forEach(function(p){p.classList.toggle('is-active',p.getAttribute('data-figure-value')===s.value);});};s.addEventListener('change',f);f();});",
    "var lb=document.createElement('div');lb.className='lightbox';lb.innerHTML='<button type=\"button\">Cerrar</button><img alt=\"Figura ampliada\">';document.body.appendChild(lb);var im=lb.querySelector('img');function c(){lb.classList.remove('is-open');im.removeAttribute('src');}lb.querySelector('button').addEventListener('click',c);lb.addEventListener('click',function(e){if(e.target===lb)c();});document.querySelectorAll('.image-card img').forEach(function(x){x.addEventListener('click',function(){im.src=x.src;lb.classList.add('is-open');});});",
    "});"
  )
  write_text(file.path(assets_dir, "portal.css"), css)
  write_text(file.path(assets_dir, "portal.js"), js)
}

write_dict <- function(path, table_name, key_cols = character(), metadata = NULL) {
  if (!file.exists(path)) return(invisible(FALSE))
  dt <- fread(path, showProgress = FALSE)
  dict <- make_table_dictionary(dt, table_name = table_name, dataset_id = dataset_id,
                                version = version, run_id = run_id, key_cols = key_cols,
                                metadata = metadata)
  fwrite(dict, dictionary_path_for_table(path))
  invisible(TRUE)
}

theme_portal <- function() {
  theme_minimal(base_size = 12) +
    theme(plot.title = element_text(face = "bold", color = "#16212a"),
          plot.subtitle = element_text(color = "#5a6672"),
          panel.grid.minor = element_blank(),
          legend.position = "top")
}

save_plot <- function(p, path, width = 9, height = 5.4) {
  if (!force_rebuild_figures && file.exists(path)) return(invisible(FALSE))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  ggsave(path, p, width = width, height = height, dpi = 120, bg = "white")
}

write_assets()

contract_path <- "data/final/population_inei/population_result.parquet"
hier_path <- "data/final/population_inei/population_result_hierarchical.parquet"
internal_path <- "data/derived/staging/inei_population/population_modeled_internal_0_125.parquet"
benchmark_path <- "data/derived/staging/inei_population/population_tail_external_benchmark_peru_80_125.parquet"
bridge_path <- "data/derived/staging/inei_population/population_tail_contract_bridge_80_109_110plus.parquet"
if (!file.exists(contract_path)) stop("Missing contractual output: ", contract_path)
if (!file.exists(hier_path)) stop("Missing hierarchical output: ", hier_path)
if (!file.exists(internal_path)) stop("Missing internal modeled output: ", internal_path)
if (!file.exists(benchmark_path)) stop("Missing external benchmark output: ", benchmark_path)
if (!file.exists(bridge_path)) stop("Missing contractual tail bridge: ", bridge_path)

contract_dt <- as.data.table(read_parquet(contract_path))
hier_dt <- as.data.table(read_parquet(hier_path))
internal_dt <- as.data.table(read_parquet(internal_path))
benchmark_dt <- as.data.table(read_parquet(benchmark_path))
bridge_dt <- as.data.table(read_parquet(bridge_path))
omop_dt <- as.data.table(read_parquet("data/derived/staging/inei_population/omop_like_long.parquet"))
loc <- fread("config/maestro_location_hierarchical.csv")
loc_contract <- rbind(
  data.table(location_id = 0L, location_name = "Peru oficial (0)", level = "national_official", is_synthetic = FALSE),
  loc[, .(location_id, location_name, level, is_synthetic)]
)
sex <- fread("config/maestro_sex_omop.csv")[, .(sex_id, sex_name = sex_label_es)]
contract_labeled <- merge(contract_dt, loc_contract[, .(location_id, location_name)], by = "location_id", all.x = TRUE)
contract_labeled <- merge(contract_labeled, sex, by = "sex_id", all.x = TRUE)
contract_labeled[is.na(location_name), location_name := as.character(location_id)]
contract_labeled[is.na(sex_name), sex_name := as.character(sex_id)]
contract_labeled[, location_label := fifelse(location_id == 0L, "Peru oficial (0)", paste0(location_name, " (", location_id, ")"))]
hier_dt <- merge(hier_dt, loc[, .(location_id, location_name, level)], by = "location_id", all.x = TRUE)
hier_dt <- merge(hier_dt, sex, by = "sex_id", all.x = TRUE)
hier_dt[is.na(location_name), location_name := as.character(location_id)]
hier_dt[is.na(sex_name), sex_name := as.character(sex_id)]
hier_dt[, location_label := fifelse(location_id == 9000L, "Peru total (9000)", paste0(location_name, " (", location_id, ")"))]
locations <- loc[location_id %in% sort(unique(hier_dt$location_id))][order(location_id)]
locations[, location_label := fifelse(location_id == 9000L, "Peru total (9000)", paste0(location_name, " (", location_id, ")"))]
years <- sort(unique(hier_dt$year_id))

baseline_fp <- read_csv("data/derived/qc/inei_population/contract_fingerprint_baseline.csv")
post_fp <- read_csv("data/derived/qc/inei_population/contract_fingerprint_post.csv")
fp_compare <- data.table()
if (nrow(baseline_fp) && nrow(post_fp)) {
  fp_compare <- rbindlist(lapply(intersect(names(baseline_fp), names(post_fp)), function(nm) {
    data.table(field = nm, baseline = as.character(baseline_fp[[nm]][1]),
               post = as.character(post_fp[[nm]][1]),
               match = identical(as.character(baseline_fp[[nm]][1]), as.character(post_fp[[nm]][1])))
  }))
}
if (nrow(fp_compare)) {
  fp_compare_core <- fp_compare[!field %in% c("generated_at")]
  fp_compare_volatile <- fp_compare[field %in% c("generated_at")]
} else {
  fp_compare_core <- data.table(field = character(), baseline = character(), post = character(), match = logical())
  fp_compare_volatile <- data.table(field = character(), baseline = character(), post = character(), match = logical())
}
fp_compare_phys <- if (nrow(fp_compare)) {
  fp_compare[field %in% c("content_sha256", "file_md5", "generated_at")]
} else {
  data.table(field = character(), baseline = character(), post = character(), match = logical())
}

qc_paths <- c(
  "data/derived/qc/inei_population/contract_fingerprint_baseline.csv",
  "data/derived/qc/inei_population/contract_fingerprint_post.csv",
  "data/derived/qc/inei_population/qc_summary.csv",
  "data/derived/qc/inei_population/qc_duplicates.csv",
  "data/derived/qc/inei_population/qc_missing_required.csv",
  "data/derived/qc/inei_population/qc_negative_population.csv",
  "data/derived/qc/inei_population/qc_tail_monotone_flags.csv",
  "data/derived/qc/inei_population/qc_tail_mass_80plus_exact.csv",
  "data/derived/qc/inei_population/qc_tail_cap_125_national.csv",
  "data/derived/qc/inei_population/qc_crossrepo_110plus_coherence.csv",
  "data/derived/qc/inei_population/qc_crossrepo_mass_adjustment.csv",
  "data/derived/qc/inei_population/qc_tail_external_alignment_national.csv",
  "data/derived/qc/inei_population/qc_tail_share_110plus.csv",
  "data/derived/qc/inei_population/qc_tail_visual_priority.csv",
  "data/derived/qc/inei_population/qc_tail_benchmark_source_by_stratum.csv",
  "data/derived/qc/inei_population/qc_tail_open_interval_exclusion.csv",
  "data/derived/qc/inei_population/qc_110plus_collapse_exact.csv",
  "data/derived/qc/inei_population/qc_national_vs_dept_sum.csv",
  "data/derived/qc/inei_population/hierarchical/qc_hierarchical_summary.csv",
  "data/derived/qc/inei_population/hierarchical/qc_hierarchical_missing_required.csv",
  "data/derived/qc/inei_population/hierarchical/qc_hierarchical_duplicates.csv",
  "data/derived/qc/inei_population/hierarchical/qc_hierarchical_negative_population.csv",
  "data/derived/qc/inei_population/hierarchical/qc_hierarchical_national_additive_check.csv",
  "data/derived/qc/inei_population/dictionary_coverage_summary.csv",
  "data/_catalog/catalogo_artefactos.csv",
  "data/_catalog/provenance_runs.csv"
)
qc_inventory <- rbindlist(lapply(qc_paths, function(path) {
  target <- file.path(downloads_dir, basename(path))
  if (file.exists(path)) {
    file.copy(path, target, overwrite = TRUE)
    dict_src <- dictionary_path_for_table(path)
    if (file.exists(dict_src)) {
      file.copy(dict_src, dictionary_path_for_table(target), overwrite = TRUE)
    }
  }
  dt <- read_csv(path)
  data.table(artifact = path, exists = file.exists(path), rows = if (file.exists(path)) nrow(dt) else NA_integer_,
             columns = if (file.exists(path)) ncol(dt) else NA_integer_,
             dictionary = dictionary_path_for_table(path),
             dictionary_exists = file.exists(dictionary_path_for_table(path)),
             download_href = if (file.exists(path)) paste0("../../downloads/", basename(path)) else NA_character_)
}), fill = TRUE)
qc_inventory_path <- file.path(downloads_dir, "qc_artifact_inventory.csv")
fwrite(qc_inventory, qc_inventory_path)
write_dict(qc_inventory_path, "portal_qc_artifact_inventory")

qc_summary <- read_csv("data/derived/qc/inei_population/qc_summary.csv")
hier_summary <- read_csv("data/derived/qc/inei_population/hierarchical/qc_hierarchical_summary.csv")
dict_cov <- read_csv("data/derived/qc/inei_population/dictionary_coverage_summary.csv")
tail_flags <- read_csv("data/derived/qc/inei_population/qc_tail_monotone_flags.csv")
tail_mass_qc <- read_csv("data/derived/qc/inei_population/qc_tail_mass_80plus_exact.csv")
tail_cap_qc <- read_csv("data/derived/qc/inei_population/qc_tail_cap_125_national.csv")
crossrepo_coh_qc <- read_csv("data/derived/qc/inei_population/qc_crossrepo_110plus_coherence.csv")
crossrepo_mass_qc <- read_csv("data/derived/qc/inei_population/qc_crossrepo_mass_adjustment.csv")
tail_align_qc <- read_csv("data/derived/qc/inei_population/qc_tail_external_alignment_national.csv")
tail_share_qc <- read_csv("data/derived/qc/inei_population/qc_tail_share_110plus.csv")
tail_priority_qc <- read_csv("data/derived/qc/inei_population/qc_tail_visual_priority.csv")
tail_source_qc <- read_csv("data/derived/qc/inei_population/qc_tail_benchmark_source_by_stratum.csv")
tail_source_qc[, source_effective := benchmark_source_label(source_effective)]
tail_open_excl_qc <- read_csv("data/derived/qc/inei_population/qc_tail_open_interval_exclusion.csv")
tail_open_excl_qc[, source_effective := benchmark_source_label(source_effective)]
collapse_qc <- read_csv("data/derived/qc/inei_population/qc_110plus_collapse_exact.csv")
nat_vs_dept <- read_csv("data/derived/qc/inei_population/qc_national_vs_dept_sum.csv")
hier_add <- read_csv("data/derived/qc/inei_population/hierarchical/qc_hierarchical_national_additive_check.csv")

obs <- omop_dt[
  age_type == "age_single" & !is.na(age) & gender_source_value %in% c("M", "F"),
  .(
    population_observed = as.integer(round(population_raw)),
    source_file = source_file[1],
    source_sheet = sheet[1],
    age_label = age_label[1]
  ),
  by = .(year_id, age, sex_id = fifelse(gender_source_value == "M", 8507L, 8532L), location_id)
]
qc_observed_vs_final <- merge(
  contract_labeled[, .(year_id, age, sex_id, sex_name, location_id, location_label, population_final = population)],
  obs,
  by = c("year_id", "age", "sex_id", "location_id"),
  all.x = TRUE
)
qc_observed_vs_final[, delta_final_minus_observed := population_final - population_observed]
qc_observed_vs_final[, pct_delta_final_minus_observed := fifelse(
  !is.na(population_observed) & population_observed != 0L,
  round(100 * delta_final_minus_observed / population_observed, 6),
  NA_real_
)]
qc_observed_vs_final[, qc_state := fifelse(
  age >= 80L, "modeled_or_collapsed_tail",
  fifelse(is.na(population_observed), "missing_observed",
          fifelse(delta_final_minus_observed == 0L, "observed_preserved", "observed_changed"))
)]
qc_observed_vs_final[, value_flag := fifelse(population_final < 0L, "negative_final",
                                            fifelse(population_final == 0L, "zero_final", "none"))]
qc_observed_vs_final_path <- file.path(downloads_dir, "qc_observed_vs_final.csv")
fwrite(qc_observed_vs_final, qc_observed_vs_final_path)
observed_meta <- data.table(
  column_name = c("population_observed", "population_final", "delta_final_minus_observed", "pct_delta_final_minus_observed", "qc_state", "value_flag", "source_file", "source_sheet"),
  label = c("Poblacion observada", "Poblacion final", "Delta final - observado", "Porcentaje delta", "Estado QC", "Flag de valor", "Archivo fuente", "Hoja fuente"),
  description = c(
    "Conteo normalizado desde la fuente antes de extrapolar edades altas.",
    "Conteo publicado en el parquet contractual final.",
    "Diferencia aritmetica entre poblacion final y poblacion observada.",
    "Diferencia porcentual respecto al valor observado.",
    "Etiqueta que distingue observado preservado, observado cambiado, cola modelada/colapsada o faltante observado.",
    "Etiqueta de seguridad para cero, negativo o sin flag.",
    "Archivo Excel de INEI desde el que se parseo la fila observada.",
    "Hoja Excel de INEI desde la que se parseo la fila observada."
  )
)
write_dict(qc_observed_vs_final_path, "qc_observed_vs_final", c("year_id", "age", "sex_id", "location_id"), observed_meta)

internal_labeled <- merge(internal_dt, loc_contract[, .(location_id, location_name)], by = "location_id", all.x = TRUE)
internal_labeled <- merge(internal_labeled, sex, by = "sex_id", all.x = TRUE)
internal_labeled[is.na(location_name), location_name := as.character(location_id)]
internal_labeled[is.na(sex_name), sex_name := as.character(sex_id)]
internal_labeled[, location_label := fifelse(location_id == 0L, "Peru oficial (0)", paste0(location_name, " (", location_id, ")"))]

qc_extrapolated <- merge(
  copy(internal_labeled[age >= 75L, .(year_id, age, sex_id, sex_name, location_id, location_label, population)]),
  benchmark_dt[, .(year_id, age, sex_id, location_id, qx_benchmark, mx_benchmark, benchmark_tail_weight = tail_weight, benchmark_source, source_effective)],
  by = c("year_id", "age", "sex_id", "location_id"),
  all.x = TRUE
)
qc_extrapolated[, source_effective := benchmark_source_label(source_effective)]
setorder(qc_extrapolated, location_id, year_id, sex_id, age)
qc_extrapolated[, previous_age_population := shift(population), by = .(location_id, year_id, sex_id)]
qc_extrapolated[, delta_from_previous_age := population - previous_age_population]
qc_extrapolated[, ratio_to_previous_age := fifelse(!is.na(previous_age_population) & previous_age_population != 0L, round(population / previous_age_population, 6), NA_real_)]
qc_extrapolated[, is_extrapolated_age := age >= 80L]
qc_extrapolated[, increase_over_prior_age := is_extrapolated_age & !is.na(delta_from_previous_age) & delta_from_previous_age > 0L]
qc_extrapolated[, benchmark_population := fifelse(
  is_extrapolated_age,
  sum(population[age >= 80L], na.rm = TRUE) * benchmark_tail_weight,
  NA_real_
), by = .(location_id, year_id, sex_id)]
qc_extrapolated[, value_flag := fifelse(population < 0L, "negative",
                                       fifelse(population == 0L, "zero",
                                               fifelse(increase_over_prior_age, "tail_increase", "none")))]
qc_extrapolated_path <- file.path(downloads_dir, "qc_extrapolated_80_125.csv")
fwrite(qc_extrapolated, qc_extrapolated_path)
extrap_meta <- data.table(
  column_name = c("previous_age_population", "delta_from_previous_age", "ratio_to_previous_age", "is_extrapolated_age", "increase_over_prior_age", "qx_benchmark", "mx_benchmark", "benchmark_tail_weight", "benchmark_population", "benchmark_source", "source_effective", "value_flag"),
  label = c("Poblacion edad previa", "Delta vs edad previa", "Ratio vs edad previa", "Edad extrapolada", "Aumento vs edad previa", "qx benchmark", "mx benchmark", "Peso benchmark", "Poblacion benchmark", "Fuente benchmark", "Fuente efectiva", "Flag de valor"),
  description = c(
    "Poblacion de la edad inmediatamente anterior dentro del mismo ano, sexo y ubicacion.",
    "Diferencia entre la poblacion actual y la poblacion de la edad previa.",
    "Cociente entre la poblacion actual y la edad previa.",
    "Indica si la edad pertenece al tramo interno 80-125 generado por el modelo de cola.",
    "Indica aumento en la cola etaria; es una senal de revision, no necesariamente error fatal.",
    "Probabilidad anual de morir usada para derivar la supervivencia benchmark.",
    "Tasa central de mortalidad anual Peru por sexo y edad usada para anclar la cola.",
    "Peso de supervivencia benchmark usado para repartir la masa 80+.",
    "Conteo benchmark esperado para la edad, usando la masa del propio estrato y el peso benchmark del mismo estrato.",
    "Fuente usada para construir la schedule benchmark.",
    "Clasificacion operativa del benchmark del estrato.",
    "Etiqueta de seguridad: none, zero, negative o tail_increase."
  )
)
write_dict(qc_extrapolated_path, "qc_extrapolated_80_125", c("year_id", "age", "sex_id", "location_id"), extrap_meta)

qc_collapse_path <- file.path(downloads_dir, "qc_110plus_collapse_exact.csv")
fwrite(collapse_qc, qc_collapse_path)
collapse_meta <- data.table(
  column_name = c("pop_110plus_final", "pop_bridge_110plus", "diff", "flag_diff"),
  label = c("Poblacion 110+ final", "Poblacion puente 110+", "Delta", "Flag de diferencia"),
  description = c(
    "Conteo contractual publicado en age=110, interpretado como 110+.",
    "Valor entero del puente contractual 110+ despues del redondeo Hamilton.",
    "Diferencia entre el contractual 110+ y el puente contractual 110+.",
    "TRUE si el colapso 110+ no es exacto o falta cobertura."
  )
)
write_dict(qc_collapse_path, "qc_110plus_collapse_exact", c("year_id", "sex_id", "location_id"), collapse_meta)

official0 <- contract_dt[location_id == 0L, .(year_id, age, sex_id, official_0 = population)]
dept_sum <- contract_dt[location_id %in% 1:25, .(dept_sum = sum(population)), by = .(year_id, age, sex_id)]
add9000 <- hier_dt[location_id == 9000L, .(year_id, age, sex_id, additive_9000 = population)]
qc_national_modes <- Reduce(function(x, y) merge(x, y, by = c("year_id", "age", "sex_id"), all = TRUE), list(official0, dept_sum, add9000))
qc_national_modes <- merge(qc_national_modes, sex, by = "sex_id", all.x = TRUE)
qc_national_modes[, diff_official0_minus_dept_sum := official_0 - dept_sum]
qc_national_modes[, diff_9000_minus_dept_sum := additive_9000 - dept_sum]
qc_national_modes[, flag_official0_diff := !is.na(diff_official0_minus_dept_sum) & diff_official0_minus_dept_sum != 0L]
qc_national_modes[, flag_9000_diff := !is.na(diff_9000_minus_dept_sum) & diff_9000_minus_dept_sum != 0L]
qc_national_modes_path <- file.path(downloads_dir, "qc_national_modes.csv")
fwrite(qc_national_modes, qc_national_modes_path)
national_meta <- data.table(
  column_name = c("official_0", "dept_sum", "additive_9000", "diff_official0_minus_dept_sum", "diff_9000_minus_dept_sum", "flag_official0_diff", "flag_9000_diff"),
  label = c("Nacional oficial 0", "Suma departamental", "Nacional aditivo 9000", "Delta oficial 0 - departamentos", "Delta 9000 - departamentos", "Flag oficial 0", "Flag 9000"),
  description = c(
    "Conteo nacional oficial preservado en el output contractual con location_id 0.",
    "Suma de departamentos 1-25 para el mismo aÃ±o, edad y sexo.",
    "Conteo nacional aditivo con location_id 9000 en la vista jerarquica.",
    "Diferencia entre nacional oficial y suma departamental; es QC detectivo.",
    "Diferencia entre nacional aditivo 9000 y suma departamental; debe ser cero.",
    "TRUE cuando el nacional oficial difiere de la suma departamental.",
    "TRUE cuando 9000 no coincide con la suma departamental."
  )
)
write_dict(qc_national_modes_path, "qc_national_modes", c("year_id", "age", "sex_id"), national_meta)

qc_tail_mass_path <- file.path(downloads_dir, "qc_tail_mass_80plus_exact.csv")
fwrite(tail_mass_qc, qc_tail_mass_path)
write_dict(qc_tail_mass_path, "qc_tail_mass_80plus_exact", c("year_id", "sex_id", "location_id"))

qc_tail_cap_path <- file.path(downloads_dir, "qc_tail_cap_125_national.csv")
fwrite(tail_cap_qc, qc_tail_cap_path)
write_dict(qc_tail_cap_path, "qc_tail_cap_125_national", c("year_id", "sex_id"))

qc_tail_align_path <- file.path(downloads_dir, "qc_tail_external_alignment_national.csv")
fwrite(tail_align_qc, qc_tail_align_path)
write_dict(qc_tail_align_path, "qc_tail_external_alignment_national", c("year_id", "sex_id", "age"))

qc_tail_share_path <- file.path(downloads_dir, "qc_tail_share_110plus.csv")
fwrite(tail_share_qc, qc_tail_share_path)
write_dict(qc_tail_share_path, "qc_tail_share_110plus", c("year_id", "sex_id", "location_id"))

qc_tail_priority_path <- file.path(downloads_dir, "qc_tail_visual_priority.csv")
fwrite(tail_priority_qc, qc_tail_priority_path)
write_dict(qc_tail_priority_path, "qc_tail_visual_priority", c("year_id", "sex_id", "location_id"))

qc_glossary <- data.table(
  term = c("PK", "content_sha256", "file_md5", "location_id=0", "location_id=9000",
           "observed", "final", "extrapolated", "110+", "observed_preserved", "observed_changed",
           "missing_observed", "diff_abs", "flag_diff", "n_tail_increase_flags", "expected_counts",
           "mass_preserved_80plus", "cap_125", "largest_remainder_rounding",
           "hierarchical", "additive_national", "qc_state", "value_flag",
           "coherence_floor", "cross-repo QC", "death_110plus_summary", "mass_adjustment_from_crossrepo_qc"),
  meaning = c(
    "Llave primaria logica: year_id, age, sex_id y location_id.",
    "Hash deterministico de contenido tras ordenar por PK; es la prueba principal de compatibilidad.",
    "Checksum del archivo fisico parquet.",
    "Nacional oficial proveniente de la fuente INEI y preservado en el output contractual.",
    "Nacional aditivo construido como suma exacta de departamentos 1-25.",
    "Valor observado normalizado desde el staging OMOP-like antes de extrapolar edades altas.",
    "Valor publicado en el parquet contractual final.",
    "Valor generado por el modelo interno de extrapolacion para edades sin edad simple observada.",
    "Grupo abierto contractual representado por age=110, construido como suma exacta de la cola contractual 110-125 despues del redondeo Hamilton.",
    "El valor observado y final coinciden luego de redondeo.",
    "El valor observado y final difieren; requiere revision.",
    "No hay observacion de edad simple comparable para esa fila final.",
    "Diferencia absoluta entre dos conteos poblacionales.",
    "Indicador booleano de diferencia detectada por el QC.",
    "Conteo de estratos con aumento en la cola de edades altas.",
    "Conteos esperados internos que pueden incluir fracciones menores que 1 en edades extremas.",
    "La suma interna 80-125 coincide exactamente con la masa observada del grupo abierto 80 y +.",
    "Tope nacional por sexo y ano: a los 125 anos no puede haber mas de 1.0 persona esperada.",
    "Metodo de redondeo entero que preserva la suma total del estrato.",
    "Vista de salida que reemplaza el nacional oficial 0 por el nacional aditivo 9000.",
    "Nacional calculado como suma de departamentos.",
    "Etiqueta de estado para interpretar la comparacion observado-final.",
    "Etiqueta de seguridad para valores cero, negativos o aumentos en cola.",
    "Piso minimo contractual aplicado cuando existe al menos una muerte observada en 110+ y la poblacion contractual 110+ habria quedado en cero.",
    "Chequeo de coherencia entre este repo y mortalidad-causa-especifica mediante un snapshot agregado y no sensible.",
    "Snapshot agregado por year_id, sex_id y location_id con muertes observadas en 110+ ya armonizadas a la misma convencion contractual.",
    "Masa entera anadida al contractual 110+ por el piso minimo de coherencia cruzada."
  ),
  reader_action = c(
    "Debe ser unica en el output final.",
    "Usarlo para mostrar si el contenido cambio; en esta iteracion el cambio es esperable por la nueva semantica 110+.",
    "Sirve como evidencia secundaria de estabilidad fisica del parquet.",
    "Usarlo para compatibilidad downstream historica.",
    "Usarlo cuando se necesita consistencia jerarquica nacional-departamentos.",
    "Compararlo contra final para confirmar que no se altero lo observado.",
    "Revisar si coincide con observado o si fue extrapolado.",
    "Revisar forma de curva y ausencia de negativos o saltos imposibles.",
    "Confirmar que coincida exactamente con el puente contractual 110+ despues del redondeo Hamilton.",
    "No requiere accion.",
    "Revisar por que cambio.",
    "Esperado para la cola modelada y el colapso contractual 110+; revisar si aparece en edades observadas 0-79.",
    "Interpretar signo y magnitud.",
    "Filtrar filas TRUE.",
    "Abrir tomo de extrapolacion si es mayor que cero.",
    "Usarlo para interpretar la cola interna como masa esperada y no como conteo observado exacto.",
    "Si falla, la reasignacion de masa 80 y + esta mal.",
    "Si falla, la cola extrema nacional sigue siendo implausible.",
    "Usarlo para entender por que el contractual sigue siendo entero aunque la cola interna sea numerica.",
    "Usar para analisis que requiere aditividad.",
    "Confirmar que coincida con suma departamental.",
    "Leer antes de filtrar o resumir filas.",
    "Filtrar todo valor distinto de none.",
    "Usarlo para entender por que un 110+ contractual puede pasar de 0 a 1 sin cambiar el metodo principal de cola.",
    "Interpretarlo como una capa de QC y reconciliacion, no como insumo primario del benchmark demografico.",
    "Verificar si existio y si su estructura fue valida antes de aplicar cualquier piso.",
    "Cuantificar el impacto contractual visible de la reconciliacion con mortalidad."
  )
)
qc_glossary_path <- file.path(downloads_dir, "qc_glossary.csv")
fwrite(qc_glossary, qc_glossary_path)
write_dict(qc_glossary_path, "qc_glossary", "term")

if (nrow(nat_vs_dept)) {
  p <- ggplot(nat_vs_dept, aes(year_id, diff_abs, color = factor(sex_id))) +
    geom_hline(yintercept = 0, color = "grey70") + geom_line(alpha = 0.7) +
    facet_wrap(~ age, scales = "free_y") +
    labs(title = "Nacional oficial 0 vs suma departamental", x = "Anio",
         y = "Oficial 0 - suma departamental", color = "Sexo") + theme_portal()
  save_plot(p, file.path(qc_fig_dir, "qc_nacional_0_vs_departamentos.png"), 14, 10)
}
if (nrow(tail_flags)) {
  tail_detail <- merge(
    tail_flags[, .(year_id, sex_id, location_id)],
    internal_dt[age >= 80L],
    by = c("year_id", "sex_id", "location_id"),
    allow.cartesian = TRUE
  )
  p <- ggplot(tail_detail, aes(age, population, color = factor(sex_id), group = sex_id)) +
    geom_line() + facet_grid(location_id ~ year_id, scales = "free_y") +
    labs(title = "Flags de monotonicidad en cola etaria", x = "Edad simple",
         y = "Poblacion", color = "Sexo") + theme_portal()
  save_plot(p, file.path(qc_fig_dir, "qc_tail_monotone_flags.png"), 12, 8)
}

contract_locations <- loc_contract[location_id %in% sort(unique(contract_labeled$location_id))][order(location_id)]
contract_locations[, location_label := fifelse(location_id == 0L, "Peru oficial (0)", paste0(location_name, " (", location_id, ")"))]
sex_controls <- sex[order(sex_id)]

observed_manifest <- rbindlist(lapply(contract_locations$location_id, function(loc_id) {
  loc_label <- contract_locations[location_id == loc_id, location_label]
  rbindlist(lapply(years, function(yr) {
    rbindlist(lapply(sex_controls$sex_id, function(sid) {
      sex_label <- sex_controls[sex_id == sid, sex_name]
      d <- qc_observed_vs_final[location_id == loc_id & year_id == yr & sex_id == sid]
      out <- file.path(qc_observed_fig_dir, sprintf("observado_final_loc_%s_year_%s_sex_%s.png", loc_id, yr, sid))
      p <- ggplot(d, aes(age)) +
        annotate("rect", xmin = 79.5, xmax = 110.5, ymin = -Inf, ymax = Inf, fill = "#eef4f7", alpha = 0.7) +
        geom_line(aes(y = population_final, color = "Final"), linewidth = 0.85) +
        geom_point(aes(y = population_observed, color = "Observado"), size = 0.9, alpha = 0.75, na.rm = TRUE) +
        scale_color_manual(values = c("Final" = "#0f5b66", "Observado" = "#b77700")) +
        scale_y_continuous(labels = label_comma()) +
        scale_x_continuous(breaks = seq(0, 110, 10)) +
        labs(title = paste0("Observado vs final - ", loc_label),
             subtitle = paste0("Anio ", yr, ", sexo ", sex_label, ". Banda sombreada: cola modelada; age=110 contractual representa 110+."),
             x = "Edad simple", y = "Poblacion", color = "Serie") +
        theme_portal()
      save_plot(p, out, 9, 5.4)
      data.table(year_id = yr, location_id = loc_id, location_label = loc_label,
                 sex_id = sid, sex_name = sex_label, figure_path = norm_path(out), figure_file = basename(out))
    }))
  }))
}))
observed_manifest_path <- file.path(downloads_dir, "qc_observed_vs_final_manifest.csv")
fwrite(observed_manifest, observed_manifest_path)
write_dict(observed_manifest_path, "qc_observed_vs_final_manifest", c("year_id", "location_id", "sex_id"))

extrap_manifest <- rbindlist(lapply(contract_locations$location_id, function(loc_id) {
  loc_label <- contract_locations[location_id == loc_id, location_label]
  rbindlist(lapply(years, function(yr) {
    rbindlist(lapply(sex_controls$sex_id, function(sid) {
      sex_label <- sex_controls[sex_id == sid, sex_name]
      d_internal <- qc_extrapolated[location_id == loc_id & year_id == yr & sex_id == sid]
      d_contract <- bridge_dt[location_id == loc_id & year_id == yr & sex_id == sid]
      d_benchmark <- benchmark_dt[year_id == yr & sex_id == sid & location_id == loc_id]
      total_open <- d_internal[age >= 80L, sum(population, na.rm = TRUE)]
      d_benchmark[, population := total_open * tail_weight]
      benchmark_label <- unique(d_benchmark$source_effective)
      benchmark_label <- benchmark_label[!is.na(benchmark_label) & nzchar(benchmark_label)]
      benchmark_label <- if (length(benchmark_label)) benchmark_label[1] else "benchmark_efectivo"
      benchmark_label <- benchmark_source_label(benchmark_label)
      benchmark_label_short <- benchmark_source_label_short(d_benchmark$source_effective)
      benchmark_label_short <- benchmark_label_short[!is.na(benchmark_label_short) & nzchar(benchmark_label_short)]
      benchmark_label_short <- if (length(benchmark_label_short)) benchmark_label_short[1] else "benchmark"
      d_benchmark[, source := "Benchmark efectivo"]
      d_contract[, source := "Contractual"]
      d_contract[age == 110L, age_plot := 110L]
      d_contract[age != 110L, age_plot := age]
      d_internal_plot <- copy(d_internal[, .(age, population, source = "Interno esperado")])
      d_internal_plot[, age_plot := age]
      d_benchmark_plot <- copy(d_benchmark[, .(age, population, source)])
      d_benchmark_plot[, age_plot := age]
      d_plot <- rbindlist(list(
        d_internal_plot[age >= 75L, .(panel = "Suavizado interno 75-125", age_plot, population, source)],
        d_benchmark_plot[age >= 80L, .(panel = "Suavizado interno 75-125", age_plot, population, source)],
        d_internal_plot[age >= 80L, .(panel = "Truncamiento contractual 80-109 y 110+", age_plot, population, source)],
        d_benchmark_plot[age >= 80L, .(panel = "Truncamiento contractual 80-109 y 110+", age_plot, population, source)],
        d_contract[, .(panel = "Truncamiento contractual 80-109 y 110+", age_plot, population, source)]
      ), use.names = TRUE, fill = TRUE)
      out <- file.path(qc_extrap_fig_dir, sprintf("extrapolacion_loc_%s_year_%s_sex_%s.png", loc_id, yr, sid))
      p <- ggplot(d_plot, aes(age_plot, population, color = source, group = source)) +
        geom_vline(xintercept = 80, linetype = "dashed", color = "#9a6700") +
        geom_vline(xintercept = 110, linetype = "dotted", color = "#b42318") +
        geom_line(linewidth = 0.85) +
        geom_point(data = d_internal[age >= 80L & value_flag != "none"], aes(age, population), inherit.aes = FALSE,
                   color = "#b77700", size = 1.5) +
        geom_point(data = d_contract[age == 110L], aes(age_plot, population), inherit.aes = FALSE,
                   color = "#b42318", fill = "#ffffff", shape = 21, stroke = 1.1, size = 3.2) +
        facet_grid(panel ~ ., scales = "free_y") +
        scale_color_manual(values = c("Interno esperado" = "#0f5b66", "Benchmark efectivo" = "#b77700", "Contractual" = "#6f42c1")) +
        scale_y_continuous(labels = label_comma()) +
        scale_x_continuous(breaks = seq(75, 125, 5), limits = c(75, 125)) +
        labs(title = paste0("Cola interna 80-125 y truncamiento 110+ - ", loc_label),
             subtitle = paste0("Anio ", yr, ", sexo ", sex_label, ". Arriba: interno vs benchmark ", benchmark_label_short, ". Abajo: contractual 80-109 y punto 110+."),
             caption = paste0("Benchmark efectivo: ", benchmark_label),
             x = "Edad simple", y = "Poblacion", color = "Serie") +
        theme_portal()
      save_plot(p, out, 9, 5.4)
      data.table(year_id = yr, location_id = loc_id, location_label = loc_label,
                 sex_id = sid, sex_name = sex_label, figure_path = norm_path(out), figure_file = basename(out))
    }))
  }))
}))
extrap_manifest_path <- file.path(downloads_dir, "qc_extrapolated_80_125_manifest.csv")
fwrite(extrap_manifest, extrap_manifest_path)
write_dict(extrap_manifest_path, "qc_extrapolated_80_125_manifest", c("year_id", "location_id", "sex_id"))

national_manifest <- rbindlist(lapply(years, function(yr) {
  rbindlist(lapply(sex_controls$sex_id, function(sid) {
    sex_label <- sex_controls[sex_id == sid, sex_name]
    d <- qc_national_modes[year_id == yr & sex_id == sid]
    long_abs <- melt(d, id.vars = c("year_id", "age", "sex_id", "sex_name"),
                     measure.vars = c("official_0", "dept_sum", "additive_9000"),
                     variable.name = "national_mode", value.name = "value")
    long_abs[, panel := "Poblacion absoluta"]
    long_diff <- melt(d, id.vars = c("year_id", "age", "sex_id", "sex_name"),
                      measure.vars = c("diff_official0_minus_dept_sum", "diff_9000_minus_dept_sum"),
                      variable.name = "national_mode", value.name = "value")
    long_diff[national_mode == "diff_official0_minus_dept_sum", national_mode := "official_0 - dept_sum"]
    long_diff[national_mode == "diff_9000_minus_dept_sum", national_mode := "additive_9000 - dept_sum"]
    long_diff[, panel := "Diferencia vs suma departamental"]
    long <- rbindlist(list(long_abs, long_diff), use.names = TRUE, fill = TRUE)
    long[, panel := factor(panel, levels = c("Poblacion absoluta", "Diferencia vs suma departamental"))]
    out <- file.path(qc_national_fig_dir, sprintf("nacional_modes_year_%s_sex_%s.png", yr, sid))
    p <- ggplot(long, aes(age, value, color = national_mode)) +
      geom_line(linewidth = 0.85) +
      geom_hline(data = data.frame(panel = factor("Diferencia vs suma departamental",
                                                  levels = levels(long$panel))),
                 aes(yintercept = 0), inherit.aes = FALSE,
                 color = "#6b7280", linewidth = 0.25, linetype = "dashed") +
      facet_grid(panel ~ ., scales = "free_y") +
      scale_y_continuous(labels = label_comma()) +
      scale_x_continuous(breaks = seq(0, 110, 10)) +
      labs(title = "Nacional oficial, suma departamental y nacional aditivo",
           subtitle = paste0("Anio ", yr, ", sexo ", sex_label,
                             ". Panel inferior: diferencia contra suma departamental."),
           x = "Edad simple", y = "Poblacion", color = "Modo nacional") +
      theme_portal()
    save_plot(p, out, 9, 5.4)
    data.table(year_id = yr, sex_id = sid, sex_name = sex_label, figure_path = norm_path(out), figure_file = basename(out))
  }))
}))
national_manifest_path <- file.path(downloads_dir, "qc_national_modes_manifest.csv")
fwrite(national_manifest, national_manifest_path)
write_dict(national_manifest_path, "qc_national_modes_manifest", c("year_id", "sex_id"))

collapse_fig_path <- file.path(qc_collapse_fig_dir, "qc_110plus_collapse_exact.png")
collapse_plot <- ggplot(collapse_qc, aes(pop_bridge_110plus, pop_110plus_final, color = factor(sex_id))) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "#6b7280") +
  geom_point(alpha = 0.75, size = 1.6) +
  scale_x_continuous(labels = label_comma()) +
  scale_y_continuous(labels = label_comma()) +
  labs(title = "Chequeo exacto del colapso 110+",
       subtitle = "Cada punto es year_id-sex_id-location_id. Todos deben caer sobre la diagonal.",
       x = "Puente contractual 110+ despues de Hamilton",
       y = "Valor contractual age=110 (110+)",
       color = "sex_id") +
  theme_portal()
save_plot(collapse_plot, collapse_fig_path, 8.8, 5.6)
collapse_manifest <- data.table(
  figure_path = norm_path(collapse_fig_path),
  figure_file = basename(collapse_fig_path)
)
collapse_manifest_path <- file.path(downloads_dir, "qc_110plus_collapse_manifest.csv")
fwrite(collapse_manifest, collapse_manifest_path)
write_dict(collapse_manifest_path, "qc_110plus_collapse_manifest")

extra_qc_paths <- c(
  qc_observed_vs_final_path,
  qc_extrapolated_path,
  qc_tail_mass_path,
  qc_tail_cap_path,
  qc_tail_align_path,
  qc_tail_share_path,
  qc_tail_priority_path,
  qc_collapse_path,
  qc_national_modes_path,
  qc_glossary_path,
  observed_manifest_path,
  extrap_manifest_path,
  collapse_manifest_path,
  national_manifest_path
)
qc_extra_inventory <- rbindlist(lapply(extra_qc_paths, function(path) {
  dt <- read_csv(path)
  data.table(artifact = path, exists = file.exists(path), rows = if (file.exists(path)) nrow(dt) else NA_integer_,
             columns = if (file.exists(path)) ncol(dt) else NA_integer_,
             dictionary = dictionary_path_for_table(path),
             dictionary_exists = file.exists(dictionary_path_for_table(path)),
             download_href = if (file.exists(path)) paste0("../../downloads/", basename(path)) else NA_character_)
}), fill = TRUE)
qc_inventory <- unique(rbind(qc_inventory, qc_extra_inventory, fill = TRUE), by = "artifact")
fwrite(qc_inventory, qc_inventory_path)
write_dict(qc_inventory_path, "portal_qc_artifact_inventory")

dict_for <- function(path) read_csv(dictionary_path_for_table(path))
location_control <- data.table(title = "Region o nacional", value = as.character(contract_locations$location_id), label = contract_locations$location_label)
year_control <- data.table(title = "Anio", value = as.character(years), label = as.character(years))
sex_control <- data.table(title = "Sexo", value = as.character(sex_controls$sex_id), label = sex_controls$sex_name)

page_nav <- paste0(
  "<div class=\"page-nav\">",
  "<a href=\"../index.html\">Resumen QC</a>",
  "<a href=\"contrato.html\">Contrato</a>",
  "<a href=\"observado-final.html\">Observado vs final</a>",
  "<a href=\"extrapolacion.html\">Cola interna 80-125</a>",
  "<a href=\"nacionalidad.html\">Nacionalidad</a>",
  "<a href=\"diccionarios-glosario.html\">Glosario y diccionarios</a>",
  "</div>"
)
page_nav_index <- paste0(
  "<div class=\"page-nav\">",
  "<a href=\"tomos/contrato.html\">Contrato</a>",
  "<a href=\"tomos/observado-final.html\">Observado vs final</a>",
  "<a href=\"tomos/extrapolacion.html\">Cola interna 80-125</a>",
  "<a href=\"tomos/nacionalidad.html\">Nacionalidad</a>",
  "<a href=\"tomos/diccionarios-glosario.html\">Glosario y diccionarios</a>",
  "</div>"
)

observed_panels <- paste(vapply(seq_len(nrow(observed_manifest)), function(i) {
  r <- observed_manifest[i]
  src <- norm_path(file.path("..", "figures", "observado_final", r$figure_file))
  sprintf("<div class=\"figure-panel image-card\" data-qc-panel=\"observed\" data-location=\"%s\" data-year=\"%s\" data-sex=\"%s\"><h3>%s - %s - %s</h3><img src=\"%s\" alt=\"Observado vs final %s %s %s\"></div>",
          r$location_id, r$year_id, r$sex_id, esc(r$location_label), r$year_id, esc(r$sex_name), src, esc(r$location_label), r$year_id, esc(r$sex_name))
}, character(1)), collapse = "\n")

extrap_panels <- paste(vapply(seq_len(nrow(extrap_manifest)), function(i) {
  r <- extrap_manifest[i]
  src <- norm_path(file.path("..", "figures", "cola_interna_80_125", r$figure_file))
  sprintf("<div class=\"figure-panel image-card\" data-qc-panel=\"extrap\" data-location=\"%s\" data-year=\"%s\" data-sex=\"%s\"><h3>%s - %s - %s</h3><img src=\"%s\" alt=\"Extrapolacion %s %s %s\"></div>",
          r$location_id, r$year_id, r$sex_id, esc(r$location_label), r$year_id, esc(r$sex_name), src, esc(r$location_label), r$year_id, esc(r$sex_name))
}, character(1)), collapse = "\n")

national_panels <- paste(vapply(seq_len(nrow(national_manifest)), function(i) {
  r <- national_manifest[i]
  src <- norm_path(file.path("..", "figures", "nacionalidad", r$figure_file))
  sprintf("<div class=\"figure-panel image-card\" data-qc-panel=\"national\" data-year=\"%s\" data-sex=\"%s\"><h3>%s - %s</h3><img src=\"%s\" alt=\"Modos nacionales %s %s\"></div>",
          r$year_id, r$sex_id, r$year_id, esc(r$sex_name), src, r$year_id, esc(r$sex_name))
}, character(1)), collapse = "\n")

observed_state_summary <- qc_observed_vs_final[, .N, by = .(qc_state, value_flag)][order(qc_state, value_flag)]
extrap_flag_summary <- qc_extrapolated[, .N, by = .(is_extrapolated_age, value_flag)][order(is_extrapolated_age, value_flag)]
national_flag_summary <- qc_national_modes[, .N, by = .(flag_official0_diff, flag_9000_diff)][order(flag_official0_diff, flag_9000_diff)]

write_page(
  file.path(pipeline_pages_dir, "contrato.html"),
  "Tomo QC: contrato downstream",
  "Schema, fingerprints, dominios y chequeos que protegen la compatibilidad downstream.",
  paste0(
    card("Navegacion", page_nav, "Tomo"),
    card("Como juzgar este tomo",
         paste0("Revise que ", term("PK"), ", columnas, tipos, dominios, ",
                term("file_md5"), " y ", term("content_sha256"),
                " coincidan entre baseline y post. La coincidencia del hash de contenido es el criterio mas fuerte."),
         "Lectura"),
    card("Fingerprint baseline vs post",
         paste0(table_explain("Cada fila compara una propiedad contractual antes y despues del cambio. En esta iteracion la estructura debe coincidir; el hash de contenido puede cambiar porque age=110 ahora significa 110+.",
                              dict_for("data/derived/qc/inei_population/contract_fingerprint_post.csv")),
                html_table(fp_compare_core, 90L),
                if (nrow(fp_compare_phys)) paste0("<h3>Campos fisicos o volatiles</h3>", html_table(fp_compare_phys, 20L)) else "",
                "<a class=\"btn\" href=\"../../../downloads/contract_fingerprint_baseline.csv\">Baseline</a><a class=\"btn\" href=\"../../../downloads/contract_fingerprint_post.csv\">Post</a>"),
         "Compatibilidad"),
    card("Resumen QC contractual y jerarquico",
         paste0(table_explain("Resumen de filas, columnas, duplicados, negativos y flags principales.", dict_for("data/derived/qc/inei_population/qc_summary.csv")),
                html_table(qc_summary),
                table_explain("La vista jerarquica debe contener 9000, excluir 0 y mantener PK unica.", dict_for("data/derived/qc/inei_population/hierarchical/qc_hierarchical_summary.csv")),
                html_table(hier_summary)),
         "QC")
  ),
  "../../.."
)

write_page(
  file.path(pipeline_pages_dir, "observado-final.html"),
  "Tomo QC: observado vs final",
  "Comparacion entre edad simple observada en staging OMOP-like y el parquet contractual final.",
  paste0(
    card("Navegacion", page_nav, "Tomo"),
    card("Como juzgar este tomo",
         paste0("La serie ", term("observed"), " viene del staging normalizado. La serie ",
                term("final"), " es el parquet contractual. Desde 80 anos la cola es modelada internamente; en el contractual la ultima fila es ", term("110+"), "."),
         "Lectura"),
    card("Resumen de estados", paste0(table_explain("Use qc_state para saber si el valor observado se preservo, cambio o fue extrapolado.",
                                                    dict_for(qc_observed_vs_final_path)), html_table(observed_state_summary, 80L)), "Estados"),
    card("Dashboard observado vs final",
         dashboard_html("observed", list(location = location_control, year = year_control, sex = sex_control), observed_panels),
         "Grafico desplegable"),
    card("Filas para auditoria",
         paste0(html_table(qc_observed_vs_final[qc_state %in% c("observed_changed", "missing_observed") | value_flag != "none"], 80L),
                "<a class=\"btn\" href=\"../../../downloads/qc_observed_vs_final.csv\">Descargar tabla completa</a>"),
         "Detalle")
  ),
  "../../.."
)

write_page(
  file.path(pipeline_pages_dir, "extrapolacion.html"),
  "Tomo QC: cola interna 80-125 y truncamiento 110+",
  "Revision de la cola interna esperada, preservacion exacta de la masa 80 y + y prueba exacta del truncamiento contractual 110+.",
  paste0(
    card("Navegacion", page_nav, "Tomo"),
    card("Como juzgar este tomo",
         paste0("La linea punteada marca el inicio de ", term("extrapolated"),
                ". La cola interna llega hasta 125 con ", term("expected_counts"),
                ", preserva exactamente la masa observada 80 y + y el contractual colapsa en ", term("110+"),
                ". Filtre los puntos con ", term("value_flag"),
                " distinto de none y revise ", term("n_tail_increase_flags"), " si existe."),
         "Lectura"),
    card("Resumen de flags", paste0(table_explain("Los flags resumen ceros, negativos y aumentos en la cola interna 80-125 por fila de edad.", dict_for(qc_extrapolated_path)),
                                    html_table(extrap_flag_summary, 80L)), "Flags"),
    card("Preservacion de masa y tope nacional",
         paste0(
           table_explain("La suma interna 80-125 debe coincidir exactamente con el grupo abierto observado 80 y + en cada estrato.", dict_for(qc_tail_mass_path)),
           html_table(tail_mass_qc, 60L),
           table_explain("A nivel Peru por sexo y ano, la edad 125 no puede superar 1.0 persona esperada.", dict_for(qc_tail_cap_path)),
           html_table(tail_cap_qc, 60L)
         ),
         "QC estructural de cola"),
    card("Alineacion con benchmark y prioridad visual",
         paste0(
           table_explain("La cola interna debe replicar exactamente la schedule benchmark efectiva del estrato. Cuando la fuente es oficial regional o nacional implicita, la alineacion dura se evalua solo en edades cerradas 80-109; la fila abierta 110+ de mortalidad no se usa como input de modelamiento.", dict_for(qc_tail_align_path)),
           html_table(tail_align_qc, 60L),
           table_explain("Esta tabla indica que fuente efectiva usa cada year_id x sex_id x location_id en la cola alta.", dict_for(file.path(downloads_dir, "qc_tail_benchmark_source_by_stratum.csv"))),
           html_table(tail_source_qc, 60L),
           table_explain("Este QC debe quedar siempre en FALSE: demuestra que la fila abierta 110+ de mortalidad fue excluida del modelamiento y que la extension 110:125 se ajusto solo con edades cerradas.", dict_for(file.path(downloads_dir, "qc_tail_open_interval_exclusion.csv"))),
           html_table(tail_open_excl_qc, 60L),
           table_explain("Esta tabla resume el share 110+ esperado por benchmark y el contractual observado en cada estrato.", dict_for(qc_tail_share_path)),
           html_table(tail_share_qc[order(-pop_contract_110plus)], 60L),
           table_explain("Use este ranking para decidir que paneles mirar primero en la inspeccion humana.", dict_for(qc_tail_priority_path)),
           html_table(tail_priority_qc, 30L)
         ),
         "Benchmark y foco visual"),
    card("Coherencia cruzada mortalidad-demografia",
         paste0(
           "<p>Esta capa aplica un ", term("coherence_floor"), " solo si existe un snapshot valido ",
           term("death_110plus_summary"), " proveniente de ", term("cross-repo QC"),
           " y el contractual 110+ habria quedado en cero. No recalibra la cola interna; solo evita la incoherencia minima de tener muertes observadas 110+ con poblacion 110+ igual a 0.</p>",
           table_explain("Esta tabla muestra, por estrato, cuantas muertes observadas 110+ llegaron desde el snapshot externo, si el piso era necesario y si se aplico efectivamente.", dict_for(file.path(downloads_dir, "qc_crossrepo_110plus_coherence.csv"))),
           html_table(crossrepo_coh_qc[has_death_110plus_observed == TRUE | coherence_floor_applied == TRUE], 80L),
           table_explain("Resumen de cuantos estratos recibieron el piso y cuanta masa contractual visible se agrego por coherencia cruzada.", dict_for(file.path(downloads_dir, "qc_crossrepo_mass_adjustment.csv"))),
           html_table(crossrepo_mass_qc, 20L),
           "<a class=\"btn\" href=\"../../../downloads/qc_crossrepo_110plus_coherence.csv\">Descargar tabla completa</a>",
           "<a class=\"btn\" href=\"../../../downloads/qc_crossrepo_mass_adjustment.csv\">Descargar resumen</a>"
         ),
         "QC cruzado 110+"),
    card("Dashboard de cola interna",
         dashboard_html("extrap", list(location = location_control, year = year_control, sex = sex_control), extrap_panels),
         "Grafico desplegable"),
    card("Chequeo exacto del colapso 110+",
         paste0(table_explain("Cada fila debe cumplir que age=110 contractual sea igual al puente contractual 110+ despues del redondeo Hamilton, mas cualquier `mass_adjustment_from_crossrepo_qc` aplicado por coherencia cruzada.", dict_for(qc_collapse_path)),
                "<div class=\"image-card\"><img src=\"../figures/colapso_110plus/qc_110plus_collapse_exact.png\" alt=\"Chequeo exacto 110+\"></div>",
                html_table(collapse_qc, 80L),
                "<a class=\"btn\" href=\"../../../downloads/qc_110plus_collapse_exact.csv\">Descargar tabla completa</a>"),
         "Colapso 110+"),
    card("Filas flagged",
         paste0(html_table(qc_extrapolated[value_flag != "none"], 100L),
                "<a class=\"btn\" href=\"../../../downloads/qc_extrapolated_80_125.csv\">Descargar tabla completa</a>"),
         "Detalle")
  ),
  "../../.."
)

write_page(
  file.path(pipeline_pages_dir, "nacionalidad.html"),
  "Tomo QC: nacionalidad y aditividad",
  "Comparacion entre nacional oficial 0, suma departamental y nacional aditivo 9000.",
  paste0(
    card("Navegacion", page_nav, "Tomo"),
    card("Como juzgar este tomo",
         paste0(term("location_id=0"), " se preserva por contrato. ",
                term("location_id=9000"), " debe coincidir con la suma departamental. Las diferencias de 0 vs departamentos son QC detectivo, no ruptura contractual."),
         "Lectura"),
    card("Resumen de flags nacionales", paste0(table_explain("flag_official0_diff marca diferencias entre nacional oficial y suma departamental; flag_9000_diff debe ser FALSE.", dict_for(qc_national_modes_path)),
                                               html_table(national_flag_summary, 80L)), "Flags"),
    card("Dashboard nacional",
         dashboard_html("national", list(year = year_control, sex = sex_control), national_panels),
         "Grafico desplegable"),
    card("Filas con diferencias oficiales",
         paste0(html_table(qc_national_modes[flag_official0_diff == TRUE | flag_9000_diff == TRUE], 100L),
                "<a class=\"btn\" href=\"../../../downloads/qc_national_modes.csv\">Descargar tabla completa</a>"),
         "Detalle")
  ),
  "../../.."
)

write_page(
  file.path(pipeline_pages_dir, "diccionarios-glosario.html"),
  "Tomo QC: glosario y diccionarios",
  "Definiciones locales para columnas, criterios, estados y etiquetas del portal QC.",
  paste0(
    card("Navegacion", page_nav, "Tomo"),
    card("Glosario tecnico", paste0(table_explain("Cada criterio o etiqueta visible en el portal debe tener una definicion legible aqui.", dict_for(qc_glossary_path)),
                                    html_table(qc_glossary, 200L),
                                    "<a class=\"btn\" href=\"../../../downloads/qc_glossary.csv\">Descargar glosario</a>"), "Definiciones"),
    card("Inventario de tablas y diccionarios", paste0(table_explain("Cada artefacto tabular esperado debe tener diccionario de columnas.", dict_for(qc_inventory_path)),
                                                       html_table(qc_inventory, 120L),
                                                       "<a class=\"btn\" href=\"../../../downloads/qc_artifact_inventory.csv\">Descargar inventario</a>"), "Diccionarios")
  ),
  "../../.."
)

curve_manifest <- rbindlist(lapply(locations$location_id, function(loc_id) {
  label <- locations[location_id == loc_id, location_label]
  rbindlist(lapply(years, function(yr) {
    d <- hier_dt[location_id == loc_id & year_id == yr]
    out <- file.path(curve_dir, sprintf("curva_edad_loc_%s_year_%s.png", loc_id, yr))
    p <- ggplot(d, aes(age, population, color = sex_name)) +
      geom_line(linewidth = 0.8) +
      scale_y_continuous(labels = label_comma()) +
      scale_x_continuous(breaks = seq(0, 110, 10)) +
      labs(title = paste0("Poblacion por edad contractual - ", label),
           subtitle = paste0("Anio ", yr, ". Sexo en lineas de color. age=110 representa 110+."),
           x = "Edad simple", y = "Poblacion", color = "Sexo") + theme_portal()
    save_plot(p, out)
    data.table(year_id = yr, location_id = loc_id, location_label = label,
               figure_path = norm_path(out), figure_file = basename(out))
  }))
}))
curve_manifest_path <- file.path(downloads_dir, "coherence_curve_manifest.csv")
fwrite(curve_manifest, curve_manifest_path)
write_dict(curve_manifest_path, "coherence_curve_manifest", c("year_id", "location_id"))

trend_manifest <- rbindlist(lapply(locations$location_id, function(loc_id) {
  label <- locations[location_id == loc_id, location_label]
  d <- hier_dt[location_id == loc_id, .(population = sum(population)), by = .(year_id, sex_name)]
  out <- file.path(trend_dir, sprintf("tendencia_total_loc_%s.png", loc_id))
  p <- ggplot(d, aes(year_id, population, color = sex_name)) + geom_line(linewidth = 0.9) +
    geom_point(size = 1.2) + scale_y_continuous(labels = label_comma()) +
    labs(title = paste0("Tendencia temporal - ", label), x = "Anio",
         y = "Poblacion total", color = "Sexo") + theme_portal()
  save_plot(p, out, 9, 5)
  data.table(location_id = loc_id, location_label = label, figure_path = norm_path(out), figure_file = basename(out))
}))
trend_manifest_path <- file.path(downloads_dir, "coherence_trend_manifest.csv")
fwrite(trend_manifest, trend_manifest_path)
write_dict(trend_manifest_path, "coherence_trend_manifest", "location_id")

heatmap_manifest <- rbindlist(lapply(locations$location_id, function(loc_id) {
  label <- locations[location_id == loc_id, location_label]
  out <- file.path(heatmap_dir, sprintf("heatmap_edad_anio_loc_%s.png", loc_id))
  p <- ggplot(hier_dt[location_id == loc_id], aes(age, year_id, fill = population)) +
    geom_tile() + facet_wrap(~ sex_name, ncol = 1) +
    scale_fill_viridis_c(option = "C", labels = label_comma()) +
    scale_x_continuous(breaks = seq(0, 110, 10)) +
    labs(title = paste0("Mapa edad-anio - ", label), x = "Edad simple",
         y = "Anio", fill = "Poblacion") + theme_portal()
  save_plot(p, out, 10, 7.5)
  data.table(location_id = loc_id, location_label = label, figure_path = norm_path(out), figure_file = basename(out))
}))
heatmap_manifest_path <- file.path(downloads_dir, "coherence_heatmap_manifest.csv")
fwrite(heatmap_manifest, heatmap_manifest_path)
write_dict(heatmap_manifest_path, "coherence_heatmap_manifest", "location_id")

year_opts <- paste(sprintf("<option value=\"%s\">%s</option>", years, years), collapse = "")
loc_opts <- paste(sprintf("<option value=\"%s\">%s</option>", locations$location_id, esc(locations$location_label)), collapse = "")
curve_panels <- paste(vapply(seq_len(nrow(curve_manifest)), function(i) {
  r <- curve_manifest[i]
  src <- norm_path(file.path("figures", "curvas_edad", r$figure_file))
  sprintf("<div class=\"figure-panel image-card\" data-coh-panel=\"%s|%s\"><h3>%s - %s</h3><img src=\"%s\" alt=\"Curva %s %s\"></div>",
          r$year_id, r$location_id, esc(r$location_label), r$year_id, src, esc(r$location_label), r$year_id)
}, character(1)), collapse = "\n")
trend_panels <- paste(vapply(seq_len(nrow(trend_manifest)), function(i) {
  r <- trend_manifest[i]
  src <- norm_path(file.path("figures", "tendencias", r$figure_file))
  sprintf("<div class=\"figure-panel image-card\" data-figure-panel=\"trend-location\" data-figure-value=\"%s\"><h3>%s</h3><img src=\"%s\" alt=\"Tendencia %s\"></div>",
          r$location_id, esc(r$location_label), src, esc(r$location_label))
}, character(1)), collapse = "\n")
heatmap_panels <- paste(vapply(seq_len(nrow(heatmap_manifest)), function(i) {
  r <- heatmap_manifest[i]
  src <- norm_path(file.path("figures", "heatmaps_edad_anio", r$figure_file))
  sprintf("<div class=\"figure-panel image-card\" data-figure-panel=\"heatmap-location\" data-figure-value=\"%s\"><h3>%s</h3><img src=\"%s\" alt=\"Heatmap %s\"></div>",
          r$location_id, esc(r$location_label), src, esc(r$location_label))
}, character(1)), collapse = "\n")

coherence_body <- paste0(
  card("Curvas por edad, sexo, anio y region",
       paste0("<p>Seleccione un anio y una region o total nacional. La edad simple esta siempre en el eje X; los sexos aparecen juntos como lineas de color.</p>",
              "<div class=\"figure-controls\"><label>Anio<select data-coh-year>", year_opts, "</select></label>",
              "<label>Region o total<select data-coh-location>", loc_opts, "</select></label></div>", curve_panels),
       "Grafico principal"),
  card("Tendencia temporal auxiliar",
       paste0("<p class=\"muted\">Poblacion total anual por sexo. Es auxiliar y no reemplaza la revision por edad simple.</p>",
              "<div class=\"figure-controls\"><label>Region o total<select data-figure-switch=\"trend-location\">", loc_opts, "</select></label></div>", trend_panels),
       "Tendencias"),
  card("Mapa edad-anio auxiliar",
       paste0("<p class=\"muted\">Edad en eje X, anio en eje Y, poblacion como color y sexos facetados.</p>",
              "<div class=\"figure-controls\"><label>Region o total<select data-figure-switch=\"heatmap-location\">", loc_opts, "</select></label></div>", heatmap_panels),
       "Estructura"),
  card("Descargas",
       "<a class=\"btn\" href=\"../../downloads/coherence_curve_manifest.csv\">Manifest curvas</a><a class=\"btn\" href=\"../../downloads/coherence_trend_manifest.csv\">Manifest tendencias</a><a class=\"btn\" href=\"../../downloads/coherence_heatmap_manifest.csv\">Manifest heatmaps</a>",
       "Reproducibilidad")
)
write_page(file.path(coherence_dir, "index.html"), "Coherencia demografica",
           "Curvas por edad simple, sexo, anio y region, mas graficos auxiliares para revisar tendencias y estructura edad-anio.",
           coherence_body, "../..")

badge <- function(ok) {
  if (is.na(ok)) return("<span class=\"badge warn\">NO DISPONIBLE</span>")
  sprintf("<span class=\"badge %s\">%s</span>", if (ok) "ok" else "bad", if (ok) "OK" else "REVISAR")
}
content_badge <- function(ok) {
  if (is.na(ok)) return("<span class=\"badge warn\">NO DISPONIBLE</span>")
  if (ok) return(badge(TRUE))
  "<span class=\"badge warn\">CAMBIO ESPERADO</span>"
}
contract_ok <- identical(names(contract_dt), c("year_id", "age", "sex_id", "location_id", "population")) &&
  contract_dt[, .N, by = .(year_id, age, sex_id, location_id)][N > 1L, .N] == 0L
hier_ok <- nrow(hier_dt[location_id == 9000L]) > 0L && nrow(hier_dt[location_id == 0L]) == 0L
dict_ok <- nrow(dict_cov) > 0L && all(dict_cov$status %in% c("OK", "SKIPPED_OPTIONAL_MISSING_TABLE"))
main_fields <- c("n_rows", "n_cols", "columns", "schema", "pk_duplicate_n", "required_missing_n",
                 "year_range", "age_range", "sex_domain", "location_domain", "population_range")
fp_ok <- if (nrow(fp_compare) > 0L) all(fp_compare[field %in% main_fields, match]) else NA
fp_content_match <- if (nrow(fp_compare_phys[field == "content_sha256"]) > 0L) {
  all(fp_compare_phys[field == "content_sha256", match])
} else {
  NA
}
kpis <- data.table(
  indicador = c("Filas contrato", "Filas jerarquico", "PK duplicadas contrato", "Faltantes requeridos", "Ubicaciones coherencia", "Curvas edad-region-anio"),
  valor = c(nrow(contract_dt), nrow(hier_dt),
            contract_dt[, .N, by = .(year_id, age, sex_id, location_id)][N > 1L, .N],
            sum(vapply(names(contract_dt), function(col) sum(is.na(contract_dt[[col]])), numeric(1))),
            uniqueN(hier_dt$location_id), nrow(curve_manifest))
)
extrap_issue_n <- qc_extrapolated[value_flag != "none", .N]
nat_issue_n <- nat_vs_dept[flag_diff == TRUE, .N]
hier_issue_n <- hier_add[flag_diff == TRUE, .N]
quick_review <- paste0(
  "<p>Empiece aqui si solo quiere saber si hay algo que mirar con mas detalle.</p>",
  "<div class=\"pill-row\">",
  "<span class=\"pill\">Duplicados PK: ", contract_dt[, .N, by = .(year_id, age, sex_id, location_id)][N > 1L, .N], "</span>",
  "<span class=\"pill\">Flags cola interna 80-125: ", qc_summary$n_tail_increase_flags[[1]], "</span>",
  "<span class=\"pill\">Dif. masa 80 y +: ", qc_summary$qc_tail_mass_n_diff[[1]], "</span>",
  "<span class=\"pill\">Dif. tope nacional 125: ", qc_summary$qc_tail_cap_125_n_diff[[1]], "</span>",
  "<span class=\"pill\">Dif. exactitud 110+: ", collapse_qc[flag_diff == TRUE, .N], "</span>",
  "<span class=\"pill\">Incoherencias xrepo 110+: ", qc_summary$qc_crossrepo_110plus_n_incoherent[[1]], "</span>",
  "<span class=\"pill\">Pisos 110+ aplicados: ", qc_summary$qc_crossrepo_110plus_n_floor_applied[[1]], "</span>",
  "<span class=\"pill\">Masa agregada xrepo: ", qc_summary$qc_crossrepo_110plus_mass_added[[1]], "</span>",
  "<span class=\"pill\">Diferencias nacional oficial vs suma dept.: ", nat_issue_n, "</span>",
  "<span class=\"pill\">Diferencias 9000 vs suma dept.: ", hier_issue_n, "</span>",
  "<span class=\"pill\">Filas cola interna con flag: ", extrap_issue_n, "</span>",
  "</div>",
  "<div class=\"page-nav\">",
  "<a href=\"tomos/contrato.html\">Ir a contrato</a>",
  "<a href=\"tomos/observado-final.html\">Ir a observado-final</a>",
  "<a href=\"tomos/extrapolacion.html\">Ir a cola interna</a>",
  "<a href=\"tomos/nacionalidad.html\">Ir a nacionalidad</a>",
  "<a href=\"tomos/diccionarios-glosario.html\">Ir a glosario</a>",
  "</div>"
)
qc_fig_html <- ""
for (img in c(file.path(qc_fig_dir, "qc_nacional_0_vs_departamentos.png"), file.path(qc_fig_dir, "qc_tail_monotone_flags.png"))) {
  if (file.exists(img)) qc_fig_html <- paste0(qc_fig_html, sprintf("<div class=\"image-card\"><h3>%s</h3><img src=\"figures/%s\" alt=\"%s\"></div>", esc(tools::file_path_sans_ext(basename(img))), basename(img), basename(img)))
}
if (!nzchar(qc_fig_html)) qc_fig_html <- "<p class=\"muted\">No se generaron figuras QC auxiliares.</p>"
download_links <- paste(vapply(seq_len(nrow(qc_inventory)), function(i) {
  r <- qc_inventory[i]
  if (!isTRUE(r$exists)) return("")
  sprintf("<a class=\"btn\" href=\"%s\">%s</a>", esc(r$download_href), esc(basename(r$artifact)))
}, character(1)), collapse = "")
pipeline_body <- paste0(
  card("Que mirar primero",
       paste0("<p>Use esta pagina como tablero ejecutivo. Para revisar detalle, abra los tomos: contrato, observado-final, extrapolacion, nacionalidad y glosario.</p>",
              page_nav_index,
              "<div class=\"pill-row\"><span class=\"pill\">Contrato estructural: ", badge(contract_ok), "</span><span class=\"pill\">Jerarquico 9000: ", badge(hier_ok), "</span><span class=\"pill\">Diccionarios: ", badge(dict_ok), "</span><span class=\"pill\">Comparacion estructural baseline/post: ", badge(fp_ok), "</span><span class=\"pill\">Hash de contenido baseline/post: ", content_badge(fp_content_match), "</span></div>"),
       "Resumen"),
  card("Hallazgos y rutas de revision", quick_review, "Prioridades"),
  card("Indicadores principales", html_table(kpis), "Contrato"),
  card("Fingerprint baseline vs post",
       paste0(
         table_explain("Se muestran los campos que sirven para juzgar compatibilidad estructural y de contenido. generated_at cambia por ejecucion y se reporta aparte.",
                       dict_for("data/derived/qc/inei_population/contract_fingerprint_post.csv")),
         html_table(fp_compare_core, 80L),
         if (nrow(fp_compare_volatile)) paste0("<h3>Campos volatiles</h3>", html_table(fp_compare_volatile, 20L)) else ""
       ),
       "Compatibilidad downstream"),
  card("QC contractual", paste0("<h3>Resumen final</h3>", html_table(qc_summary), "<h3>QC jerarquico</h3>", html_table(hier_summary)), "Tablas QC"),
  card("Comparaciones detectivas",
       paste0(
         qc_fig_html,
         "<h3>Vista previa nacional oficial vs suma departamental</h3>",
         "<p class=\"muted\">Solo filas con diferencia detectiva.</p>",
         html_table(nat_vs_dept[flag_diff == TRUE], 30L),
         "<h3>Vista previa aditividad 9000</h3>",
         "<p class=\"muted\">La expectativa es cero diferencias.</p>",
         html_table(hier_add[flag_diff == TRUE], 30L)
       ),
       "Nacional"),
  card("Cobertura de diccionarios", html_table(dict_cov, 80L), "Diccionarios"),
  card("Inventario QC y descargas", paste0(html_table(qc_inventory, 100L), "<div>", download_links, "</div>"), "Artefactos")
)
write_page(file.path(pipeline_dir, "index.html"), "Pipeline QC demografico",
           "Evidencia de contrato, fingerprints, QC global, QC jerarquico, diccionarios, catalogo y provenance.",
           pipeline_body, "../..")

build_summary <- data.table(
  run_id = run_id,
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  portal_root = norm_path(portal_root),
  contract_rows = nrow(contract_dt),
  hierarchical_rows = nrow(hier_dt),
  curve_figures = nrow(curve_manifest),
  trend_figures = nrow(trend_manifest),
  heatmap_figures = nrow(heatmap_manifest),
  qc_observed_final_figures = nrow(observed_manifest),
  qc_extrapolation_figures = nrow(extrap_manifest),
  qc_110plus_collapse_figures = nrow(collapse_manifest),
  qc_national_figures = nrow(national_manifest),
  contract_ok = contract_ok,
  hierarchical_ok = hier_ok,
  dictionary_coverage_ok = dict_ok,
  fingerprint_structure_ok = fp_ok,
  fingerprint_content_match = fp_content_match
)
build_summary_path <- file.path(downloads_dir, "portal_build_summary.csv")
fwrite(build_summary, build_summary_path)
write_dict(build_summary_path, "portal_build_summary")

index_body <- paste0(
  card("Modulos", "<div class=\"module-grid\"><div class=\"module-card\"><h2>Pipeline QC</h2><p>Contrato, fingerprints, QC, diccionarios y evidencia de catalogo.</p><a class=\"btn\" href=\"modules/pipeline-qc/index.html\">Abrir QC</a></div><div class=\"module-card\"><h2>Coherencia demografica</h2><p>Curvas por edad simple, sexo, anio y region/total, con filtros interactivos.</p><a class=\"btn\" href=\"modules/coherencia-demografica/index.html\">Abrir coherencia</a></div></div>", "Portal"),
  card("Resumen de construccion", html_table(build_summary), "Evidencia"),
  card("Descargas principales", "<a class=\"btn\" href=\"downloads/portal_build_summary.csv\">Resumen build</a><a class=\"btn\" href=\"downloads/qc_artifact_inventory.csv\">Inventario QC</a><a class=\"btn\" href=\"downloads/coherence_curve_manifest.csv\">Manifest curvas</a>", "Reproducibilidad")
)
write_page(file.path(portal_root, "index.html"), "Portal QC y coherencia demografica",
           "Reporte tecnico estatico para auditar la poblacion INEI y documentar el contractual 0-109 mas 110+.",
           index_body, ".")

register_run_start(run_id, dataset_id, version)
register_artifact(dataset_id, "portal_qc_demografia_index", version, run_id, "report", file.path(portal_root, "index.html"), notes = "Static HTML portal index.")
register_artifact(dataset_id, "portal_pipeline_qc", version, run_id, "report", file.path(pipeline_dir, "index.html"), notes = "Pipeline QC HTML module.")
register_artifact(dataset_id, "portal_coherencia_demografica", version, run_id, "report", file.path(coherence_dir, "index.html"), notes = "Demographic coherence HTML module.")
register_artifact(dataset_id, "portal_build_summary", version, run_id, "qc", build_summary_path, n_rows = nrow(build_summary), n_cols = ncol(build_summary), notes = "Portal build summary.")
register_artifact(dataset_id, "coherence_curve_manifest", version, run_id, "qc", curve_manifest_path, n_rows = nrow(curve_manifest), n_cols = ncol(curve_manifest), notes = "Manifest of age curve figures.")
register_artifact(dataset_id, "coherence_trend_manifest", version, run_id, "qc", trend_manifest_path, n_rows = nrow(trend_manifest), n_cols = ncol(trend_manifest), notes = "Manifest of temporal trend figures.")
register_artifact(dataset_id, "coherence_heatmap_manifest", version, run_id, "qc", heatmap_manifest_path, n_rows = nrow(heatmap_manifest), n_cols = ncol(heatmap_manifest), notes = "Manifest of age-year heatmap figures.")
register_artifact(dataset_id, "qc_observed_vs_final", version, run_id, "qc", qc_observed_vs_final_path, n_rows = nrow(qc_observed_vs_final), n_cols = ncol(qc_observed_vs_final), notes = "Observed normalized values compared with final contractual values.")
register_artifact(dataset_id, "qc_extrapolated_80_125", version, run_id, "qc", qc_extrapolated_path, n_rows = nrow(qc_extrapolated), n_cols = ncol(qc_extrapolated), notes = "Internal high-age tail QC rows across ages 75-125.")
register_artifact(dataset_id, "qc_tail_mass_80plus_exact", version, run_id, "qc", qc_tail_mass_path, n_rows = nrow(tail_mass_qc), n_cols = ncol(tail_mass_qc), notes = "Exact check that internal ages 80-125 preserve the observed open group 80 y +.")
register_artifact(dataset_id, "qc_tail_cap_125_national", version, run_id, "qc", qc_tail_cap_path, n_rows = nrow(tail_cap_qc), n_cols = ncol(tail_cap_qc), notes = "National per-sex per-year check that internal age 125 does not exceed 1.0.")
register_artifact(dataset_id, "qc_110plus_collapse_exact", version, run_id, "qc", qc_collapse_path, n_rows = nrow(collapse_qc), n_cols = ncol(collapse_qc), notes = "Exact check that contractual age=110 equals the rounded contractual bridge 110+.")
register_artifact(dataset_id, "qc_national_modes", version, run_id, "qc", qc_national_modes_path, n_rows = nrow(qc_national_modes), n_cols = ncol(qc_national_modes), notes = "Official national, department sum and additive national comparison.")
register_artifact(dataset_id, "qc_glossary", version, run_id, "qc", qc_glossary_path, n_rows = nrow(qc_glossary), n_cols = ncol(qc_glossary), notes = "Portal glossary for QC terms and labels.")
register_run_finish(run_id, "success", "Portal QC y coherencia demografica generado.")

message("Portal written: ", normalizePath(file.path(portal_root, "index.html"), winslash = "/", mustWork = FALSE))
print(build_summary)

