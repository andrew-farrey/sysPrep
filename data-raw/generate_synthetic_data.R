
# Generate synthetic ESSENCE-like data for sysPrep package ----
# Run from the package root: source("data-raw/generate_synthetic_data.R")
# Does NOT require sysPrep to be installed. devtools::load_all() loads
# functions directly from source so this script can run before any
# installation step.
# All data are fully synthetic. No real patients, facilities, or geographic
# identifiers are included. Facility names, Visit_IDs, and all other
# identifiers are fabricated.

devtools::load_all(".")

library(dplyr)
library(tibble)

set.seed(2025)

# Synthetic facility reference ----
facilities <- tibble::tribble(
  ~HospitalName,                   ~Hospital, ~FacilityType,                 ~HospitalRegion,  ~HospitalZip,
  "Central Medical Center",        1001L,     "Emergency Care",              "KY_Jefferson",   "40201",
  "North County Hospital",         1002L,     "Emergency Care",              "KY_Kenton",      "41011",
  "River Valley Medical",          1003L,     "Emergency Care",              "KY_Warren",      "42101",
  "Lakeside Community Hospital",   1004L,     "Emergency Care",              "KY_Boone",       "41042",
  "Metro Health System East",      1005L,     "Emergency Care",              "KY_Fayette",     "40507",
  "Rural Health Center",           1006L,     "Emergency Care",              "KY_Madison",     "40390",
  "Hillside FSED",                 1007L,     "Urgent Care",                 "KY_Jefferson",   "40202",
  "Downtown Emergency Services",   1008L,     "Urgent Care",                 "KY_Fayette",     "40504",
  "Westside Family Practice",      1009L,     "Primary Care",                "KY_Jefferson",   "40203",
  "Cardiology Specialists Group",  1010L,     "Medical Specialty",           "KY_Fayette",     "40508"
)

# Helper: generate a Visit_ID ----
new_visit_id <- function(n) {
  sprintf("V%08d", sample(10000000:99999999, n, replace = FALSE))
}

# Helper: compute C_BioSense_ID from its source fields ----
# ESSENCE derives C_BioSense_ID by concatenating C_Visit_Date (YYYYMMDD),
# C_BioSense_Facility_ID (Hospital), and C_Unique_Patient_ID with no separator.
make_biosense_id <- function(date, hospital, pid) {
  paste0(format(date, "%Y%m%d"), hospital, pid)
}

# Helper: generate a C_Unique_Patient_ID ----
new_pid <- function(n) {
  sprintf("P%08d", sample(10000000:99999999, n, replace = FALSE))
}

# Helper: random KY region ----
ky_regions <- c(
  "KY_Jefferson", "KY_Fayette", "KY_Kenton", "KY_Boone",
  "KY_Campbell", "KY_Warren", "KY_Hardin", "KY_Madison",
  "KY_Daviess", "KY_McCracken"
)
ky_zips <- c("40201", "40507", "41011", "41042", "41011",
             "42101", "42701", "40390", "42301", "42001")

oos_regions <- c("TN_Davidson", "TN_Shelby", "OH_Hamilton", "OH_Franklin",
                 "WV_Cabell", "OTHER_REGION", NA_character_)
oos_zips    <- c("37040", "38101", "45001", "43215", "25701", NA_character_, NA_character_)

# ── Build base records (clean, non-duplicate visits) ─────────────────────────
n_clean <- 160L

# Assign visits to ED facilities only (facilities 1001-1008)
ed_facilities <- dplyr::filter(facilities, Hospital <= 1008L)

base_visits <- tibble::tibble(
  HospitalName        = sample(ed_facilities$HospitalName, n_clean, replace = TRUE,
                               prob = c(0.25, 0.15, 0.10, 0.10, 0.20, 0.05, 0.08, 0.07)),
  Visit_ID            = new_visit_id(n_clean),
  C_Unique_Patient_ID = new_pid(n_clean),
  Date                = sample(seq(as.Date("2023-01-01"), as.Date("2023-12-31"), by = "day"),
                               n_clean, replace = TRUE),
  HasBeenE            = 1L,
  HasBeenAdmitted     = sample(c(0L, 1L), n_clean, replace = TRUE, prob = c(0.75, 0.25)),
  Sex                 = sample(c("M", "F", "U"), n_clean, replace = TRUE, prob = c(0.48, 0.48, 0.04)),
  C_Patient_Age       = sample(18:85, n_clean, replace = TRUE)
) |>
  dplyr::left_join(
    dplyr::select(ed_facilities, HospitalName, Hospital, FacilityType,
                  HospitalRegion, HospitalZip),
    by = "HospitalName"
  ) |>
  dplyr::mutate(
    C_BioSense_ID   = make_biosense_id(Date, Hospital, C_Unique_Patient_ID),
    C_Patient_Class = dplyr::case_when(
      HasBeenE        == 1L ~ "E",
      HasBeenAdmitted == 1L ~ "I",
      TRUE                  ~ NA_character_
    )
  )

