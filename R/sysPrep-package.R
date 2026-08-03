
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @importFrom dplyr across all_of arrange bind_rows case_when desc filter group_by if_else left_join mutate n n_distinct pick recode_values rows_update select semi_join slice slice_max starts_with summarise ungroup
#' @importFrom janitor adorn_pct_formatting clean_names make_clean_names tabyl
#' @importFrom rlang .data := abort as_name as_string enquo ensym inform quo_is_null sym warn
#' @importFrom stats quantile
#' @importFrom stringr fixed str_detect str_starts
#' @importFrom tibble tibble
#' @importFrom tidyr pivot_longer pivot_wider unnest
#' @importFrom cli cli_alert_info cli_bullets cli_h1 cli_h2 cli_text
## usethis namespace: end
utils::globalVariables(c(
  # Default column name values in function signatures
  "HospitalName", "Visit_ID", "FacilityType", "Region",
  "HospitalRegion", "HospitalZip", "ZipCode", "Hospital",
  # Computed variables used as bare names inside dplyr verbs
  "n_rows", "n_dates", "n_pid", "n_patient_classes",
  "n_duplicated_visit_ids", "n_visits", "n_excess_rows",
  "n_duplicated_total", "n_days",
  # Internal dot-prefixed columns created with mutate()
  ".n_complete", ".pair_key", ".episode_id", ".out_of_state",
  ".original_facility_type", ".date_change", ".pid_change", ".class_change",
  ".q1", ".q3", ".iqr", ".outlier_low", ".outlier_high",
  ".outlier_flag", ".outlier_direction", ".class_time",
  # Other bare column references in dplyr contexts
  "dup_type", "corrected_facility_type", "patient_class", "present",
  "c_visit_date_time", "date", "time",
  # Intermediate columns created by strsplit + unnest in link_encounters()
  "pc_split", "mdt_split",
  # Base function used without package prefix in clean_names_safe()
  "setNames"
))
NULL
