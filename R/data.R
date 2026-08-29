
# Synthetic dataset documentation ----

#' Synthetic raw ESSENCE-like ED visit data
#'
#' A fabricated dataset simulating a raw ESSENCE API data pull containing
#' common data quality issues: duplicate records of multiple types, non-ED
#' provider visits, out-of-state patient records, and `OTHER_REGION` entries.
#' All facility names, visit identifiers, patient identifiers, and geographic
#' values are entirely synthetic. No real patient or facility data are included.
#'
#' @format A data frame with approximately 197 rows and 19 columns:
#' \describe{
#'   \item{HospitalName}{Character. Synthetic facility name.}
#'   \item{Hospital}{Integer. Synthetic numeric facility identifier
#'     (`C_BioSense_Facility_ID` equivalent).}
#'   \item{FacilityType}{Character. ESSENCE facility type. Includes
#'     intentional misclassifications for two FSEDs (`"Urgent Care"`) to
#'     demonstrate [filter_care_setting()] correction logic.}
#'   \item{HospitalRegion}{Character. Facility ESSENCE Region in
#'     `{SITE}_{REGION}` format (e.g., `"KY_Jefferson"`).}
#'   \item{HospitalZip}{Character. Facility zip code.}
#'   \item{Visit_ID}{Character. Synthetic visit identifier, unique within
#'     a facility. Multiple rows with the same `HospitalName x Visit_ID`
#'     represent the duplicate patterns this package addresses.}
#'   \item{C_BioSense_ID}{Character. Synthetic BioSense record identifier.
#'     Multiple values per `Visit_ID` indicate `visit_date_change`
#'     duplication.}
#'   \item{C_Unique_Patient_ID}{Character. Synthetic patient identifier
#'     (MRN equivalent in Kentucky). Multiple values per `Visit_ID`
#'     indicate `pid_change` duplication.}
#'   \item{Date}{Date. Visit date.}
#'   \item{C_Visit_Date_Time}{POSIXct. Timestamp of the actual clinical
#'     encounter. Used by [link_encounters()] to chronologically order
#'     `.patient_class_sequence` when linking ED and direct-admit records.}
#'   \item{Arrived_Date_Time}{POSIXct. Timestamp when NSSP received the
#'     record. Use as `order_by` in [dedupe()] to retain the most recently
#'     transmitted version of each record.}
#'   \item{HasBeenE}{Integer. `1` for `PullSource = "ED"` rows, consistent
#'     with a `HasBeenE = 1` filtered ESSENCE pull. `0` on all
#'     `PullSource = "Admission"` rows (see Details): the two
#'     `patient_class_change` duplicate rows, which represent a
#'     mis-submitted direct-admit continuation of an ED visit, and four
#'     genuine direct admissions with no preceding ED visit at all.}
#'   \item{HasBeenAdmitted}{Integer. `1` if the visit resulted in
#'     inpatient admission (discharge-disposition aware).}
#'   \item{C_Patient_Class}{Character. ESSENCE-derived single-letter patient
#'     class (`"E"` for ED, `"I"` for inpatient). `classify_duplicates()`
#'     detects `patient_class_change` duplicates generically, from any two
#'     rows sharing a `facility x Visit_ID` key with distinct
#'     `C_Patient_Class` values -- not a specific from/to pair. `"E"` to
#'     `"I"` is used here only as a common, realistic illustration; see
#'     Details.}
#'   \item{Region}{Character. Patient ESSENCE Region of residence in
#'     `{SITE}_{REGION}` format. Includes out-of-state values
#'     (e.g., `"TN_Davidson"`) and `"OTHER_REGION"` entries to demonstrate
#'     [assign_treating_geography()].}
#'   \item{ZipCode}{Character. Patient zip code. May be `NA` for
#'     `OTHER_REGION` records.}
#'   \item{Sex}{Character. `"M"`, `"F"`, or `"U"` (unknown).}
#'   \item{C_Patient_Age}{Integer. Patient age in years.}
#'   \item{PullSource}{Character, `"ED"` or `"Admission"`. Not a real
#'     ESSENCE field -- marks which of two separately-run ESSENCE queries
#'     (`HasBeenE = 1` vs. `HasBeenAdmitted = 1`) this row would have come
#'     back in, so `vignette("encounter-linkage")` can split `essence_raw`
#'     back into the two pulls [link_encounters()] is designed to
#'     recombine. Drop this column (or filter and discard it) before
#'     treating a subset of `essence_raw` as a real single ESSENCE pull.}
#' }
#'
#' @details
#' ## Duplicate patterns included
#' \describe{
#'   \item{`standard`}{5 visits with an extra row differing only in
#'     `Arrived_Date_Time` -- representing a record retransmission.}
#'   \item{`visit_date_change`}{3 visits with a second row carrying a new
#'     `C_BioSense_ID` and a `Date` advanced by 1 day -- representing a
#'     midnight-crossing visit where `Admit_Date_Time` was updated.}
#'   \item{`pid_change`}{2 visits with a second row carrying a different
#'     `C_Unique_Patient_ID` -- representing a corrected patient identifier.}
#'   \item{`patient_class_change`}{2 visits with a second row carrying
#'     `C_Patient_Class = "I"` (`HasBeenE`/`HasBeenAdmitted` flipped to
#'     match) against the original row's `"E"`, and later `C_Visit_Date_Time`/
#'     `Arrived_Date_Time` values -- representing an ED visit and its
#'     direct-admit continuation transmitted as two records sharing one
#'     `Visit_ID` rather than one record with an updated
#'     `C_Patient_Class_List`. Since `dedupe(keep = "last")` keeps the more
#'     recent row by `Arrived_Date_Time`, these two visits survive into
#'     [essence_clean] as `c_patient_class = "I"` -- the ED encounter is
#'     silently dropped by deduplication alone, illustrating the gap
#'     `link_encounters()` is designed to catch instead. These are also the
#'     `PullSource = "Admission"` rows that share a `HospitalName x
#'     Visit_ID` key with a real `PullSource = "ED"` row -- see
#'     `PullSource` above.}
#'   \item{`visit_date_change+pid_change`}{1 visit exhibiting both
#'     mechanisms simultaneously.}
#' }
#'
#' ## Genuine direct admissions
#' 4 additional visits with `HasBeenE = 0`, `HasBeenAdmitted = 1`, and a
#' `Visit_ID` that appears nowhere else in `essence_raw` -- true direct
#' admissions with no preceding ED visit at all (`PullSource =
#' "Admission"`), structurally invisible to a `HasBeenE = 1` query and
#' distinct from the `patient_class_change` rows above, which share a key
#' with a real ED row. See `vignette("encounter-linkage")`.
#'
#' ## Non-ED providers
#' 20 records from a `"Primary Care"` and a `"Medical Specialty"` facility
#' are included. These should be excluded by [filter_care_setting()].
#'
#' ## FSED misclassifications
#' `"Hillside FSED"` and `"Downtown Emergency Services"` are onboarded with
#' `FacilityType = "Urgent Care"`. These require correction via
#' `fix_facility_type_vector` in [filter_care_setting()].
#'
#' @source Entirely synthetic. Generated by `data-raw/generate_synthetic_data.R`.
#'   Column structure models an ESSENCE `va_er` (Patient Location, Full
#'   Details) pull, the data source against which `sysPrep`'s functions
#'   have been validated. Encounter linkage (`link_encounters()`) expects a
#'   supplemental inpatient pull structured as `va_hosp` (Facility Location,
#'   Full Details).
#' @seealso [essence_clean] for the processed version of this dataset;
#'   [dedupe()], [filter_care_setting()], [assign_treating_geography()],
#'   [link_encounters()] for how `PullSource` is used to demonstrate
#'   two-pull encounter linkage.
"essence_raw"