# Assign patient regions (mix of in-state, out-of-state, OTHER_REGION) ----
region_idx <- sample(
  c(seq_along(ky_regions), seq_along(oos_regions) + length(ky_regions)),
  n_clean, replace = TRUE,
  prob = c(rep(0.08, length(ky_regions)), rep(0.02, length(oos_regions)))
)
region_idx <- pmin(region_idx, length(ky_regions) + length(oos_regions))

base_visits <- base_visits |>
  dplyr::mutate(
    Region  = dplyr::if_else(
      region_idx <= length(ky_regions),
      ky_regions[pmin(region_idx, length(ky_regions))],
      oos_regions[pmax(region_idx - length(ky_regions), 1L)]
    ),
    ZipCode = dplyr::if_else(
      region_idx <= length(ky_regions),
      ky_zips[pmin(region_idx, length(ky_regions))],
      oos_zips[pmax(region_idx - length(ky_regions), 1L)]
    )
  )

# C_Visit_Date_Time: actual clinical encounter timestamp ----
# Arrived_Date_Time: NSSP receipt timestamp (slight lag after the visit) ----
base_visits <- base_visits |>
  dplyr::mutate(
    C_Visit_Date_Time = as.POSIXct(
      paste0(Date, " ", sprintf("%02d:%02d:%02d",
                                sample(0:23, n_clean, replace = TRUE),
                                sample(0:59, n_clean, replace = TRUE),
                                sample(0:59, n_clean, replace = TRUE))),
      tz = "America/New_York"
    ),
    Arrived_Date_Time = C_Visit_Date_Time + sample(0:7200, n_clean, replace = TRUE)
  )

# ── Add non-ED provider visits (to be filtered by filter_care_setting()) ─────
n_non_ed <- 20L
non_ed_facilities <- dplyr::filter(facilities, Hospital >= 1009L)

non_ed_visits <- tibble::tibble(
  HospitalName        = sample(non_ed_facilities$HospitalName, n_non_ed, replace = TRUE),
  Visit_ID            = new_visit_id(n_non_ed),
  C_Unique_Patient_ID = new_pid(n_non_ed),
  Date                = sample(seq(as.Date("2023-01-01"), as.Date("2023-12-31"), by = "day"),
                               n_non_ed, replace = TRUE),
  HasBeenE            = 1L,
  HasBeenAdmitted     = 0L,
  Sex                 = sample(c("M", "F"), n_non_ed, replace = TRUE),
  C_Patient_Age       = sample(18:85, n_non_ed, replace = TRUE),
  Region              = sample(ky_regions, n_non_ed, replace = TRUE),
  ZipCode             = sample(ky_zips,    n_non_ed, replace = TRUE),
  C_Visit_Date_Time   = as.POSIXct(paste0(Date, " 12:00:00"), tz = "America/New_York"),
  Arrived_Date_Time   = as.POSIXct(
    paste0(sample(seq(as.Date("2023-01-01"), as.Date("2023-12-31"), by = "day"),
                  n_non_ed, replace = TRUE), " 12:00:00"),
    tz = "America/New_York"
  )
) |>
  dplyr::left_join(
    dplyr::select(non_ed_facilities, HospitalName, Hospital, FacilityType,
                  HospitalRegion, HospitalZip),
    by = "HospitalName"
  ) |>
  dplyr::mutate(
    C_BioSense_ID   = make_biosense_id(Date, Hospital, C_Unique_Patient_ID),
    C_Patient_Class = dplyr::case_when(
      HasBeenE        == 1L ~ "E",
      HasBeenAdmitted == 1L ~ "I",
      TRUE                  ~ NA_character_
    )
  )

# ── Add duplicate records of each type ───────────────────────────────────────

# standard duplicates: same hospital x Visit_ID, minor field differences ----
standard_dups <- base_visits |>
  dplyr::slice_sample(n = 5L) |>
  dplyr::mutate(
    Arrived_Date_Time = Arrived_Date_Time + sample(300:3600, 5L, replace = TRUE)
  )

# visit_date_change duplicates: same Visit_ID, different C_BioSense_ID, Date +-1 ----
date_change_base <- base_visits |> dplyr::slice_sample(n = 3L)
date_change_dups <- date_change_base |>
  dplyr::mutate(
    Date              = Date + 1L,
    C_BioSense_ID     = make_biosense_id(Date, Hospital, C_Unique_Patient_ID),
    Arrived_Date_Time = Arrived_Date_Time + sample(3600:14400, 3L, replace = TRUE)
  )

