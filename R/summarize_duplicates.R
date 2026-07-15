
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
#' not constitute a duplicate -- `Visit_ID` is unique only within a facility.
#' Duplicate detection is therefore always scoped to `facility x visit_col`.
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
#' @param data A data frame of raw ESSENCE visit-level records.
#' @param facility_col <[`tidy-select`][dplyr::dplyr_tidy_select]> Unquoted
#'   column name identifying the facility. Defaults to `HospitalName`.
#'   Accepts both raw ESSENCE names and post-[janitor::clean_names()]
#'   equivalents.
#' @param visit_col <[`tidy-select`][dplyr::dplyr_tidy_select]> Unquoted
#'   column name identifying the visit. Defaults to `Visit_ID`. Accepts
#'   both raw ESSENCE names and post-[janitor::clean_names()] equivalents.
#'
#' @return A named list of class `essence_dup_summary` with components
#'   `$duplicate_ids`, `$by_facility`, and `$overall`.
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
#' # (clean first so join keys match snake_case output of $duplicate_ids)
#' essence_raw |>
#'   janitor::clean_names() |>
#'   dplyr::semi_join(
#'     summarize_duplicates(essence_raw)$duplicate_ids,
#'     by = c("hospital_name", "visit_id")
#'   )
#'
#' @seealso [classify_duplicates()] for mechanism-level classification;
#'   [dedupe()] to remove duplicates after review.
#' @export
summarize_duplicates <- function(data,
                                 facility_col = HospitalName,
                                 visit_col    = Visit_ID) {

  # Resolve column names ----
  data_clean   <- clean_names_safe(data)
  facility_col <- resolve_col(data_clean, rlang::ensym(facility_col))
  visit_col    <- resolve_col(data_clean, rlang::ensym(visit_col))

  fac_col_str   <- rlang::as_string(facility_col)
  visit_col_str <- rlang::as_string(visit_col)

  # Identify duplicate groups (facility x visit_col with n > 1) ----
  group_counts <- data_clean |>
    dplyr::group_by(
      .data[[fac_col_str]],
      .data[[visit_col_str]]
    ) |>
    dplyr::summarise(
      n_rows  = dplyr::n(),
      .groups = "drop"
    )

  dup_groups <- dplyr::filter(group_counts, n_rows > 1L)

  # Component 1: facility x Visit_ID pairs with > 1 row ----
  duplicate_ids <- dplyr::select(
    dup_groups,
    dplyr::all_of(c(fac_col_str, visit_col_str))
  )

  # Component 2: facility-level summary ----
  n_total_visits <- dplyr::n_distinct(
    data_clean[[fac_col_str]],
    data_clean[[visit_col_str]]
  )

  # Build a lookup of duplicated facility x visit pairs for matching
  dup_pair_key <- paste(dup_groups[[fac_col_str]], dup_groups[[visit_col_str]])

  by_facility <- data_clean |>
    dplyr::mutate(
      .pair_key = paste(.data[[fac_col_str]], .data[[visit_col_str]])
    ) |>
    dplyr::group_by(.data[[fac_col_str]]) |>
    dplyr::summarise(
      n_visits               = dplyr::n_distinct(.data[[visit_col_str]]),
      n_duplicated_visit_ids = dplyr::n_distinct(
        .data[[visit_col_str]][.pair_key %in% dup_pair_key]
      ),
      n_excess_rows          = sum(.pair_key %in% dup_pair_key) -
        n_duplicated_visit_ids,
      pct_duplicated         = round(
        n_duplicated_visit_ids / n_visits * 100,
        digits = 1
      ),
      .groups = "drop"
    ) |>
    dplyr::filter(n_duplicated_visit_ids > 0L) |>
    dplyr::arrange(dplyr::desc(n_excess_rows))

  # Component 3: overall summary ----
  pct_dup <- if (n_total_visits == 0L) {
    NA_real_
  } else {
    round(nrow(dup_groups) / n_total_visits * 100, digits = 1)
  }

  overall <- tibble::tibble(
    n_total_rows           = nrow(data_clean),
    n_unique_visits        = n_total_visits,
    n_duplicated_visit_ids = nrow(dup_groups),
    n_excess_rows          = sum(dup_groups$n_rows - 1L),
    pct_duplicated         = pct_dup
  )

  # Assemble and return ----
  structure(
    list(
      duplicate_ids = duplicate_ids,
      by_facility   = by_facility,
      overall       = overall
    ),
    class        = "essence_dup_summary",
    facility_col = fac_col_str,
    visit_col    = visit_col_str
  )
}

# print.essence_dup_summary() ----
#' @export
print.essence_dup_summary <- function(x, ...) {
  cli::cli_h1("ESSENCE Duplicate Summary")

  cli::cli_h2("Overall")
  cli::cli_bullets(c(
    "*" = "Total rows in pull:             {x$overall$n_total_rows}",
    "*" = "Unique visits (facility x ID):  {x$overall$n_unique_visits}",
    "*" = "Duplicated Visit IDs:           {x$overall$n_duplicated_visit_ids} ({x$overall$pct_duplicated}%)",
    "*" = "Excess rows to remove:          {x$overall$n_excess_rows}"
  ))

  if (nrow(x$by_facility) > 0L) {
    cli::cli_h2("By Facility (most duplicated first)")
    print(x$by_facility, n = Inf)
  }

  if (nrow(x$duplicate_ids) > 0L) {
    cli::cli_h2("Duplicated Visit IDs")
    cli::cli_text(
      "{nrow(x$duplicate_ids)} facility \u00d7 Visit_ID pair(s) with >1 row. ",
      "Access via $duplicate_ids."
    )
  }

  invisible(x)
}
