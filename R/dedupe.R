
# dedupe() ----
#' Remove duplicate records from an ESSENCE data pull
#'
#' Retains one row per unique facility x visit identifier combination.
#' ESSENCE data frequently contains multiple rows for the same visit due to
#' query overlap, multi-facility pulls, or late-arriving record updates.
#' This function formalizes the deduplication step prior to case counting,
#' cluster detection, or geographic attribution.
#'
#' @details
#' ## Why deduplication is necessary
#' The ESSENCE API may return multiple rows for a single facility x Visit_ID
#' combination due to several mechanisms: standard data feed retransmissions,
#' midnight-crossing visits that trigger recomputation of C_BioSense_ID,
#' patient identifier corrections mid-visit, and patient class transitions.
#' Without deduplication, visit counts, rates, and cluster detection outputs
#' are inflated. See [classify_duplicates()] to understand the mechanism of
#' duplication in a specific pull before deduplicating.
#'
#' ## Deduplication key
#' The deduplication key is always `facility_col x visit_col`. Visit_ID is
#' unique within a facility in ESSENCE -- the same Visit_ID at two different
#' facilities represents two distinct encounters and is not collapsed.
#'
#' ## keep strategies
#' \describe{
#'   \item{`"first"` (default)}{Retains the first row as received. When
#'     `order_by` is supplied, retains the earliest record by that column.
#'     Fastest and most transparent.}
#'   \item{`"last"`}{Retains the final row. When `order_by` is supplied,
#'     retains the most recently received record -- appropriate when ESSENCE
#'     records are updated chronologically and later rows reflect corrected
#'     information. Use `Arrived_Date_Time` as `order_by` to retain the most
#'     recently transmitted version of each record.}
#'   \item{`"most_complete"`}{Retains the row with the fewest `NA` values
#'     across all columns. Useful when records vary in completeness due to
#'     late-arriving lab or disposition fields. `order_by` is ignored and a
#'     warning is issued if supplied.}
#' }
#'
#' ## Column name flexibility
#' All `_col` arguments accept both raw ESSENCE column names (e.g.,
#' `HospitalName`) and post-[janitor::clean_names()] equivalents (e.g.,
#' `hospital_name`). The function normalizes both the supplied name and the
#' data's column names to snake_case for matching, then returns results using
#' the actual column names present in the data.
#'
#' @param data A data frame of raw ESSENCE visit-level records.
#' @param facility_col <[`tidy-select`][dplyr::dplyr_tidy_select]> Unquoted
#'   column name identifying the facility. Defaults to `HospitalName`.
#'   Use `Hospital` when working with `C_BioSense_Facility_ID`-based pulls.
#'   Accepts both raw ESSENCE names and post-[janitor::clean_names()]
#'   equivalents.
#' @param visit_col <[`tidy-select`][dplyr::dplyr_tidy_select]> Unquoted
#'   column name identifying the visit. Defaults to `Visit_ID`. Common
#'   alternatives include `MedicalRecordNumber`, `MRN`, `VisitNumber`, and
#'   `C_Unique_Patient_ID`. Accepts both raw ESSENCE names and
#'   post-[janitor::clean_names()] equivalents.
#' @param order_by <[`tidy-select`][dplyr::dplyr_tidy_select]> Optional.
#'   Unquoted column name to sort by within each facility x visit group
#'   before applying `keep`. Ignored when `keep = "most_complete"` (a warning
#'   is issued). Use `Arrived_Date_Time` to retain the most recently
#'   transmitted record (`keep = "last"`) or the earliest (`keep = "first"`).
#'   Other useful options: `C_Visit_Date`, `C_Visit_Date_Time`, `Date`.
#'   Defaults to `NULL` (row order as received).
#' @param keep Character string. Which row to retain per group. One of
#'   `"first"` (default), `"last"`, or `"most_complete"`. See Details.
#' @param clean_names Logical. If `TRUE` (default), applies
#'   [janitor::clean_names()] to standardize column names to snake_case
#'   after deduplication.
#'
#' @return A deduplicated data frame with one row per `facility_col` x
#'   `visit_col` combination.
#'
#' @examples
#' # Default: one row per HospitalName x Visit_ID, first row as received
#' essence_raw |> dedupe()
#'
#' # Retain earliest record by visit date
#' essence_raw |> dedupe(order_by = Date, keep = "first")
#'
#' # Retain most recently transmitted record (best for rolling pulls)
#' essence_raw |> dedupe(order_by = Arrived_Date_Time, keep = "last")
#'
#' # Retain most complete record per visit
#' essence_raw |> dedupe(keep = "most_complete")
#'
#' # Use numeric facility ID instead of name
#' essence_raw |> dedupe(facility_col = Hospital)
#'
#' # Deduplicate by patient identifier (MRN-equivalent in ESSENCE)
#' essence_raw |> dedupe(visit_col = C_Unique_Patient_ID)
#'
#' # Works with post-clean_names() column names too
#' essence_raw |>
#'   janitor::clean_names() |>
#'   dedupe(order_by = arrived_date_time, keep = "last")
#'
#' # Full recommended pre-processing pipeline
#' essence_raw |>
#'   dedupe(order_by = Arrived_Date_Time, keep = "last") |>
#'   filter_care_setting() |>
#'   assign_treating_geography()
#'
#' @seealso [summarize_duplicates()] to count duplicates before deduplication;
#'   [classify_duplicates()] to understand duplication mechanisms.
#' @export
dedupe <- function(data,
                   facility_col = HospitalName,
                   visit_col    = Visit_ID,
                   order_by     = NULL,
                   keep         = "first",
                   clean_names  = TRUE) {

  keep <- match.arg(keep, choices = c("first", "last", "most_complete"))

  # Normalize names upfront ----
  original_names <- names(data)
  data           <- clean_names_safe(data)
  facility_col   <- resolve_col(data, rlang::ensym(facility_col))
  visit_col      <- resolve_col(data, rlang::ensym(visit_col))

  # Resolve optional order_by ----
  order_by_quo     <- rlang::enquo(order_by)
  has_order_by     <- !rlang::quo_is_null(order_by_quo)

  if (has_order_by) {
    order_by_str <- rlang::as_name(order_by_quo)
    order_col    <- resolve_col(data, rlang::sym(order_by_str))

    if (keep == "most_complete") {
      rlang::warn(
        paste0(
          "`order_by` is ignored when `keep = 'most_complete'`. ",
          "Row selection is based on column completeness, not sort order."
        )
      )
    } else {
      data <- dplyr::arrange(
        data,
        !!facility_col,
        !!visit_col,
        !!order_col
      )
    }
  }

  # Group and apply keep strategy ----
  grouped <- dplyr::group_by(data, !!facility_col, !!visit_col)

  deduped <- switch(
    keep,
    "first" = {
      dplyr::slice(grouped, 1L)
    },
    "last" = {
      dplyr::slice(grouped, dplyr::n())
    },
    "most_complete" = {
      grouped |>
        dplyr::mutate(
          .n_complete = rowSums(!is.na(dplyr::pick(dplyr::everything())))
        ) |>
        dplyr::slice_max(.n_complete, n = 1L, with_ties = FALSE) |>
        dplyr::select(-.n_complete)
    }
  )

  deduped <- dplyr::ungroup(deduped)

  if (clean_names) {
    clean_names_safe(deduped)
  } else {
    stats::setNames(deduped, original_names)
  }
}
