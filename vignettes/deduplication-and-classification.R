## ----setup, include = FALSE---------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment  = "#>"
)
library(sysPrep)
library(dplyr)

## ----summarize----------------------------------------------------------------
dups <- summarize_duplicates(essence_raw)
dups

## ----summarize-components-----------------------------------------------------
# Dataset-level counts
dups$overall

# Per-facility counts (facilities with duplicates only)
dups$by_facility

## ----classify-----------------------------------------------------------------
classified <- classify_duplicates(essence_raw)
classified

## ----classify-overall---------------------------------------------------------
# Type distribution across the full dataset
classified$overall

## ----classify-facility--------------------------------------------------------
# Per-facility breakdown by type (wide format)
classified$by_facility

## ----classify-tibble----------------------------------------------------------
# Join mechanism type back to raw data for row-level inspection.
# classify_duplicates() returns cleaned (snake_case) column names,
# so clean essence_raw first to align join keys.
typed <- essence_raw |>
  janitor::clean_names() |>
  dplyr::left_join(
    classify_duplicates(essence_raw, return_format = "tibble"),
    by = c("hospital_name", "visit_id")
  )

dplyr::count(typed, dup_type)

## ----dedupe-------------------------------------------------------------------
deduped <- dedupe(essence_raw, order_by = Arrived_Date_Time, keep = "last")

cat("Rows before: ", nrow(essence_raw), "\n")
cat("Rows after:  ", nrow(deduped), "\n")
cat("Rows removed:", nrow(essence_raw) - nrow(deduped), "\n")

## ----verify-zero--------------------------------------------------------------
# Confirm zero duplicate groups remain
summarize_duplicates(deduped)$overall

