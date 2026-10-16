#' Stages of dedupe() and summarize_duplicates()
#'
#' Internal helpers that [dedupe()] and [summarize_duplicates()] run in order,
#' so each exported function reads as a short pipeline.
#'
#' @details
#' [dedupe()] calls `sort_for_dedupe()` (apply the optional `order_by`, which
#' `keep = "most_complete"` ignores with a warning) and then
#' `keep_group_rows()` (apply the `keep` strategy within each
#' `facility x visit` group).
#'
#' [summarize_duplicates()] calls `count_visit_row_groups()` (one row per
#' `facility x visit` group with its row count),
#' `dup_summary_by_facility()`, and `dup_summary_overall()`.
#'
#' Grouping directly on `facility_col`/`visit_col` would follow the `dplyr`
#' SQL-style convention of treating every `NA` as equal to every other `NA`,
#' silently collapsing rows with a missing identifier into a single
#' "duplicate" even though a missing value means the row's true identity is
#' unknown, not confirmed to match. Both exported functions therefore group
#' with [na_safe_group_id()], which gives each NA-key row its own singleton
#' group, and report how many rows were affected.
#'
#' For `keep = "most_complete"`, `dplyr::pick(dplyr::everything())` already
#' excludes `.group_id`: `dplyr::pick()` never includes the active grouping
#' variable(s) among the columns it can pick, so no explicit exclusion is
#' needed (or possible, since `pick()` errors if asked to exclude a column it
#' never included).
#'
#' @param data A data frame already passed through [clean_names_safe()].
#' @param facility_col,visit_col Symbols for the resolved facility and visit
#'   columns.
#' @param order_by_quo The captured `order_by` expression (a `quosure` from
#'   [rlang::enquo()]), possibly `NULL`.
#' @param keep One of `"first"`, `"last"`, or `"most_complete"`.
#' @param call The environment errors are attributed to; see
#'   [resolve_col()].
#' @param fac_col_str,visit_col_str Names of the facility and visit columns.
#' @param data_clean A data frame already passed through [clean_names_safe()].
#' @param dup_group_ids The `.group_id` values of the groups with more than
#'   one row.
#' @param group_counts The data frame returned by `count_visit_row_groups()`.
#' @param dup_groups `group_counts` restricted to groups with `n_rows > 1`.
#'
#' @return `sort_for_dedupe()` returns `data`, sorted when `order_by` applies.
#'   `keep_group_rows()` returns the deduplicated data frame.
#'   `count_visit_row_groups()` returns a list with `data` (with a `.group_id`
#'   column) and `counts`. `dup_summary_by_facility()` and
#'   `dup_summary_overall()` return tibbles.
#' @keywords internal
sort_for_dedupe <- function(data, facility_col, visit_col, order_by_quo, keep,
                            call = rlang::caller_env()) {
  if (rlang::quo_is_null(order_by_quo)) return(data)

  order_by_str <- rlang::as_name(order_by_quo)
  order_col    <- resolve_col(data, rlang::sym(order_by_str), call = call)

  if (keep == "most_complete") {
    rlang::warn(
      paste0(
        "`order_by` is ignored when `keep = 'most_complete'`. ",
        "Row selection is based on column completeness, not sort order."
      )
    )
    return(data)
  }

  dplyr::arrange(
    data,
    !!facility_col,
    !!visit_col,
    !!order_col
  )
}

#' @rdname sort_for_dedupe
keep_group_rows <- function(data, fac_col_str, visit_col_str, keep) {
  n_na_key <- sum(key_has_na_mask(data, c(fac_col_str, visit_col_str)))
  inform_na_key_rows(n_na_key, fac_col_str, visit_col_str, rlang::inform)

  data$.group_id <- na_safe_group_id(data, c(fac_col_str, visit_col_str))
  grouped        <- dplyr::group_by(data, .group_id)

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

  dplyr::ungroup(deduped) |> dplyr::select(-.group_id)
}

#' @rdname sort_for_dedupe
count_visit_row_groups <- function(data_clean, fac_col_str, visit_col_str) {
  n_na_key <- sum(key_has_na_mask(data_clean, c(fac_col_str, visit_col_str)))
  inform_na_key_rows(n_na_key, fac_col_str, visit_col_str, rlang::inform)

  data_clean$.group_id <- na_safe_group_id(
    data_clean, c(fac_col_str, visit_col_str)
  )

  counts <- data_clean |>
    dplyr::group_by(.group_id) |>
    dplyr::summarise(
      "{fac_col_str}"   := dplyr::first(.data[[fac_col_str]]),
      "{visit_col_str}" := dplyr::first(.data[[visit_col_str]]),
      n_rows            = dplyr::n(),
      .groups           = "drop"
    )

  list(data = data_clean, counts = counts)
}

#' @rdname sort_for_dedupe
dup_summary_by_facility <- function(data_clean, fac_col_str,
                                    dup_group_ids) {
  data_clean |>
    dplyr::group_by(.data[[fac_col_str]]) |>
    dplyr::summarise(
      n_visits               = dplyr::n_distinct(.group_id),
      n_duplicated_visit_ids = dplyr::n_distinct(
        .group_id[.group_id %in% dup_group_ids]
      ),
      n_excess_rows          = sum(.group_id %in% dup_group_ids) -
        n_duplicated_visit_ids,
      pct_duplicated         = round(
        n_duplicated_visit_ids / n_visits * 100,
        digits = 1
      ),
      .groups = "drop"
    ) |>
    dplyr::filter(n_duplicated_visit_ids > 0L) |>
    dplyr::arrange(dplyr::desc(n_excess_rows))
}

#' @rdname sort_for_dedupe
dup_summary_overall <- function(data_clean, group_counts, dup_groups) {
  # group_counts has one row per distinct facility x visit_col pair (each
  # NA-key row counted as its own visit) ----
  n_total_visits <- nrow(group_counts)

  pct_dup <- if (n_total_visits == 0L) {
    NA_real_
  } else {
    round(nrow(dup_groups) / n_total_visits * 100, digits = 1)
  }

  tibble::tibble(
    n_total_rows           = nrow(data_clean),
    n_unique_visits        = n_total_visits,
    n_duplicated_visit_ids = nrow(dup_groups),
    n_excess_rows          = sum(dup_groups$n_rows - 1L),
    pct_duplicated         = pct_dup
  )
}
