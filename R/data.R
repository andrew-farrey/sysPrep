
# Synthetic dataset documentation ----

#' Synthetic raw ESSENCE-like ED visit data
#'
#' A fabricated dataset simulating a raw ESSENCE API data pull containing
#' common data quality issues: duplicate records of multiple types, non-ED
#' provider visits, out-of-state patient records, and `OTHER_REGION` entries.
#' All facility names, visit identifiers, patient identifiers, and geographic
#' values are entirely synthetic. No real patient or facility data are included.
#'
#' @format A data frame with approximately 193 rows and 18 columns:
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
#'   \item{HasBeenE}{Integer. `1` if the visit has been classified as an
#'     emergency visit. `0` on the two `patient_class_change` duplicate rows
#'     (see Details), which represent a direct-admit continuation of an ED
#'     visit; all other records have `HasBeenE = 1`, consistent with a
#'     `HasBeenE = 1` filtered ESSENCE pull.}
#'   \item{HasBeenAdmitted}{Integer. `1` if the visit resulted in
#'     inpatient admission (discharge-disposition aware).}
#'   \item{C_Patient_Class}{Character. ESSENCE-derived single-letter patient
#'     class (`"E"` for ED, `"I"` for inpatient). `classify_duplicates()`
#'     detects `patient_class_change` duplicates generically, from any two
#'     rows sharing a `facility x Visit_ID` key with distinct
#'     `C_Patient_Class` values, not a specific from/to pair. `"E"` to
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
#' }
#'
#' @details
#' ## Duplicate patterns included
#' \describe{
#'   \item{`standard`}{5 visits with an extra row differing only in
#'     `Arrived_Date_Time`, representing a record retransmission.}
#'   \item{`visit_date_change`}{3 visits with a second row carrying a new
#'     `C_BioSense_ID` and a `Date` advanced by 1 day, representing a
#'     midnight-crossing visit where `Admit_Date_Time` was updated.}
#'   \item{`pid_change`}{2 visits with a second row carrying a different
#'     `C_Unique_Patient_ID`, representing a corrected patient identifier.}
#'   \item{`patient_class_change`}{2 visits with a second row carrying
#'     `C_Patient_Class = "I"` (`HasBeenE`/`HasBeenAdmitted` flipped to
#'     match) against the original row's `"E"`, and later `C_Visit_Date_Time`/
#'     `Arrived_Date_Time` values, representing an ED visit and its
#'     direct-admit continuation transmitted as two records sharing one
#'     `Visit_ID` rather than one record with an updated
#'     `C_Patient_Class_List`. Since `dedupe(keep = "last")` keeps the more
#'     recent row by `Arrived_Date_Time`, these two visits survive into
#'     [essence_clean] as `c_patient_class = "I"`: the ED encounter is
#'     silently dropped by deduplication alone, illustrating the gap
#'     `link_encounters()` is designed to catch instead. `essence_raw` is
#'     not itself used to demonstrate `link_encounters()`; see
#'     [essence_ed_raw]/[essence_inp_raw], which are purpose-built for
#'     that.}
#'   \item{`visit_date_change+pid_change`}{1 visit exhibiting both
#'     mechanisms simultaneously.}
#' }
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
#'   [dedupe()], [filter_care_setting()], [assign_treating_geography()];
#'   [essence_ed_raw] and [essence_inp_raw] for the datasets used to
#'   demonstrate [link_encounters()].
"essence_raw"

#' Synthetic cleaned ESSENCE-like ED visit data
#'
#' The result of running `essence_raw` through the full `sysPrep` preprocessing
#' pipeline: deduplication, care setting filtering with FSED correction, and
#' both geography attribution functions chained on their default (additive)
#' behavior: `region`/`zip_code` are the untouched originals throughout;
#' [assign_treating_geography()] and [assign_facility_geography()] each add
#' their own new columns alongside them rather than overwriting. Intended to
#' demonstrate the expected output of the package workflow and to serve as
#' a reference for function output structure.
#'
#' @format A data frame with approximately 160 rows and 24 columns. All
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
#'     under `dedupe(keep = "last")`; see `c_patient_class` and
#'     `?essence_raw`.}
#'   \item{has_been_admitted}{Integer. `1` if the visit resulted in
#'     inpatient admission.}
#'   \item{c_patient_class}{Character. ESSENCE-derived single-letter patient
#'     class. `"I"` on the two visits where deduplication kept the
#'     direct-admit continuation row over the original ED row (see
#'     `?essence_raw`); `"E"` otherwise. Unchanged by the preprocessing
#'     pipeline.}
#'   \item{region}{Character. Patient ESSENCE Region of residence in
#'     `{SITE}_{REGION}` format, exactly as received; never modified by
#'     either geography function.}
#'   \item{zip_code}{Character. Patient zip code, exactly as received.}
#'   \item{sex}{Character. `"M"`, `"F"`, or `"U"`.}
#'   \item{c_patient_age}{Integer. Patient age in years.}
#'   \item{.out_of_state}{Logical. `TRUE` for visits where `region` is
#'     out-of-state, `"OTHER_REGION"`, or unknown residence; these are the
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
#'   \item{.facility_geography}{Logical. Always `TRUE`; signals that
#'     facility geography has been computed for every row. Added by
#'     [assign_facility_geography()].}
#' }
#'
#' @source Derived from [essence_raw] via
#'   `data-raw/generate_synthetic_data.R`.
#' @seealso [essence_raw] for the raw version; the Getting Started vignette
#'   for the full pipeline demonstration.
"essence_clean"

