## ----setup, include = FALSE---------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment  = "#>"
)
library(sysPrep)
library(dplyr)

## ----install, eval = FALSE----------------------------------------------------
# # CRAN (when available)
# install.packages("sysPrep")
# 
# # Development version
# remotes::install_github("andrew-farrey/sysPrep")

## ----glimpse------------------------------------------------------------------
dplyr::glimpse(essence_raw)

## ----pipeline-----------------------------------------------------------------
clean <- essence_raw |>
  # Step 1: Remove duplicate records, retaining the most recently transmitted
  dedupe(order_by = Arrived_Date_Time, keep = "last") |>
  # Step 2: Filter to valid ED and inpatient providers; correct FSED types
  filter_care_setting(
    fix_facility_type_vector = c("Hillside FSED", "Downtown Emergency Services")
  ) |>
  # Step 3: Assign treating facility geography to out-of-state and OTHER_REGION visits
  assign_treating_geography(preserve_original_geographies = TRUE)

## ----compare------------------------------------------------------------------
cat("Raw rows:   ", nrow(essence_raw), "\n")
cat("Clean rows: ", nrow(clean), "\n")
cat("\nRows removed at each step:\n")
cat("  Duplicates removed:         ",
    nrow(essence_raw) - nrow(dedupe(essence_raw, order_by = Arrived_Date_Time)), "\n")

after_dedup <- essence_raw |>
  dedupe(order_by = Arrived_Date_Time, keep = "last")
after_filter <- after_dedup |>
  filter_care_setting(
    fix_facility_type_vector = c("Hillside FSED", "Downtown Emergency Services")
  )
cat("  Non-ED providers excluded:  ",
    nrow(after_dedup) - nrow(after_filter), "\n")
cat("\nNew columns added by assign_treating_geography():\n")
cat(" ", paste(setdiff(names(clean), names(essence_raw)), collapse = ", "), "\n")

## ----reassigned---------------------------------------------------------------
# How many visits had geography reassigned?
dplyr::count(clean, .out_of_state)

