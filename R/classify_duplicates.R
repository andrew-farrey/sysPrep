
# classify_duplicates() ----
#' Classify the mechanism of duplication in an ESSENCE data pull
#'
#' Identifies and classifies the mechanism of duplication for each
#' facility x Visit_ID group containing more than one row.
#' Classification is based on which key ESSENCE fields vary within a
#' duplicate group: visit date (via C_BioSense_ID recomputation), patient
#' identifier, and/or patient class. Intended to be called before [dedupe()]
#' to inform deduplication strategy and understand the nature of data quality
#' issues in a specific pull.
#'
#' @details
#' ## Columns used
#' Required: `facility_col`, `visit_col`, `C_BioSense_ID`, `Date`,
#' `C_Unique_Patient_ID`. Optional: `C_Patient_Class` (enables
#' `patient_class_change` detection).
#'
#' ## Duplication mechanisms in ESSENCE
#' Multiple rows for the same facility x Visit_ID arise through distinct
#' mechanisms, each with different causes and implications:
#'
#' \describe{
#'   \item{`"visit_date_change"`}{`C_BioSense_ID` is computed by
#'     concatenating `C_Visit_Date`, `C_BioSense_Facility_ID` (`Hospital`),
#'     and `C_Unique_Patient_ID`. `C_Visit_Date` itself takes its date value
#'     from `C_Visit_Date_Time`. When a hospital's system updates
#'     `C_Visit_Date_Time` as providers interact with the patient, rather
#'     than fixing it at initial registration, and one such update crosses
#'     midnight, `C_Visit_Date` changes to the next calendar day, which
#'     recomputes `C_BioSense_ID` for the same `Visit_ID` and produces two
#'     rows that refer to the same encounter. This is the most widespread
#'     duplication type across NSSP sites; the affected proportion of visits
#'     is typically small, but the impact is disproportionate in small-count
#'     syndrome definitions where a few inflated counts can trigger anomaly
#'     detection alerts that do not reflect genuine changes in incidence.
#'     The duplicate arises only at facilities whose systems continue to
#'     update `C_Visit_Date_Time` after initial registration. Detected by
#'     multiple distinct `C_BioSense_ID` values and `Date` values within a
#'     group.}
#'   \item{`"pid_change"`}{`C_Unique_Patient_ID` (which maps to MRN in
#'     Kentucky) is also one of the three fields concatenated into
#'     `C_BioSense_ID`, so updating it mid-visit recomputes `C_BioSense_ID`
#'     and produces a new row, for example, when an initial local
#'     (facility- or department-specific) MRN is replaced with a
#'     community-wide or health-system-level MRN, or with a different local
#'     MRN. Detected by multiple distinct `C_Unique_Patient_ID` values
#'     within a group. Not all ESSENCE sites use MRN as
#'     `C_Unique_Patient_ID`.}
#'   \item{`"patient_class_change"`}{Under normal HL7 processing, patient
#'     class transitions are handled without generating duplicate rows:
#'     the transition is appended to `C_Patient_Class_List` and the
#'     `HasBeenE`, `HasBeenI`, `HasBeenAdmitted` flags are updated in place.
#'     This type is detected when the same `Visit_ID` appears with multiple
#'     distinct `c_patient_class` values, which may indicate a feed
#'     configuration issue or a concurrent triggering event. Requires
#'     `c_patient_class` to be present in the data; available via the
#'     standard ESSENCE API. See also [link_encounters()] for burden
#'     estimation from multi-class episodes.}
#'   \item{`"type_unknown"`}{Multiple rows exist but all assessed fields
#'     are identical across rows. The differentiating field was not included
#'     in the pull. Consider adding `C_BioSense_ID`, `Date`, and
#'     `C_Unique_Patient_ID` to your ESSENCE pull fields.}
#'   \item{Compound types}{Any combination of the above joined with `+`,
#'     e.g., `"visit_date_change+pid_change"`. Indicates multiple mechanisms
#'     acting simultaneously on the same visit. All possible combinations
#'     of the three primary mechanisms are detected and classified.}
#' }
#'
#' ## Required columns
#' All classification types require `facility_col`, `visit_col`,
#' `C_BioSense_ID` (or `c_biosense_id` / `c_bio_sense_id`), `Date` (or
#' `date`), and
#' `C_Unique_Patient_ID` (or `c_unique_patient_id`). The function aborts
#' with an informative message if any are absent.
#'
#' ## Missing key values are never classified as duplicates
#' A row with a missing `facility_col` or `visit_col` value has an unknown
#' identity, not one confirmed to match every other row with a missing
#' value. `classify_duplicates()` never groups two such rows together,
#' even when they share the same facility and both have a missing
#' `visit_col`: each gets its own `$visit_groups` row with `dup_type =
#' "no_duplication"`. This differs from grouping directly on the raw
#' columns (e.g. `dplyr::group_by()`), which follows SQL's `GROUP BY`
#' convention of treating every `NA` as equal to every other `NA` and
#' would otherwise classify genuinely distinct visits as duplicated just
#' because their identifier happened to be missing. `rlang::inform()`
#' (gated by `verbose`) reports how many rows were affected whenever this
#' occurs. See [dedupe()]'s "Missing key values" section for the same
#' behavior there.
#'
#' ## Optional patient class detection
#' Detection of `patient_class_change` requires `c_patient_class` in the
#' data, available via the standard ESSENCE API as a pull field. When absent,
#' patient class change detection is skipped and all other types remain
#' functional.
#'
#' ## Linked vs. unlinked input
#' `classify_duplicates()` can be run on a raw (unlinked) ESSENCE pull, or on
#' the long-format output of [link_encounters()]: it only requires
#' `facility_col`/`visit_col` and the identifying columns above, regardless
#' of which record structure they come from. Either way, `patient_class_change`
#' (and every other type here) is detected from rows that still exist
#' side-by-side with a shared `facility_col` x `visit_col` key: it looks for
#' more than one distinct value of a field (here, `c_patient_class`) across
#' those rows, not from any single row. Once those rows have already been
#' collapsed into one, e.g. by [dedupe()], or by [link_encounters()] with
#' `return_format = "collapsed"`, there is only one row left per key, so
#' `n_rows == 1` and nothing is classified as a duplicate at all, regardless
#' of what mechanism originally produced the now-merged rows. Classify before
#' collapsing if you want to see which mechanism was responsible.
#'
#' ## Return formats
#' \describe{
#'   \item{`"list"` (default)}{A named list of class `essence_dup_classified`
#'     with `$duplicate_ids`, `$visit_groups`, `$by_facility`, and
#'     `$overall`. `$duplicate_ids` is a tibble of facility x visit_col
#'     pairs with more than one row, consistent with
#'     [summarize_duplicates()]`$duplicate_ids`.}
#'   \item{`"tibble"`}{The visit-group level summary tibble only: one row
#'     per facility x visit_col with `dup_type` and supporting `n_*`
#'     metrics. Suitable for joining back to original data or piping into
#'     further analysis.}
#' }
#'
#' @inheritParams dedupe
#' @param return_format Character string. One of `"list"` (default) or
#'   `"tibble"`. See Details.
#' @param verbose Logical. If `FALSE`, suppresses informational messages
#'   (`rlang::inform()`); warnings and errors are always shown regardless.
#'
#' @return When `return_format = "list"`, a named list of class
#'   `essence_dup_classified` with:
#'   \describe{
#'     \item{`$duplicate_ids`}{Tibble of facility x visit_col pairs with
#'       more than one row.}
#'     \item{`$visit_groups`}{Tibble with one row per facility x visit_col
#'       containing `n_rows`, `n_biosense_ids`, `n_dates`, `n_pid`,
#'       `n_patient_classes` (if available), and `dup_type`.}
#'     \item{`$by_facility`}{Wide-format count of each `dup_type` per
#'       facility, sorted by total duplicated Visit IDs descending.}
#'     \item{`$overall`}{Dataset-level counts and proportions by `dup_type`
#'       via [janitor::tabyl()].}
#'   }
#'
#'   The `format()` method returns the printed report as a character vector;
#'   the `print()` method writes it to standard output with [writeLines()] and
#'   returns `x` invisibly.
#'   When `return_format = "tibble"`, the `$visit_groups` tibble only.
#'
#' @examples
#' # Default list return
#' essence_raw |> classify_duplicates()
#'
#' # Tibble return for piping
#' essence_raw |>
#'   classify_duplicates(return_format = "tibble") |>
#'   dplyr::filter(dup_type == "visit_date_change")
#'
#' # Join classifications back to raw data for row-level inspection
#' # (clean first so join keys match the snake_case output of
#' # classify_duplicates; essence_raw has Hospital, so that's the
#' # preferred join key here, not hospital_name; see Details in ?dedupe)
#' essence_raw |>
#'   janitor::clean_names() |>
#'   dplyr::left_join(
#'     classify_duplicates(essence_raw, return_format = "tibble"),
#'     by = c("hospital", "visit_id")
#'   )
#'
#' @seealso [summarize_duplicates()] for counts without mechanism detail;
#'   [dedupe()] to remove duplicates after review.
#' @export
classify_duplicates <- function(data,
                                facility_col  = NULL,
                                visit_col     = Visit_ID,
                                return_format = c("list", "tibble"),
                                verbose       = TRUE) {

  check_data_frame(data)
  check_flag(verbose)

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

  return_format <- rlang::arg_match(return_format)

  # Normalize names upfront and resolve the columns ----
  data_clean    <- clean_names_safe(data)
  fac_col_str   <- resolve_facility_col_str(
    data_clean, facility_col_sym, facility_col_missing
  )
  visit_col_str <- resolve_col_str(data_clean, rlang::ensym(visit_col))

  cols          <- resolve_classification_cols(data_clean)
  patient_class <- resolve_patient_class_col(data_clean, verbose)
  has_patient_class <- patient_class$has_patient_class

  # Build the visit-group summary and classify each group ----
  visit_groups <- data_clean |>
    summarize_visit_groups(
      fac_col_str, visit_col_str, cols, patient_class, verbose
    ) |>
    classify_dup_type(has_patient_class)

  # Return tibble early if requested ----
  if (return_format == "tibble") return(visit_groups)

  # Rows classified as an actual duplicate, shared by all three components
  # below ----
  dup_rows <- dplyr::filter(visit_groups, dup_type != "no_duplication")

  # Assemble and return list ----
  structure(
    list(
      duplicate_ids = dplyr::select(
        dup_rows,
        dplyr::all_of(c(fac_col_str, visit_col_str))
      ),
      visit_groups  = visit_groups,
      by_facility   = summarize_dup_by_facility(dup_rows, fac_col_str),
      overall       = summarize_dup_overall(dup_rows)
    ),
    class             = "essence_dup_classified",
    facility_col      = fac_col_str,
    visit_col         = visit_col_str,
    has_patient_class = has_patient_class
  )
}