#' Synthetic raw ESSENCE-like ED pull for encounter linkage
#'
#' A small, fabricated dataset representing a `HasBeenE = 1` ESSENCE query,
#' purpose-built to demonstrate [link_encounters()] two-pull linkage in
#' `vignette("encounter-linkage")` alongside [essence_inp_raw]. Unlike
#' [essence_raw] (a single, larger, realistic pull covering every
#' deduplication/care-setting/geography issue `sysPrep` addresses),
#' `essence_ed_raw` exists solely to demonstrate encounter linkage and is
#' deliberately small. All facility names, visit identifiers, patient
#' identifiers, and geographic values are entirely synthetic. No real
#' patient or facility data are included.
#'
#' @format A data frame with approximately 15 rows and 19 columns. Same
#'   column structure as [essence_raw], plus `HasBeenI` (see Details); see
#'   [essence_raw]'s documentation for the other column definitions.
#'
#' @details
#' ## Visit types included
#' \describe{
#'   \item{Plain ED-only visits}{`HasBeenE = 1`, `HasBeenAdmitted = 0`:
#'     the majority of rows.}
#'   \item{Correctly carried-through escalation}{`HasBeenE = 1` and
#'     `HasBeenAdmitted = 1` on one already-deduplicated record; needs no
#'     cross-pull linking, since there is only ever one record. These 2
#'     visits also have `HasBeenI = 1`, so that
#'     `link_encounters()`'s preference for `HasBeenAdmitted` over
#'     `HasBeenI` when both are present is demonstrable with real data.}
#'   \item{Continuity-break ED half}{2 rows that look like plain ED visits
#'     within `essence_ed_raw` alone (`HasBeenE = 1`, `HasBeenAdmitted = 0`);
#'     their mis-submitted direct-admit continuation lives in
#'     [essence_inp_raw], sharing the same `HospitalName x Visit_ID` key.
#'     `link_encounters()` should merge each pair back into one episode.}
#' }
#'
#' One standard retransmission duplicate (same `HospitalName x Visit_ID`,
#' differing `Arrived_Date_Time`) is included so
#' `vignette("encounter-linkage")`'s "dedupe each pull separately before
#' linking" guidance has something real to demonstrate.
#'
#' @source Entirely synthetic. Generated by `data-raw/generate_synthetic_data.R`.
#' @seealso [essence_inp_raw], the paired inpatient-admission pull;
#'   [essence_raw] for the general-purpose synthetic pull used elsewhere;
#'   [link_encounters()] and `vignette("encounter-linkage")`.
"essence_ed_raw"

#' Synthetic raw ESSENCE-like inpatient admission pull for encounter linkage
#'
#' A small, fabricated dataset representing a separately queried
#' `HasBeenAdmitted = 1` ESSENCE query, purpose-built to demonstrate
#' [link_encounters()] two-pull linkage in `vignette("encounter-linkage")`
#' alongside [essence_ed_raw]. All facility names, visit identifiers,
#' patient identifiers, and geographic values are entirely synthetic. No
#' real patient or facility data are included.
#'
#' @format A data frame with approximately 6 rows and 18 columns. Same
#'   column structure as [essence_raw]; see its documentation for column
#'   definitions.
#'
#' @details
#' ## Visit types included
#' \describe{
#'   \item{Continuity-break admission half}{2 rows (`HasBeenE = 0`,
#'     `HasBeenAdmitted = 1`) sharing `HospitalName x Visit_ID` with a real
#'     row in [essence_ed_raw]: the mis-submitted direct-admit
#'     continuation of an ED visit reported as two unrelated records.}
#'   \item{Genuine direct admission}{4 rows (`HasBeenE = 0`,
#'     `HasBeenAdmitted = 1`) with a `Visit_ID` that appears nowhere in
#'     [essence_ed_raw]: true direct admissions with no preceding ED
#'     visit at all, structurally invisible to a `HasBeenE = 1` query.}
#' }
#'
#' @source Entirely synthetic. Generated by `data-raw/generate_synthetic_data.R`.
#' @seealso [essence_ed_raw], the paired ED pull; [link_encounters()] and
#'   `vignette("encounter-linkage")`.
"essence_inp_raw"
