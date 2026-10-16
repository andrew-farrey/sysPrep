#' NA-safe grouping keys
#'
#' Internal helpers that stop rows with a missing identifier from being merged
#' into one group. They are shared by [dedupe()], [summarize_duplicates()],
#' [classify_duplicates()], and [link_encounters()].
#'
#' @details
#' `dplyr::group_by()` and `.by =` follow SQL's `GROUP BY` convention, in which
#' every `NA` is equal to every other `NA` for grouping purposes, even though
#' `NA == NA` evaluates to `NA` everywhere else in R. For a
#' `facility_col x visit_col` key a missing value means the row's true
#' identity is unknown, not confirmed to match every other row with a missing
#' value, so grouping `NA`s together silently merges genuinely distinct visits
#' (several rows with no `Visit_ID` would collapse into one during
#' [dedupe()], or read as artificially "duplicated" in
#' [summarize_duplicates()]/[classify_duplicates()]).
#'
#' `na_safe_group_id()` groups rows with no `NA` in `cols` exactly as
#' `dplyr::group_by()` would, and places every row with any `NA` in `cols` in
#' a singleton group of its own. The group key joins the columns with the
#' ASCII unit-separator control character (U+001F), which cannot occur in an
#' ESSENCE identifier, so two different key pairs can never concatenate to the
#' same string (for example facility `100` + visit `"15"` versus facility
#' `1001` + visit `"5"`).
#'
#' `inform_na_key_rows()` emits the standard informational message when
#' `na_safe_group_id()` exempted one or more rows. `inform_fn` is either
#' `rlang::inform` ([dedupe()] and [summarize_duplicates()], which have no
#' `verbose` argument) or a closure over `inform_if()` ([classify_duplicates()]
#' and [link_encounters()], which do).
#'
#' @param data A data frame.
#' @param cols Character vector of the key column names in `data`.
#' @param n_na_key Integer. Number of rows with a missing key.
#' @param fac_col_str,visit_col_str Names of the facility and visit columns,
#'   used in the message.
#' @param inform_fn A function taking a single message string.
#'
#' @return `key_has_na_mask()` returns a logical vector, `TRUE` where any of
#'   `cols` is `NA`. `na_safe_group_id()` returns an integer group id per row.
#'   `inform_na_key_rows()` returns `NULL` invisibly.
#' @keywords internal
key_has_na_mask <- function(data, cols) {
  Reduce(`|`, lapply(data[cols], is.na))
}

#' @rdname key_has_na_mask
na_safe_group_id <- function(data, cols) {
  key_is_na <- key_has_na_mask(data, cols)

  # The separator is the ASCII unit-separator control character (U+001F),
  # which cannot occur in an ESSENCE identifier, so two different
  # (facility, visit) pairs can never concatenate to the same key (e.g.
  # facility 100 + visit "15" vs. facility 1001 + visit "5"). Written as an
  # escape, never a literal, so it stays visible to readers and linters.
  group_key <- do.call(paste, c(data[cols], list(sep = "\x1f")))
  group_id  <- match(group_key, unique(group_key))

  if (any(key_is_na)) {
    group_id[key_is_na] <- max(group_id) + seq_len(sum(key_is_na))
  }

  group_id
}

#' @rdname key_has_na_mask
inform_na_key_rows <- function(n_na_key, fac_col_str, visit_col_str,
                               inform_fn) {
  if (n_na_key == 0L) return(invisible())
  inform_fn(
    paste0(
      n_na_key, " row(s) have a missing `", fac_col_str, "` or `",
      visit_col_str, "` value and cannot be matched to any other row; ",
      "each is treated as its own distinct visit rather than being ",
      "merged with other rows sharing the same missing value."
    )
  )
}
