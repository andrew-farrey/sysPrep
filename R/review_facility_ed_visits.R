
# review_facility_ed_visits() ----
#' Review facility ED visit counts for data quality assessment
#'
#' Computes visit counts per facility and flags statistical outliers:
#' facilities with disproportionately low or high visit volumes relative to
#' the pull as a whole. Intended as an ongoing data quality monitoring tool
#' for production surveillance pipelines, where unexpectedly low counts may
#' indicate feed outages, facility onboarding issues, or non-ED providers,
#' and unexpectedly high counts may indicate feed duplication or query
#' misconfiguration.
#'
#' @details
#' ## Interpreting results
#' Low-count outliers are expected and normal for narrow syndrome definitions,
#' particularly at small rural hospitals. A rural ED with two opioid overdose
#' visits in a given month is not a data quality problem; it may reflect
#' true low incidence. This function is best used on **denominator data**
#' (all-cause ED visits) where facility volumes are stable and comparable.
#' When applied to narrow case definitions, some ED facilities will routinely
#' appear as low outliers. The function is intended to make routine QA
#' assessment easier, not to drive exclusion decisions. Always review
#' flagged facilities in context.
#'
#' ## Outlier methods
#' \describe{
#'   \item{`"percentile"` (default)}{Flags facilities below
#'     `percentile_low` and above `percentile_high` of the visit count
#'     distribution. Default thresholds of 5th and 95th percentile are
#'     interpretable and robust to skewed count distributions.}
#'   \item{`"iqr"`}{Flags facilities below `Q1 - iqr_multiplier * IQR` and
#'     above `Q3 + iqr_multiplier * IQR`. Tukey fences with the default
#'     multiplier of 1.5 are sensitive to data dropouts: a facility that
#'     abruptly stops sending visits during a pull window will fall well
#'     below the lower fence. Increase `iqr_multiplier` to reduce
#'     sensitivity.}
#'   \item{`"both"`}{Applies both methods independently. A facility is
#'     flagged if it meets either criterion. `.outlier_method` indicates
#'     which method triggered.}
#' }
#'
#' ## Time normalization
#' When `date_col` is supplied, visits per day is computed and outlier
#' detection is applied to the normalized rate rather than raw counts.
#' This makes pulls of different durations comparable and improves
#' sensitivity to within-pull data dropouts (e.g., a facility that stops
#' sending data mid-month).
#'
#' ## Grouped detection
#' When `group_by_type = TRUE`, outlier thresholds are computed separately
#' within each `FacilityType`. This prevents large academic medical centers
#' from inflating thresholds that mask low counts at smaller facilities.
#'
#' @inheritParams dedupe
#' @inheritParams filter_care_setting
#' @inheritParams classify_duplicates
#' @param data A data frame of ESSENCE visit-level records, typically after
#'   [dedupe()] and optionally [filter_care_setting()].
#' @param date_col Optional.
#'   Unquoted column name for the visit date. When supplied, outlier
#'   detection uses visits per day rather than raw counts. Accepts `Date`,
#'   `C_Visit_Date`, or post-[janitor::clean_names()] equivalents.
#'   Defaults to `NULL`.
#' @param method Character string. Outlier detection method. One of
#'   `"percentile"` (default), `"iqr"`, or `"both"`. See Details.
#' @param percentile_low Numeric. Lower percentile threshold for
#'   `method = "percentile"` or `"both"`. Defaults to `0.05`.
#' @param percentile_high Numeric. Upper percentile threshold for
#'   `method = "percentile"` or `"both"`. Defaults to `0.95`.
#' @param iqr_multiplier Numeric. Fence multiplier for `method = "iqr"` or
#'   `"both"`. Defaults to `1.5` (Tukey standard). Increase to reduce
#'   sensitivity; decrease to increase sensitivity to dropouts.
#' @param group_by_type Logical. If `TRUE`, outlier thresholds are computed
#'   separately within each `FacilityType` group. Defaults to `FALSE`.
#' @param return_format Character string. One of `"outliers_only"` (default)
#'   or `"all"`. `"outliers_only"` returns only flagged facilities.
#'   `"all"` returns all facilities with outlier flag columns appended.
#' @return A tibble with one row per facility containing facility identifier,
#'   facility type, `n_visits`, optionally `visits_per_day` and `n_days`,
#'   and outlier flag columns `.outlier_low`, `.outlier_high`,
#'   `.outlier_flag`, `.outlier_direction`, and `.outlier_method`.
#'
#' @examples
#' # Default: percentile method, outliers only
#' essence_clean |> review_facility_ed_visits()
#'
#' # All facilities with flags
#' essence_clean |> review_facility_ed_visits(return_format = "all")
#'
#' # IQR method with time normalization for dropout detection
#' essence_clean |>
#'   review_facility_ed_visits(
#'     method   = "iqr",
#'     date_col = Date
#'   )
#'
#' # Both methods, grouped by facility type
#' essence_clean |>
#'   review_facility_ed_visits(
#'     method        = "both",
#'     group_by_type = TRUE,
#'     return_format = "all"
#'   )
#'
#' @seealso [filter_care_setting()] for removing non-ED facilities before
#'   review.
#' @export
review_facility_ed_visits <- function(data,
                                      facility_col = NULL,
                                      facility_type_col = FacilityType,
                                      date_col = NULL,
                                      method = c("percentile", "iqr", "both"),
                                      percentile_low = 0.05,
                                      percentile_high = 0.95,
                                      iqr_multiplier = 1.5,
                                      group_by_type = FALSE,
                                      return_format = c("outliers_only", "all"),
                                      clean_names = TRUE,
                                      verbose = TRUE) {

  check_data_frame(data)
  check_number(percentile_low, lower = 0, upper = 1)
  check_number(percentile_high, lower = 0, upper = 1)
  check_number(iqr_multiplier, lower = 0)
  check_flag(group_by_type)
  check_flag(clean_names)
  check_flag(verbose)
  check_percentile_order(percentile_low, percentile_high)

  # facility_col defaults to NULL (rather than a fixed column) so the
  # printed signature/Usage line doesn't misrepresent the smart default
  # below as a plain HospitalName default ----
  facility_col_quo     <- rlang::enquo(facility_col)
  facility_col_missing <- rlang::quo_is_null(facility_col_quo)
  facility_col_sym     <- if (facility_col_missing) {
    NULL
  } else {
    rlang::sym(rlang::as_name(facility_col_quo))
  }

  method        <- rlang::arg_match(method)
  return_format <- rlang::arg_match(return_format)

  # Normalize names and resolve the columns ----
  data <- clean_names_safe(data)

  fac_col_str  <- resolve_facility_col_str(
    data, facility_col_sym, facility_col_missing
  )
  type_col_str <- resolve_col_str(data, rlang::ensym(facility_type_col))

  date_info  <- resolve_review_date_col(data, rlang::enquo(date_col))
  use_time_norm <- date_info$use_time_norm

  inform_review_defaults(
    data, type_col_str, use_time_norm, group_by_type, verbose
  )

  # Count visits, set thresholds, flag outliers ----
  facility_counts <- count_facility_visits(
    data, fac_col_str, type_col_str, use_time_norm, date_info$date_col_str
  )
  detect_col <- if (use_time_norm) "visits_per_day" else "n_visits"

  facility_counts <- facility_counts |>
    add_outlier_thresholds(
      detect_col, type_col_str, group_by_type, method,
      percentile_low, percentile_high, iqr_multiplier
    ) |>
    flag_outliers(detect_col, method)

  if (!use_time_norm) {
    facility_counts <- dplyr::select(facility_counts, -n_days)
  }

  result <- arrange_review_result(facility_counts, detect_col, return_format)

  inform_review_summary(facility_counts, method, group_by_type, verbose)

  if (clean_names) clean_names_safe(result) else result
}
