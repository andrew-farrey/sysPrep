
# filter_care_setting() ----
#' Filter ESSENCE data to valid emergency and inpatient care settings
#'
#' Retains visits from facilities with emergency department or inpatient
#' admission capacity. Optionally corrects known `FacilityType`
#' misclassifications, such as free-standing EDs (FSEDs) onboarded with
#' non-emergency facility types, before the keep filter is applied,
#' ensuring valid ED visits are not incorrectly excluded.
#'
#' @details
#' ## Why this function exists
#' The most reliable way to isolate emergency department visits from
#' non-emergency providers is to filter to a valid `FacilityType` before or
#' during case counting. Where a site's facilities are consistently onboarded
#' to ESSENCE, restricting the query itself to `FacilityType = "Emergency
#' Care"` (a front-end filter, applied before the pull) avoids returning
#' non-ED provider data at all. This approach worked reliably for years in
#' Kentucky, until several free-standing emergency departments (FSEDs) were
#' onboarded to ESSENCE with a `FacilityType` other than `"Emergency Care"`.
#' A front-end query filtered to `FacilityType = "Emergency Care"` now
#' silently excludes these FSEDs' legitimate ED visits, even though each
#' operates a true emergency department.
#'
#' Once front-end filtering by `FacilityType` can no longer be trusted for a
#' site, a raw pull returns every facility type that submitted matching
#' records, including primary care clinics, specialty practices, and other
#' genuinely non-ED providers whose visits should not contribute to an
#' ED-based numerator or denominator. `filter_care_setting()` addresses this
#' by first correcting the small, known set of misclassified facilities (by
#' name, ID, or pattern) to a valid ED-consistent `FacilityType`, then
#' filtering to `keep_types`. This makes it possible to filter reproducibly
#' and defensibly on `FacilityType` again, without excluding true ED visits
#' or manually rebuilding the correction list for every pull. Whether this
#' pre-cleaning step is worthwhile depends on a site's own onboarding
#' consistency: sites where `FacilityType` reliably identifies emergency
#' providers may not need it at all.
#'
#' ## FSED facility type assignment
#' The specific pattern observed in Kentucky's ESSENCE data is that some
#' FSEDs are onboarded with a `FacilityType` of `"Urgent Care"` rather than
#' `"Emergency Care"`. This reflects what has been observed and processed in
#' Kentucky's data specifically; it is not a documented or guaranteed
#' convention across all NSSP sites, and other sites may see FSEDs (or other
#' facility types) onboarded under different `FacilityType` values entirely.
#' Regardless of which value a given site observes, the
#' `fix_facility_type_vector`, `fix_facility_id_vector`, and
#' `fix_facility_type_regex` parameters exist to reassign known misclassified
#' facilities to a specified `fix_to` value before the `keep_types` filter is
#' applied.
#'
#' ## Default `keep_types`
#' The default `keep_types` of `c("Emergency Care", "Inpatient Practice
#' Setting")` keeps both facility types that identify hospitals with emergency
#' or inpatient capacity, so a pull that mixes ED and inpatient records is not
#' silently narrowed. In Kentucky, inpatient admission data are transmitted
#' through the corresponding ED hospital feeds and carry the ED
#' `FacilityType`, so Kentucky pulls do not depend on the second value; sites
#' whose inpatient feeds are onboarded under `"Inpatient Practice Setting"`
#' do. Sites pulling ED visits only should set `keep_types = "Emergency Care"`.
#'
#' ## Facility name column
#' Unlike the duplicate and review functions, `filter_care_setting()` does not
#' prefer `Hospital` over `HospitalName` for `facility_col`: its name-based
#' corrections (`fix_facility_type_vector`, `fix_facility_type_regex`) match
#' facility *names*, so the column must hold names. The ID-based route
#' (`fix_facility_id_vector`, matched on `facility_id_col`) is the one that
#' uses the stable identifier.
#'
#' ## Processing order
#' Corrections are applied before filtering, in this sequence:
#'
#' 1. Exact ID corrections (`fix_facility_id_vector`)
#' 2. Exact name corrections (`fix_facility_type_vector`)
#' 3. Regex name corrections (`fix_facility_type_regex`)
#' 4. Filter to `keep_types`
#'
#' ID and name corrections are both exact-match methods and take precedence
#' over regex: a facility corrected by either `fix_facility_id_vector` or
#' `fix_facility_type_vector` will not be re-evaluated by
#' `fix_facility_type_regex`, even if its name also happens to match the
#' pattern.
#'
#' ## Facility ID vs. facility name corrections
#' `fix_facility_id_vector` matches on `facility_id_col` (`Hospital` /
#' `C_BioSense_Facility_ID` by default), which does not change even when a
#' facility's name is edited or the facility is rebranded. For a correction
#' list reused across many recurring pulls, ID-based correction is more
#' durable than name-based correction. `fix_facility_type_vector` remains
#' available for cases where the ID isn't known or `Hospital` wasn't
#' included as a pull field. Both accept the same `fix_to` value and can be
#' used together.
#'
#' ## dry_run preview
#' When `dry_run = TRUE`, the function returns a preview tibble showing each
#' facility's original and corrected `FacilityType`, visit count, and whether
#' it would be retained, without modifying the data. Use this to verify
#' corrections and `keep_types` before committing to a filter.
#'
#' ## Warnings and dry_run
#' Facilities matched and corrected via `fix_facility_type_regex` are always
#' surfaced in a warning, since regex matching is open-ended: a newly
#' onboarded facility could start matching the pattern at any time, which is
#' worth knowing about on every run, not just during setup. These are
#' candidates for promotion to `fix_facility_type_vector` or
#' `fix_facility_id_vector` for explicitness and long-term reproducibility.
#'
#' Unmatched entries in `fix_facility_type_vector` (a name with zero matching
#' rows in this pull) only produce a warning when `dry_run = TRUE`. A
#' persistent correction list reused across many pulls will routinely include
#' facilities with zero visits in a given pull; this is expected, not an
#' error, so it isn't surfaced on ordinary (non-`dry_run`) runs. `dry_run`
#' is the intended point to verify a correction list is behaving as expected.
#' Unmatched entries in `fix_facility_id_vector` never produce a warning, at
#' any setting, for the same reason.
#'
#' @inheritParams dedupe
#' @inheritParams classify_duplicates
#' @param data A data frame of ESSENCE visit-level records, typically the
#'   output of [dedupe()].
#' @param facility_col Unquoted
#'   column name identifying the facility. Defaults to `HospitalName`, and
#'   unlike other functions does not prefer `Hospital`; see "Facility name
#'   column" in Details. Accepts both raw ESSENCE names and
#'   post-[janitor::clean_names()] equivalents.
#' @param facility_type_col
#'   Unquoted column name identifying the facility type. Defaults to
#'   `FacilityType`. Accepts both raw ESSENCE names and
#'   post-[janitor::clean_names()] equivalents.
#' @param facility_id_col
#'   Unquoted column name identifying the facility's stable numeric ID.
#'   Defaults to `Hospital` (`C_BioSense_Facility_ID` in the NSSP Master
#'   Facility Table). Accepts both raw ESSENCE names and
#'   post-[janitor::clean_names()] equivalents, and any arbitrarily-named
#'   column. Optional: if absent and `fix_facility_id_vector` is not
#'   supplied, ID-based correction is skipped with an informative message.
#' @param keep_types Character vector of `FacilityType` values to retain
#'   after corrections are applied. Defaults to
#'   `c("Emergency Care", "Inpatient Practice Setting")` for ED + inpatient
#'   cohorts. Set to `"Emergency Care"` for ED-only cohorts. Values are
#'   matched exactly, including capitalization.
#' @param fix_facility_id_vector Optional numeric or character vector of
#'   exact facility IDs as they appear in `facility_id_col`. Matching
#'   facilities have their `FacilityType` set to `fix_to` before filtering.
#'   Both the supplied vector and the data column are coerced to character
#'   before matching, so numeric and character forms of the same IDs behave
#'   identically. More durable than `fix_facility_type_vector` for a
#'   correction list reused across many pulls, since facility IDs do not
#'   change when a facility is renamed. Unmatched IDs never produce a
#'   warning; see Details.
#' @param fix_facility_type_vector Optional character vector of exact facility
#'   names as they appear in `facility_col`. Matching facilities have their
#'   `FacilityType` set to `fix_to` before filtering. Use for known FSEDs
#'   or other facilities with confirmed misclassifications. Unmatched names
#'   only produce a warning when `dry_run = TRUE`; see Details.
#' @param fix_facility_type_regex Optional regular expression matched against
#'   `facility_col` values. Facilities not already corrected by
#'   `fix_facility_id_vector` or `fix_facility_type_vector` whose names match
#'   the pattern have their `FacilityType` set to `fix_to`. Matched names are
#'   always surfaced in a warning as candidates for `fix_facility_type_vector`
#'   or `fix_facility_id_vector`.
#' @param fix_to Character string. The `FacilityType` value assigned to
#'   facilities matched by any correction parameter. Defaults to
#'   `"Emergency Care"`.
#' @param dry_run Logical. If `TRUE`, returns a preview tibble showing each
#'   facility's original facility type, corrected facility type, visit count,
#'   and whether it would be retained, without modifying or filtering the
#'   data. Defaults to `FALSE`.
#' @return When `dry_run = FALSE` (default), a filtered data frame retaining
#'   only visits from facilities whose `FacilityType`, after any corrections,
#'   appears in `keep_types`. When `dry_run = TRUE`, a tibble with columns
#'   `facility`, `facility_id` (when `facility_id_col` resolves),
#'   `original_facility_type`, `corrected_facility_type`, `n_visits`, and
#'   `.would_keep`, arranged by `n_visits` descending.
#'
#' @examples
#' # Default: keep Emergency Care and Inpatient Practice Setting
#' essence_raw |> filter_care_setting()
#'
#' # ED-only cohort
#' essence_raw |> filter_care_setting(keep_types = "Emergency Care")
#'
#' # Preview what would be filtered before committing
#' essence_raw |>
#'   filter_care_setting(
#'     fix_facility_type_vector = c(
#'       "Hillside FSED", "Downtown Emergency Services"
#'     ),
#'     dry_run = TRUE
#'   )
#'
#' # Exact FSED corrections
#' essence_raw |>
#'   filter_care_setting(
#'     fix_facility_type_vector = c(
#'       "Hillside FSED",
#'       "Downtown Emergency Services"
#'     )
#'   )
#'
#' # Regex fallback for catching FSEDs by name pattern
#' essence_raw |>
#'   filter_care_setting(
#'     fix_facility_type_vector = c("Hillside FSED"),
#'     fix_facility_type_regex  = "FSED|ED - Urgent Care"
#'   )
#'
#' # ID-based corrections: durable across facility name changes/rebranding
#' essence_raw |>
#'   filter_care_setting(fix_facility_id_vector = c(1007, 1008))
#'
#' # ID and name corrections can be combined
#' essence_raw |>
#'   filter_care_setting(
#'     fix_facility_id_vector   = 1007,
#'     fix_facility_type_vector = "Downtown Emergency Services"
#'   )
#'
#' # Full pipeline
#' essence_raw |>
#'   dedupe(order_by = Arrived_Date_Time) |>
#'   filter_care_setting(
#'     fix_facility_type_vector = c(
#'       "Hillside FSED", "Downtown Emergency Services"
#'     )
#'   )
#'
#' @seealso [review_facility_ed_visits()] for flagging facility-level visit
#'   count outliers after filtering.
#' @export
filter_care_setting <- function(data,
                                facility_col = HospitalName,
                                facility_type_col = FacilityType,
                                facility_id_col = Hospital,
                                keep_types = c("Emergency Care",
                                               "Inpatient Practice Setting"),
                                fix_facility_id_vector = NULL,
                                fix_facility_type_vector = NULL,
                                fix_facility_type_regex = NULL,
                                fix_to = "Emergency Care",
                                dry_run = FALSE,
                                clean_names = TRUE,
                                verbose = TRUE) {

  check_data_frame(data)
  check_character(keep_types)
  check_character(fix_facility_type_vector, allow_null = TRUE)
  check_string(fix_facility_type_regex, allow_null = TRUE)
  check_string(fix_to)
  check_flag(dry_run)
  check_flag(clean_names)
  check_flag(verbose)

  # Normalize names upfront, remembering the originals for clean_names =
  # FALSE ----
  original_names <- names(data)
  data           <- clean_names_safe(data)
  name_map       <- input_name_map(original_names, names(data))

  fac_col_str  <- resolve_col_str(data, rlang::ensym(facility_col))
  type_col_str <- resolve_col_str(data, rlang::ensym(facility_type_col))

  # Resolve facility_id_col optionally; not required unless
  # fix_facility_id_vector is actually supplied ----
  id_col_sym      <- resolve_col_optional(data, rlang::ensym(facility_id_col))
  id_col_str      <- resolve_facility_id_str(
    id_col_sym, fix_facility_id_vector, verbose
  )
  use_facility_id <- !is.na(id_col_str)

  # Preserve original facility_type for dry_run comparison ----
  data <- dplyr::mutate(
    data,
    .original_facility_type = .data[[type_col_str]]
  )

  # Apply the three correction routes in order: ID, exact name, then regex
  # (which skips facilities an earlier route already corrected) ----
  by_id <- correct_by_facility_id(
    data, fac_col_str, type_col_str, id_col_str, fix_facility_id_vector, fix_to
  )
  data <- correct_by_facility_name(
    by_id$data, fac_col_str, type_col_str, fix_facility_type_vector, fix_to,
    dry_run
  )
  data <- correct_by_facility_regex(
    data, fac_col_str, type_col_str, fix_facility_type_regex,
    already_corrected = c(by_id$names, fix_facility_type_vector), fix_to
  )

  # dry_run: return preview tibble without filtering ----
  if (dry_run) {
    return(
      preview_type_corrections(
        data, fac_col_str, type_col_str, id_col_str, use_facility_id,
        keep_types
      )
    )
  }

  # Name the type column as the input spelled it in messages ----
  type_col_label <- unname(name_map)[match(type_col_str, names(name_map))]

  # Filter to keep_types, reporting what was dropped ----
  inform_dropped_types(
    data, type_col_str, keep_types, verbose, type_col_label = type_col_label
  )

  result <- dplyr::filter(
    data,
    .data[[type_col_str]] %in% keep_types
  ) |>
    dplyr::select(-.original_facility_type)

  warn_if_no_rows(
    data, result, type_col_str, keep_types, type_col_label = type_col_label
  )

  finish_names(result, clean_names, name_map)
}