# pid_change duplicates: same Visit_ID, different C_Unique_Patient_ID ----
pid_change_base <- base_visits |> dplyr::slice_sample(n = 2L)
pid_change_dups <- pid_change_base |>
  dplyr::mutate(
    C_Unique_Patient_ID = new_pid(2L),
    C_BioSense_ID       = make_biosense_id(Date, Hospital, C_Unique_Patient_ID),
    Arrived_Date_Time   = Arrived_Date_Time + sample(600:1800, 2L, replace = TRUE)
  )

# compound: visit_date_change + pid_change ----
compound_base <- base_visits |> dplyr::slice_sample(n = 1L)
compound_dups <- compound_base |>
  dplyr::mutate(
    Date                = Date + 1L,
    C_Unique_Patient_ID = new_pid(1L),
    C_BioSense_ID       = make_biosense_id(Date, Hospital, C_Unique_Patient_ID),
    Arrived_Date_Time   = Arrived_Date_Time + 7200L
  )

# patient_class_change duplicates: same Visit_ID x Hospital, a second row
# carrying a different C_Patient_Class value -- classify_duplicates()
# detects this from any distinct C_Patient_Class values across duplicate
# rows, not a specific from/to pair; an ED-to-inpatient transition (E -> I)
# is used here only as a common, realistic illustration. This is also the
# continuity-break case link_encounters() addresses, though essence_raw
# itself is never used to demonstrate link_encounters() directly -- see
# essence_ed_raw/essence_inp_raw below, which are purpose-built for that ----
class_change_base <- base_visits |> dplyr::slice_sample(n = 2L)
class_change_dups <- class_change_base |>
  dplyr::mutate(
    C_BioSense_ID     = paste0(make_biosense_id(Date, Hospital, C_Unique_Patient_ID), "R"),
    HasBeenE          = 0L,
    HasBeenAdmitted   = 1L,
    C_Patient_Class   = "I",
    # Advance both timestamps (not just Arrived_Date_Time) so a reader
    # inspecting the two rows directly sees the ED visit genuinely
    # preceding its direct-admit continuation, rather than an identical
    # C_Visit_Date_Time that looks like a data error ----
    C_Visit_Date_Time = C_Visit_Date_Time + sample(1800:5400, 2L, replace = TRUE),
    Arrived_Date_Time = Arrived_Date_Time + sample(1800:5400, 2L, replace = TRUE)
  )

# ── Combine all records into essence_raw ─────────────────────────────────────
essence_raw <- dplyr::bind_rows(
  base_visits,
  non_ed_visits,
  standard_dups,
  date_change_dups,
  pid_change_dups,
  compound_dups,
  class_change_dups
) |>
  # Shuffle row order to simulate a real pull
  dplyr::slice_sample(prop = 1) |>
  dplyr::select(
    HospitalName, Hospital, FacilityType, HospitalRegion, HospitalZip,
    Visit_ID, C_BioSense_ID, C_Unique_Patient_ID,
    Date, C_Visit_Date_Time, Arrived_Date_Time,
    HasBeenE, HasBeenAdmitted, C_Patient_Class,
    Region, ZipCode, Sex, C_Patient_Age
  )

# ── Build essence_clean by running the pipeline ───────────────────────────────
# Chains both geography functions on their new (additive) defaults: region/
# zip_code stay exactly as received, region_hybrid/zip_code_hybrid and
# region_facility/zip_code_facility are added alongside them. This mirrors
# the recommended pipeline shown in getting-started.Rmd, README.md, and
# vignette("geography-assignment") -- essence_clean should demonstrate the
# same call readers are told to run themselves ----
essence_clean <- essence_raw |>
  dedupe(order_by = Arrived_Date_Time, keep = "last") |>
  filter_care_setting(
    fix_facility_type_vector = c("Hillside FSED", "Downtown Emergency Services")
  ) |>
  assign_treating_geography() |>
  assign_facility_geography()

