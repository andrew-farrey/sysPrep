#' Console output helpers
#'
#' Internal helpers for messages and printed reports.
#'
#' @details
#' `inform_if()` emits an [rlang::inform()] message only when `verbose` is
#' `TRUE`. It gates informational (non-fatal, non-warning) messages in
#' functions that have a `verbose` argument; [rlang::warn()] and
#' [rlang::abort()] calls never go through it and always fire.
#'
#' `print_lines()` returns the lines `print(x, ...)` would write as a
#' character vector, so a `format()` method can embed them with
#' `cli::cli_verbatim()`.
#'
#' `cli_duplicate_ids_footer()` renders the identical "Duplicated Visit IDs"
#' footer shared by the `format()` methods of `essence_dup_summary` and
#' `essence_dup_classified` objects. It must be called inside
#' `cli::cli_format_method()`.
#'
#' @param verbose Logical. Whether to emit the message.
#' @param ... Passed to [rlang::inform()] (for `inform_if()`) or to `print()`
#'   (for `print_lines()`).
#' @param x For `print_lines()`, any printable object; for
#'   `cli_duplicate_ids_footer()`, an `essence_dup_summary` or
#'   `essence_dup_classified` object.
#'
#' @return `inform_if()` returns `NULL` invisibly. `print_lines()` returns a
#'   character vector. `cli_duplicate_ids_footer()` is called for its cli
#'   output side effect.
#' @keywords internal
inform_if <- function(verbose, ...) {
  if (verbose) rlang::inform(...)
}

#' @rdname inform_if
print_lines <- function(x, ...) {
  utils::capture.output(print(x, ...))
}

#' @rdname inform_if
cli_duplicate_ids_footer <- function(x) {
  cli::cli_h2("Duplicated Visit IDs")
  cli::cli_text(
    "{nrow(x$duplicate_ids)} facility \u00d7 Visit_ID pair(s) with >1 row. ",
    "Access via $duplicate_ids."
  )
}
