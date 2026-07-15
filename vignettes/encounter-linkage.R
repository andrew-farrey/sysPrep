## ----setup, include = FALSE---------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment  = "#>"
)
library(sysPrep)
library(dplyr)

## ----prepare------------------------------------------------------------------
# Deduplicate and filter before linking
ed_clean <- essence_raw |>
  dedupe(order_by = Arrived_Date_Time, keep = "last") |>
  filter_care_setting(
    fix_facility_type_vector = c("Hillside FSED", "Downtown Emergency Services")
  )

## ----single-pull--------------------------------------------------------------
episodes <- link_encounters(ed_clean)

dplyr::glimpse(episodes)

## ----patient-class-counts-----------------------------------------------------
# Distribution of patient class rows
dplyr::count(episodes, patient_class)

## ----burden-single------------------------------------------------------------
# Unduplicated episode count (one row per encounter)
episodes |>
  dplyr::filter(.index_encounter) |>
  dplyr::count(.patient_class_sequence, sort = TRUE)

## ----two-pull, eval = FALSE---------------------------------------------------
# # Query ESSENCE for HasBeenAdmitted = 1 separately, then:
# inpatient_clean <- essence_inpatient |>
#   dedupe(order_by = Arrived_Date_Time, keep = "last")
# 
# episodes_full <- link_encounters(ed_clean, inpatient_clean)
# 
# # Direct admissions are now visible
# dplyr::filter(episodes_full, patient_class == "Direct Admit")

## ----burden-------------------------------------------------------------------
burden <- episodes |>
  dplyr::filter(.index_encounter) |>
  dplyr::count(.patient_class_sequence, sort = TRUE)

burden

## ----cluster-prep, eval = FALSE-----------------------------------------------
# # Prepare for spatial analysis: one row per encounter, with geographic field
# episodes |>
#   dplyr::filter(.index_encounter) |>
#   assign_treating_geography() |>
#   dplyr::count(region)