#' Synthetic cleaned ESSENCE-like ED visit data
#'
#' The result of running `essence_raw` through the full `sysPrep` preprocessing
#' pipeline: deduplication, care setting filtering with FSED correction, and
#' both geography attribution functions chained on their default (additive)
#' behavior -- `region`/`zip_code` are the untouched originals throughout;
#' [assign_treating_geography()] and [assign_facility_geography()] each add
#' their own new columns alongside them rather than overwriting. Intended to
#' demonstrate the expected output of the package workflow and to serve as
#' a reference for function output structure.
#'
#' @format A data frame with approximately 164 rows and 25 columns. All
#'   column names are in snake_case (post [janitor::clean_names()]).
#' \describe{
#'   \item{hospital_name}{Character. Synthetic facility name.}
#'   \item{hospital}{Integer. Synthetic numeric facility identifier.}
#'   \item{facility_type}{Character. ESSENCE facility type. Non-ED
#'     providers have been removed; FSED corrections applied.}
#'   \item{hospital_region}{Character. Facility ESSENCE Region in
#'     `{SITE}_{REGION}` format.}
#'   \item{hospital_zip}{Character. Facility zip code.}
#'   \item{visit_id}{Character. Synthetic visit identifier, unique within
#'     a facility.}
#'   \item{c_bio_sense_id}{Character. Synthetic BioSense record identifier.
#'     One unique value per visit after deduplication.}
#'   \item{c_unique_patient_id}{Character. Synthetic patient identifier.}
#'   \item{date}{Date. Visit date.}
#'   \item{c_visit_date_time}{POSIXct. Timestamp of the actual clinical
#'     encounter.}
#'   \item{arrived_date_time}{POSIXct. NSSP record receipt timestamp.}
#'   \item{has_been_e}{Integer. `1` for an ED pull; `0` on the two visits
#'     where a `patient_class_change` direct-admit row outranked the ED row
#'     under `dedupe(keep = "last")`, plus the four genuine direct
#'     admissions with no ED row at all -- see `c_patient_class` and
#'     `?essence_raw`.}
#'   \item{has_been_admitted}{Integer. `1` if the visit resulted in
#'     inpatient admission.}
#'   \item{c_patient_class}{Character. ESSENCE-derived single-letter patient
#'     class. `"I"` on the visits where deduplication kept a direct-admit
#'     row over (or with no) original ED row (see `?essence_raw`); `"E"`
#'     otherwise. Unchanged by the preprocessing pipeline.}
#'   \item{region}{Character. Patient ESSENCE Region of residence in
#'     `{SITE}_{REGION}` format, exactly as received -- never modified by
#'     either geography function.}
#'   \item{zip_code}{Character. Patient zip code, exactly as received.}
#'   \item{sex}{Character. `"M"`, `"F"`, or `"U"`.}
#'   \item{c_patient_age}{Integer. Patient age in years.}
#'   \item{.out_of_state}{Logical. `TRUE` for visits where `region` is
#'     out-of-state, `"OTHER_REGION"`, or unknown residence -- these are the
#'     visits where `region_hybrid` differs from `region`. Added by
#'     [assign_treating_geography()].}
#'   \item{region_hybrid}{Character. `region` for in-state visits;
#'     `hospital_region` for out-of-state/`OTHER_REGION`/unknown-residence
#'     visits. Added by [assign_treating_geography()].}
#'   \item{zip_code_hybrid}{Character. `zip_code` analog of
#'     `region_hybrid`.}
#'   \item{region_facility}{Character. `hospital_region` for every visit,
#'     regardless of patient residence. Added by
#'     [assign_facility_geography()].}
#'   \item{zip_code_facility}{Character. `zip_code` analog of
#'     `region_facility`.}
#'   \item{.facility_geography}{Logical. Always `TRUE` -- signals that
#'     facility geography has been computed for every row. Added by
#'     [assign_facility_geography()].}
#'   \item{pull_source}{Character, `"ED"` or `"Admission"`. Carried through
#'     from `essence_raw`'s `PullSource`, converted to snake_case by
#'     [janitor::clean_names()] like any other column; not a real ESSENCE
#'     field -- see `?essence_raw`.}
#' }
#'
#' @source Derived from [essence_raw] via
#'   `data-raw/generate_synthetic_data.R`.
#' @seealso [essence_raw] for the raw version; the Getting Started vignette
#'   for the full pipeline demonstration.
"essence_clean"