# ── Build essence_ed_raw and essence_inp_raw ──────────────────────────────────
# Two small, purpose-built synthetic pulls demonstrating link_encounters()
# two-pull linkage. Unlike essence_raw (a single realistic ED pull with
# every dedup/care-setting/geography issue baked in for the other
# vignettes), these exist solely for vignette("encounter-linkage") and
# link_encounters()'s own @examples, and are deliberately small.
# essence_ed_raw represents a HasBeenE = 1 query; essence_inp_raw
# represents a separately queried HasBeenAdmitted = 1 query. Four visit
# types are represented, split across the two:
#   1. Plain ED-only visits (essence_ed_raw): HasBeenE = 1,
#      HasBeenAdmitted = 0.
#   2. Correctly carried-through ED -> inpatient escalation
#      (essence_ed_raw only): HasBeenE = 1 and HasBeenAdmitted = 1 on one
#      already-deduplicated record -- needs no cross-pull linking.
#   3. Continuity-break artifact: an essence_ed_raw row (HasBeenE = 1,
#      HasBeenAdmitted = 0) and its mis-submitted essence_inp_raw
#      continuation (HasBeenE = 0, HasBeenAdmitted = 1) sharing
#      HospitalName x Visit_ID -- link_encounters() should merge these
#      back into one episode.
#   4. Genuine direct admission (essence_inp_raw only): HasBeenE = 0,
#      HasBeenAdmitted = 1, a Visit_ID that appears nowhere else --
#      structurally invisible to a HasBeenE = 1 query.
# One standard retransmission duplicate is included in essence_ed_raw so
# vignette("encounter-linkage")'s "dedupe each pull separately before
# linking" guidance has something real to demonstrate ----

n_ed_demo <- 14L

ed_demo_base <- tibble::tibble(
  HospitalName        = sample(ed_facilities$HospitalName, n_ed_demo, replace = TRUE),
  Visit_ID            = new_visit_id(n_ed_demo),
  C_Unique_Patient_ID = new_pid(n_ed_demo),
  Date                = sample(seq(as.Date("2023-01-01"), as.Date("2023-12-31"), by = "day"),
                               n_ed_demo, replace = TRUE),
  HasBeenE            = 1L,
  # positions 11-12: correctly carried-through escalation (both flags on
  # one record). Positions 13-14: continuity-break ED halves -- look like
  # plain ED visits here; their admission continuation lives in
  # essence_inp_raw ----
  HasBeenAdmitted     = c(rep(0L, 10L), 1L, 1L, 0L, 0L),
  # HasBeenI mirrors HasBeenAdmitted here -- in real ESSENCE data the two
  # normally move together for a genuine admission; link_encounters()
  # prefers HasBeenAdmitted when both are present (see
  # vignette("encounter-linkage")'s "Fallback: HasBeen_ flag pivot") ----
  HasBeenI            = c(rep(0L, 10L), 1L, 1L, 0L, 0L),
  Sex                 = sample(c("M", "F", "U"), n_ed_demo, replace = TRUE, prob = c(0.48, 0.48, 0.04)),
  C_Patient_Age       = sample(18:85, n_ed_demo, replace = TRUE)
) |>
  dplyr::left_join(
    dplyr::select(ed_facilities, HospitalName, Hospital, FacilityType,
                  HospitalRegion, HospitalZip),
    by = "HospitalName"
  ) |>
  dplyr::mutate(
    C_BioSense_ID     = make_biosense_id(Date, Hospital, C_Unique_Patient_ID),
    C_Patient_Class   = dplyr::if_else(HasBeenAdmitted == 1L, "I", "E"),
    Region            = sample(ky_regions, n_ed_demo, replace = TRUE),
    ZipCode           = sample(ky_zips,    n_ed_demo, replace = TRUE),
    C_Visit_Date_Time = as.POSIXct(
      paste0(Date, " ", sprintf("%02d:%02d:%02d",
                                sample(0:23, n_ed_demo, replace = TRUE),
                                sample(0:59, n_ed_demo, replace = TRUE),
                                sample(0:59, n_ed_demo, replace = TRUE))),
      tz = "America/New_York"
    ),
    Arrived_Date_Time = C_Visit_Date_Time + sample(0:7200, n_ed_demo, replace = TRUE)
  )

# One standard retransmission duplicate of the first plain ED row ----
ed_demo_dup <- ed_demo_base |>
  dplyr::slice(1L) |>
  dplyr::mutate(Arrived_Date_Time = Arrived_Date_Time + 1800L)

essence_ed_raw <- dplyr::bind_rows(ed_demo_base, ed_demo_dup) |>
  dplyr::slice_sample(prop = 1) |>
  dplyr::select(
    HospitalName, Hospital, FacilityType, HospitalRegion, HospitalZip,
    Visit_ID, C_BioSense_ID, C_Unique_Patient_ID,
    Date, C_Visit_Date_Time, Arrived_Date_Time,
    HasBeenE, HasBeenAdmitted, HasBeenI, C_Patient_Class,
    Region, ZipCode, Sex, C_Patient_Age
  )

