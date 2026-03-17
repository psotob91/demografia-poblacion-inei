# scripts/03_extrapola_80_110.R
library(data.table)
library(splines)
library(arrow)
library(here)

source(here("R/io_utils.R"))
source(here("R/spec_utils.R"))

`%||%` <- function(x, y) if (is.null(x)) y else x

P <- paths_inei()
dir.create(P$FINAL_DIR, recursive = TRUE, showWarnings = FALSE)

SPEC <- read_spec(here("config", "spec_population_inei.yml"))

fit_min   <- SPEC$policy$extrapolation$fit_age_min %||% 70L
fit_max   <- SPEC$policy$extrapolation$fit_age_max %||% 79L
spline_df <- SPEC$policy$extrapolation$spline_df %||% 4L
age_max   <- SPEC$constraints$age$max %||% 110L

dt <- as.data.table(arrow::read_parquet(file.path(P$STAGE_DIR, "omop_like_long.parquet")))

# Solo edad simple observada
pop_age <- dt[age_type == "age_single" & !is.na(age)]
pop_age[, population := as.numeric(population_raw)]

# FINAL solo M/F -> sex_id OMOP concept id
pop_age[, sex_id := fifelse(gender_source_value == "M", 8507L,
                            fifelse(gender_source_value == "F", 8532L, NA_integer_))]
pop_age <- pop_age[!is.na(sex_id)]

# Congelar location_id como ubigeo depto (00–25)
pop_age[, location_id := as.integer(location_id)]

by_strata <- c("location_id", "year_id", "sex_id")
new_ages <- 0:age_max

pred <- pop_age[
  age >= fit_min & age <= fit_max,
  {
    tmp <- .SD[!is.na(population) & population > 0]
    if (nrow(tmp) < 8L || uniqueN(tmp$age) < 8L) {
      .(age = new_ages, population_pred = NA_real_)
    } else {
      fit <- lm(log(population) ~ ns(age, df = spline_df), data = tmp)
      pred_pop <- exp(predict(fit, newdata = data.table(age = new_ages)))
      
      # Monotonicidad solo desde fit_min (70+)
      idx0 <- which(new_ages == fit_min)
      if (length(idx0) == 1L) {
        for (i in seq(idx0 + 1L, length(pred_pop))) {
          if (!is.na(pred_pop[i - 1L]) && pred_pop[i] > pred_pop[i - 1L]) {
            pred_pop[i] <- pred_pop[i - 1L]
          }
        }
      }
      pred_pop[pred_pop < 0] <- 0
      .(age = new_ages, population_pred = pred_pop)
    }
  },
  by = by_strata
]

pop_age[, population_obs := population]
pop_age[, population := NULL]

ext <- merge(
  pop_age[, .(location_id, year_id, sex_id, age, population_obs)],
  pred,
  by = c(by_strata, "age"),
  all = TRUE
)

ext[, population := data.table::fcoalesce(population_obs, population_pred)]
ext[, population := as.integer(round(population))]
ext <- ext[!is.na(population)]  # seguridad

final <- ext[, .(year_id, age, sex_id, location_id, population)]
setkey(final, year_id, age, sex_id, location_id)

out_fp <- file.path(P$FINAL_DIR, "population_result.parquet")
arrow::write_parquet(final, out_fp)
message("✅ FINAL guardado: ", out_fp)
