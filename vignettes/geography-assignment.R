## ----setup, include = FALSE---------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment  = "#>"
)
library(sysPrep)
library(dplyr)

## ----region-examples----------------------------------------------------------
# Illustrate the detection logic on a few example values
region_examples <- c("KY_Jefferson", "TN_Davidson", "OH_Hamilton",
                     "OTHER_REGION", NA_character_)

data.frame(
  region   = region_examples,
  in_state = startsWith(
    tidyr::replace_na(region_examples, ""),
    "KY_"
  ) & !is.na(region_examples)
)

## ----treating-geography-------------------------------------------------------
# Start from deduplicated, filtered data
ed_clean <- essence_raw |>
  dedupe(order_by = Arrived_Date_Time, keep = "last") |>
  filter_care_setting(
    fix_facility_type_vector = c("Hillside FSED", "Downtown Emergency Services")
  )

# Selective reassignment: only out-of-state and OTHER_REGION rows change
treating_geo <- ed_clean |>
  assign_treating_geography(
    site                        = "KY",
    preserve_original_geographies = TRUE
  )

## ----treating-counts----------------------------------------------------------
# How many visits were reassigned?
dplyr::count(treating_geo, .out_of_state)

## ----treating-comparison------------------------------------------------------
# Compare region before and after for reassigned rows
treating_geo |>
  dplyr::filter(.out_of_state) |>
  dplyr::select(hospital_name, original_region, region) |>
  head(10)

## ----facility-geography-------------------------------------------------------
# Universal reassignment: ALL rows get facility geography
facility_geo <- ed_clean |>
  assign_facility_geography(
    preserve_original_geographies = TRUE
  )

## ----facility-comparison------------------------------------------------------
# After full reassignment, region = hospital_region for all rows
facility_geo |>
  dplyr::select(hospital_name, hospital_region, region, original_region) |>
  head(10)

## ----facility-verify----------------------------------------------------------
# Confirm: region == hospital_region for every row
all(facility_geo$region == facility_geo$hospital_region)

