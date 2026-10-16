
# summarize_duplicates() ----
#' Summarize duplicate records in an ESSENCE data pull
#'
#' Identifies visits with more than one row per facility x Visit_ID combination
#' and returns a named list with three components: a tibble of duplicated
#' facility x Visit_ID pairs for filtering or review, a facility-level summary
#' arranged from most to least duplicated, and an overall count and proportion
#' of affected visits. Intended to be called on raw or minimally processed
#' ESSENCE data before [dedupe()].
#'
#' @details
#' ## Duplicate definition
#' A duplicate is any `facility_col x visit_col` group containing more than
#' one row. The same `Visit_ID` appearing at two different facilities does
#' not constitute a duplicate: `Visit_ID` is unique only within a facility.
#' Duplicate detection is therefore always scoped to `facility x visit_col`.
#'
#' ## Missing key values are never counted as duplicates
#' A row with a missing `facility_col` or `visit_col` value has an unknown
#' identity, not one confirmed to match every other row with a missing
#' value. `summarize_duplicates()` never groups two such rows together,
#' even when they share the same facility and both have a missing
#' `visit_col`: each counts as its own distinct visit in `$overall` and
#' `$by_facility`. This differs from grouping directly on the raw columns
#' (e.g. `dplyr::group_by()`), which follows SQL's `GROUP BY` convention
#' of treating every `NA` as equal to every other `NA` and would otherwise
#' report genuinely distinct visits as duplicated just because their
#' identifier happened to be missing. `rlang::inform()` reports how many
#' rows were affected whenever this occurs. See [dedupe()]'s "Missing key
#' values" section for the same behavior there.
#'
#' ## Return value components
#' \describe{
#'   \item{`$duplicate_ids`}{A tibble of `facility_col x visit_col` pairs
#'     where more than one row exists. Use for targeted review, semi-joins,
#'     or anti-joins prior to deduplication.}
#'   \item{`$by_facility`}{A tibble of facility-level duplicate metrics
#'     arranged from most to least duplicated by `n_excess_rows`.}
#'   \item{`$overall`}{A single-row tibble with dataset-level counts and
#'     proportions.}
#' }
#'
#' @inheritParams dedupe
#' @return A named list of class `essence_dup_summary` with components
#'   `$duplicate_ids`, `$by_facility`, and `$overall`.
#'
#'   The `format()` method returns the printed report as a character vector;
#'   the `print()` method writes it to standard output with [writeLines()] and
#'   returns `x` invisibly.
#'
#' @examples
#' # Basic usage before deduplication
#' essence_raw |> summarize_duplicates()
#'
#' # Inspect components
#' dups <- summarize_duplicates(essence_raw)
#' dups$overall
#' dups$by_facility
#' dups$duplicate_ids
#'
#' # Filter raw data to duplicated visits for manual review
#' # (clean first so join keys match snake_case output of $duplicate_ids;
#' # essence_raw has Hospital, so that's the preferred join key here,
#' # not hospital_name; see Details in ?dedupe)
#' essence_raw |>
#'   janitor::clean_names() |>
#'   dplyr::semi_join(
#'     summarize_duplicates(essence_raw)$duplicate_ids,
#'     by = c("hospital", "visit_id")
#'   )
#'
#' @seealso [classify_duplicates()] for mechanism-level classification;
#'   [dedupe()] to remove duplicates after review.
#' @export
summarize_duplicates <- function(data,
                                 facility_col = NULL,
                                 visit_col    = Visit_ID) {

  check_data_frame(data)

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

  # Resolve column names ----
  data_clean    <- clean_names_safe(data)
  fac_col_str   <- resolve_facility_col_str(
    data_clean, facility_col_sym, facility_col_missing
  )
  visit_col_str <- resolve_col_str(data_clean, rlang::ensym(visit_col))

  # Identify duplicate groups (facility x visit_col with n > 1) ----
  groups       <- count_visit_row_groups(data_clean, fac_col_str, visit_col_str)
  data_clean   <- groups$data
  group_counts <- groups$counts
  dup_groups   <- dplyr::filter(group_counts, n_rows > 1L)

  # Assemble and return ----
  structure(
    list(
      duplicate_ids = dplyr::select(
        dup_groups,
        dplyr::all_of(c(fac_col_str, visit_col_str))
      ),
      by_facility   = dup_summary_by_facility(
        data_clean, fac_col_str, dup_groups$.group_id
      ),
      overall       = dup_summary_overall(
        data_clean, group_counts, dup_groups
      )
    ),
    class        = "essence_dup_summary",
    facility_col = fac_col_str,
    visit_col    = visit_col_str
  )
}

# format.essence_dup_summary() / print.essence_dup_summary() ----
# Rendering is built as a character vector (cli::cli_format_method()) and
# print() just writes it with writeLines(), so the whole summary goes to
# stdout as one block:
# capture.output(), sink(), and knitr all see it, and it never splits across
# the message and output streams the way direct cli_*() calls would.
#' @rdname summarize_duplicates
#' @param x An `essence_dup_summary` object, as returned by
#'   `summarize_duplicates()`.
#' @param ... Passed on to `format()`; currently unused.
#' @export
format.essence_dup_summary <- function(x, ...) {
  cli::cli_format_method({
    cli::cli_h1("ESSENCE Duplicate Summary")

    cli::cli_h2("Overall")
    cli::cli_bullets(c(
      "*" = "Total rows in pull:             {x$overall$n_total_rows}",
      "*" = paste0(
        "Unique visits (facility x ID):  ", "{x$overall$n_unique_visits}"
      ),
      "*" = paste0(
        "Duplicated Visit IDs:           ",
        "{x$overall$n_duplicated_visit_ids} ({x$overall$pct_duplicated}%)"
      ),
      "*" = "Excess rows to remove:          {x$overall$n_excess_rows}"
    ))

    if (nrow(x$by_facility) > 0L) {
      cli::cli_h2("By Facility (most duplicated first)")
      cli::cli_verbatim(print_lines(x$by_facility, n = Inf))
    }

    if (nrow(x$duplicate_ids) > 0L) {
      cli_duplicate_ids_footer(x)
    }
  })
}

#' @rdname summarize_duplicates
#' @export
print.essence_dup_summary <- function(x, ...) {
  writeLines(format(x, ...))
  invisible(x)
}
