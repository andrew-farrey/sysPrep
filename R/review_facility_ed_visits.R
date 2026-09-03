
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
#' @param data A data frame of ESSENCE visit-level records, typically after
#'   [dedupe()] and optionally [filter_care_setting()].
#' @param facility_col <[`tidy-select`][dplyr::dplyr_tidy_select]> Unquoted
#'   column name identifying the facility. Defaults to `HospitalName`.
#' @param facility_type_col <[`tidy-select`][dplyr::dplyr_tidy_select]>
#'   Unquoted column name identifying the facility type. Defaults to
#'   `FacilityType`.
#' @param date_col <[`tidy-select`][dplyr::dplyr_tidy_select]> Optional.
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
#' @param clean_names Logical. If `TRUE` (default), applies
#'   [janitor::clean_names()] to standardize column names on output.
#' @param verbose Logical. If `FALSE`, suppresses informational messages
#'   (`rlang::inform()`); warnings and errors are always shown regardless.
#'
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
#' @seealso [filter_care_setting()] for removing non-ED facilities before review.
#' @export
review_facility_ed_visits <- function(data,
                                      facility_col      = HospitalName,
                                      facility_type_col = FacilityType,
                                      date_col          = NULL,
                                      method            = c("percentile", "iqr", "both"),
                                      percentile_low    = 0.05,
                                      percentile_high   = 0.95,
                                      iqr_multiplier    = 1.5,
                                      group_by_type     = FALSE,
                                      return_format     = c("outliers_only", "all"),
                                      clean_names       = TRUE,
                                      verbose           = TRUE) {

  method        <- match.arg(method)
  return_format <- match.arg(return_format)

  # Normalize names ----
  data <- clean_names_safe(data)

  fac_col_str  <- resolve_col_str(data, rlang::ensym(facility_col))
  type_col_str <- resolve_col_str(data, rlang::ensym(facility_type_col))

  # Resolve optional date column ----
  date_col_quo <- rlang::enquo(date_col)
  use_time_norm <- !rlang::quo_is_null(date_col_quo)
  date_col_str  <- NULL

  if (use_time_norm) {
    date_col_str <- rlang::as_name(date_col_quo)
    date_col_sym <- resolve_col_optional(data, rlang::sym(date_col_str))
    if (is.null(date_col_sym)) {
      rlang::warn(
        paste0(
          "Date column '", date_col_str, "' not found in data. ",
          "Falling back to raw visit counts."
        )
      )
      use_time_norm <- FALSE
    } else {
      date_col_str <- rlang::as_string(date_col_sym)
    }
  }

  # Inform about key behavioral defaults ----
  inform_if(
    verbose,
    paste0(
      "Low-count facilities are expected for narrow syndrome definitions, ",
      "particularly at small rural hospitals. Low outliers do not necessarily ",
      "indicate a data quality problem. For most reliable outlier detection, ",
      "use denominator (all-cause ED visit) data."
    )
  )

  if (!use_time_norm) {
    inform_if(
      verbose,
      paste0(
        "No `date_col` supplied; using raw visit counts. ",
        "Supply a date column (e.g., `date_col = Date`) to normalize to ",
        "visits per day for dropout detection or cross-pull comparisons."
      )
    )
  }

  if (!group_by_type && dplyr::n_distinct(data[[type_col_str]]) > 1L) {
    inform_if(
      verbose,
      paste0(
        "Outlier detection across all facility types combined. ",
        "Use `group_by_type = TRUE` to detect outliers within each ",
        "`FacilityType` separately."
      )
    )
  }

  # Compute facility-level visit counts ----
  group_vars <- c(fac_col_str, type_col_str)

  facility_counts <- data |>
    dplyr::group_by(dplyr::across(dplyr::all_of(group_vars))) |>
    dplyr::summarise(
      n_visits = dplyr::n(),
      n_days   = if (use_time_norm) {
        dplyr::n_distinct(.data[[date_col_str]], na.rm = TRUE)
      } else {
        NA_integer_
      },
      .groups = "drop"
    )

  if (use_time_norm) {
    facility_counts <- dplyr::mutate(
      facility_counts,
      visits_per_day = n_visits / n_days
    )
  }

  detect_col <- if (use_time_norm) "visits_per_day" else "n_visits"

  # Compute outlier thresholds (optionally within FacilityType groups) ----
  threshold_groups <- if (group_by_type) {
    dplyr::group_by(facility_counts, .data[[type_col_str]])
  } else {
    facility_counts
  }

  # Only compute the quantiles the chosen `method` actually uses, e.g. the
  # IQR quantiles are wasted work (recomputed per group) under the default
  # method = "percentile", and vice versa for method = "iqr".
  needs_pct <- method != "iqr"
  needs_iqr <- method != "percentile"

  facility_counts <- threshold_groups |>
    dplyr::mutate(
      .pct_low  = if (needs_pct) {
        quantile(.data[[detect_col]], percentile_low, na.rm = TRUE)
      } else {
        NA_real_
      },
      .pct_high = if (needs_pct) {
        quantile(.data[[detect_col]], percentile_high, na.rm = TRUE)
      } else {
        NA_real_
      },
      .q1       = if (needs_iqr) {
        quantile(.data[[detect_col]], 0.25, na.rm = TRUE)
      } else {
        NA_real_
      },
      .q3       = if (needs_iqr) {
        quantile(.data[[detect_col]], 0.75, na.rm = TRUE)
      } else {
        NA_real_
      },
      .iqr      = .q3 - .q1,
      .iqr_low  = if (needs_iqr) .q1 - iqr_multiplier * .iqr else NA_real_,
      .iqr_high = if (needs_iqr) .q3 + iqr_multiplier * .iqr else NA_real_
    ) |>
    dplyr::ungroup()

  # Apply outlier flags ----
  # `method` is a single scalar value for the whole call, so the comparison
  # is chosen once with if/else rather than dplyr::case_when(); case_when()
  # with a scalar LHS and vector RHS is deprecated as of dplyr 1.2.0.
  facility_counts <- facility_counts |>
    dplyr::mutate(
      .outlier_low = if (method == "percentile") {
        .data[[detect_col]] < .data[[".pct_low"]]
      } else if (method == "iqr") {
        .data[[detect_col]] < .data[[".iqr_low"]]
      } else {
        .data[[detect_col]] < .data[[".pct_low"]] |
          .data[[detect_col]] < .data[[".iqr_low"]]
      },
      .outlier_high = if (method == "percentile") {
        .data[[detect_col]] > .data[[".pct_high"]]
      } else if (method == "iqr") {
        .data[[detect_col]] > .data[[".iqr_high"]]
      } else {
        .data[[detect_col]] > .data[[".pct_high"]] |
          .data[[detect_col]] > .data[[".iqr_high"]]
      },
      .outlier_flag = .outlier_low | .outlier_high,
      .outlier_direction = dplyr::case_when(
        .outlier_low  & .outlier_high ~ "both",
        .outlier_low                  ~ "low",
        .outlier_high                 ~ "high",
        TRUE                          ~ NA_character_
      ),
      .outlier_method = dplyr::if_else(
        .outlier_flag,
        method,
        NA_character_
      )
    ) |>
    dplyr::select(
      -dplyr::starts_with(".pct_"),
      -dplyr::starts_with(".q"),
      -dplyr::starts_with(".iqr")
    )

  if (!use_time_norm) {
    facility_counts <- dplyr::select(facility_counts, -n_days)
  }

  # Return format ----
  result <- if (return_format == "outliers_only") {
    facility_counts |>
      dplyr::filter(.outlier_flag) |>
      dplyr::arrange(dplyr::desc(.outlier_direction), .data[[detect_col]])
  } else {
    dplyr::arrange(
      facility_counts,
      dplyr::desc(.outlier_flag),
      .data[[detect_col]]
    )
  }

  n_flagged <- sum(facility_counts$.outlier_flag, na.rm = TRUE)
  n_total   <- nrow(facility_counts)

  if (n_total == 0L) {
    inform_if(verbose, "No facilities in data after processing. Returning empty result.")
  } else {
    inform_if(
      verbose,
      paste0(
        n_flagged, " of ", n_total, " facilities flagged as outliers (",
        round(n_flagged / n_total * 100, 1), "%) ",
        "using method = '", method, "'",
        if (group_by_type) " within FacilityType groups" else "", "."
      )
    )
  }

  if (clean_names) clean_names_safe(result) else result
}
