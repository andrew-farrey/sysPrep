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
#' `na_safe_group_id()` takes an optional `row_id` for data that has already
#' been expanded to several rows per source record (as [link_encounters()]
#' does, one row per patient class): NA-key rows with the same `row_id` stay in
#' one group, so one record is never split into several visits.
#'
#' `as_key_text()` converts an identifier column to text for comparison. Whole
#' numbers are written in full, so `100000` becomes `"100000"` rather than
#' `as.character()`'s `"1e+05"`, and two different long identifiers never
#' collapse to the same text.
#'
#' `inform_na_key_rows()` emits the standard informational message when
#' `na_safe_group_id()` exempted one or more rows. `inform_fn` is either
#' `rlang::inform` ([dedupe()] and [summarize_duplicates()], which have no
#' `verbose` argument) or a closure over `inform_if()` ([classify_duplicates()]
#' and [link_encounters()], which do).
#'
#' @param data A data frame.
#' @param cols Character vector of the key column names in `data`.
#' @param row_id Optional vector, one value per row of `data`, identifying the
#'   source record each row came from.
#' @param x A vector of identifiers (numeric, character, or factor).
#' @param n_na_key Integer. Number of rows with a missing key.
#' @param fac_col_str,visit_col_str Names of the facility and visit columns,
#'   used in the message.
#' @param inform_fn A function taking a single message string.
#'
#' @return `key_has_na_mask()` returns a logical vector, `TRUE` where any of
#'   `cols` is `NA`. `na_safe_group_id()` returns an integer group id per row.
#'   `as_key_text()` returns a character vector the length of `x`.
#'   `inform_na_key_rows()` returns `NULL` invisibly.
#' @keywords internal
key_has_na_mask <- function(data, cols) {
  Reduce(`|`, lapply(data[cols], is.na))
}

#' @rdname key_has_na_mask
as_key_text <- function(x) {
  # `as.character()` writes 100000 as "1e+05", and a plain "%.15g" rounds
  # integers of 16 or more digits, so two different identifiers could end up
  # as the same text. Whole numbers are written in full instead, and NA stays
  # NA ----
  if (is.numeric(x)) {
    value <- as.numeric(x)
    text  <- sprintf("%.15g", value)
    whole <- is.finite(value) & value == trunc(value)
    text[whole] <- formatC(value[whole], format = "f", digits = 0L)
    text[is.na(x)] <- NA_character_
    return(text)
  }
  as.character(x)
}

#' @rdname key_has_na_mask
na_safe_group_id <- function(data, cols, row_id = NULL) {
  key_is_na <- key_has_na_mask(data, cols)

  # The separator is the ASCII unit-separator control character (U+001F),
  # which cannot occur in an ESSENCE identifier, so two different
  # (facility, visit) pairs can never concatenate to the same key (e.g.
  # facility 100 + visit "15" vs. facility 1001 + visit "5"). Written as an
  # escape, never a literal, so it stays visible to readers and linters.
  group_key <- do.call(paste, c(data[cols], list(sep = "\x1f")))
  group_id  <- match(group_key, unique(group_key))

  if (any(key_is_na)) {
    # Without `row_id` every NA-key row is its own record. With it, NA-key
    # rows that share a `row_id` (several rows expanded from one source
    # record) stay together as one record ----
    na_record <- if (is.null(row_id)) {
      seq_len(sum(key_is_na))
    } else {
      match(row_id[key_is_na], unique(row_id[key_is_na]))
    }
    group_id[key_is_na] <- max(group_id) + na_record
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