# format.essence_dup_classified() / print.essence_dup_classified() ----
# See the note above format.essence_dup_summary(): print() writes a single
# formatted character vector so all output goes to stdout.
#' @rdname classify_duplicates
#' @param x An `essence_dup_classified` object, as returned by
#'   `classify_duplicates()` with `return_format = "list"`.
#' @param ... Passed on to `format()`; currently unused.
#' @export
format.essence_dup_classified <- function(x, ...) {
  has_pc <- attr(x, "has_patient_class")

  cli::cli_format_method({
    cli::cli_h1("ESSENCE Duplicate Classification")

    if (!has_pc) {
      cli::cli_alert_info(
        paste0(
          "Patient class change detection was unavailable ",
          "(`c_patient_class` absent)."
        )
      )
    }

    cli::cli_h2("Overall")
    cli::cli_verbatim(print_lines(x$overall))

    cli::cli_h2("By Facility")
    cli::cli_verbatim(print_lines(x$by_facility, n = Inf))

    cli_duplicate_ids_footer(x)

    cli::cli_h2("Visit Groups")
    cli::cli_text(
      "{nrow(x$visit_groups)} facility \u00d7 Visit_ID groups total. ",
      "Access full detail via $visit_groups."
    )
  })
}

#' @rdname classify_duplicates
#' @export
print.essence_dup_classified <- function(x, ...) {
  # Same lines format() builds, written to stdout; kept as its own method
  # (not a shared helper) so each class owns its print() behavior.
  lines <- format(x, ...)
  writeLines(lines)
  invisible(x)
}