# Build the continuity-break admission-pull continuations from
# ed_demo_base's last 2 rows (positions 13-14, chosen above), sharing
# HospitalName x Visit_ID but a later timestamp and a different
# C_BioSense_ID -- mirrors the class_change_dups mechanism above ----
continuity_break_ed_rows <- dplyr::slice(ed_demo_base, (n_ed_demo - 1L):n_ed_demo)

continuity_break_admits <- continuity_break_ed_rows |>
  dplyr::mutate(
    C_BioSense_ID     = paste0(make_biosense_id(Date, Hospital, C_Unique_Patient_ID), "R"),
    HasBeenE          = 0L,
    HasBeenAdmitted   = 1L,
    C_Patient_Class   = "I",
    C_Visit_Date_Time = C_Visit_Date_Time + sample(1800:5400, 2L, replace = TRUE),
    Arrived_Date_Time = Arrived_Date_Time + sample(1800:5400, 2L, replace = TRUE)
  )

# Genuine direct admissions: brand new Visit_IDs, no ED counterpart at all ----
n_direct_admit <- 4L

direct_admits <- tibble::tibble(
  HospitalName        = sample(ed_facilities$HospitalName, n_direct_admit, replace = TRUE),
  Visit_ID            = new_visit_id(n_direct_admit),
  C_Unique_Patient_ID = new_pid(n_direct_admit),
  Date                = sample(seq(as.Date("2023-01-01"), as.Date("2023-12-31"), by = "day"),
                               n_direct_admit, replace = TRUE),
  HasBeenE            = 0L,
  HasBeenAdmitted     = 1L,
  Sex                 = sample(c("M", "F", "U"), n_direct_admit, replace = TRUE, prob = c(0.48, 0.48, 0.04)),
  C_Patient_Age       = sample(18:85, n_direct_admit, replace = TRUE)
) |>
  dplyr::left_join(
    dplyr::select(ed_facilities, HospitalName, Hospital, FacilityType,
                  HospitalRegion, HospitalZip),
    by = "HospitalName"
  ) |>
  dplyr::mutate(
    C_BioSense_ID     = make_biosense_id(Date, Hospital, C_Unique_Patient_ID),
    C_Patient_Class   = "I",
    Region            = sample(ky_regions, n_direct_admit, replace = TRUE),
    ZipCode           = sample(ky_zips,    n_direct_admit, replace = TRUE),
    C_Visit_Date_Time = as.POSIXct(
      paste0(Date, " ", sprintf("%02d:%02d:%02d",
                                sample(0:23, n_direct_admit, replace = TRUE),
                                sample(0:59, n_direct_admit, replace = TRUE),
                                sample(0:59, n_direct_admit, replace = TRUE))),
      tz = "America/New_York"
    )
  ) |>
  dplyr::mutate(Arrived_Date_Time = C_Visit_Date_Time + sample(0:7200, n_direct_admit, replace = TRUE))

essence_inp_raw <- dplyr::bind_rows(continuity_break_admits, direct_admits) |>
  dplyr::slice_sample(prop = 1) |>
  dplyr::select(
    HospitalName, Hospital, FacilityType, HospitalRegion, HospitalZip,
    Visit_ID, C_BioSense_ID, C_Unique_Patient_ID,
    Date, C_Visit_Date_Time, Arrived_Date_Time,
    HasBeenE, HasBeenAdmitted, C_Patient_Class,
    Region, ZipCode, Sex, C_Patient_Age
  )

# ── Save as package data ──────────────────────────────────────────────────────
# version = 2 is required -- usethis::use_data() defaults to version = 3 which
# Windows libdeflate cannot decompress. base::save() with version = 2 is safe
# across all platforms and all R versions >= 2.x.
save(essence_raw,      file = "data/essence_raw.rda",      compress = "gzip", version = 2)
save(essence_clean,    file = "data/essence_clean.rda",    compress = "gzip", version = 2)
save(essence_ed_raw,   file = "data/essence_ed_raw.rda",   compress = "gzip", version = 2)
save(essence_inp_raw,  file = "data/essence_inp_raw.rda",  compress = "gzip", version = 2)

cat("Synthetic data saved to data/\n")
cat("essence_raw:     ", nrow(essence_raw),      "rows x", ncol(essence_raw),      "cols\n")
cat("essence_clean:   ", nrow(essence_clean),    "rows x", ncol(essence_clean),    "cols\n")
cat("essence_ed_raw:  ", nrow(essence_ed_raw),   "rows x", ncol(essence_ed_raw),   "cols\n")
cat("essence_inp_raw: ", nrow(essence_inp_raw),  "rows x", ncol(essence_inp_raw),  "cols\n")
