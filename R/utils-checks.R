#' Validate the arguments of exported functions
#'
#' Internal argument checkers called at the top of every exported function.
#' Each aborts with a classed `rlang_error` whose message names the offending
#' argument, attributed to the exported function the user actually called
#' (via `call`) rather than to the checker. They exist so a wrong argument
#' fails with a plain message instead of an error raised from deep inside a
#' dplyr verb or from a base R `if ()` ("missing value where TRUE/FALSE
#' needed").
#'
#' @details
#' By default `arg` is `rlang::caller_arg(x)`, the expression the user passed
#' to the *calling function*, so `check_data_frame(ed_data)` reports
#' `ed_data`. `is_scalar_number()` is the non-aborting predicate behind
#' `check_number()`.
#'
#' @param x The value to check.
#' @param arg The argument name to use in the error message. Defaults to the
#'   caller's expression for `x`.
#' @param call The environment the error is attributed to. Defaults to the
#'   caller's frame, i.e. the exported function.
#' @param allow_null Logical. If `TRUE`, `NULL` passes the check.
#' @param lower,upper Inclusive numeric bounds for `check_number()`.
#'
#' @return `is_scalar_number()` returns a single logical. The `check_*()`
#'   functions return `x` invisibly when it is valid, and otherwise abort.
#' @keywords internal
is_scalar_number <- function(x) {
  is.numeric(x) && length(x) == 1L && !is.na(x)
}

#' @rdname is_scalar_number
check_data_frame <- function(x, arg = rlang::caller_arg(x),
                             call = rlang::caller_env()) {
  if (!is.data.frame(x)) {
    rlang::abort(
      c(
        paste0("`", arg, "` must be a data frame."),
        "x" = paste0("`", arg, "` is of class `", class(x)[1L], "`.")
      ),
      call = call
    )
  }
  invisible(x)
}

#' @rdname is_scalar_number
check_flag <- function(x, arg = rlang::caller_arg(x),
                       call = rlang::caller_env()) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    rlang::abort(
      c(
        paste0("`", arg, "` must be `TRUE` or `FALSE`."),
        "x" = paste0("`", arg, "` is of class `", class(x)[1L],
                     "` and length ", length(x), ".")
      ),
      call = call
    )
  }
  invisible(x)
}

#' @rdname is_scalar_number
check_string <- function(x, allow_null = FALSE, arg = rlang::caller_arg(x),
                         call = rlang::caller_env()) {
  if (allow_null && is.null(x)) return(invisible(x))
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x)) {
    rlang::abort(
      c(
        paste0("`", arg, "` must be a single, non-empty character string."),
        "x" = paste0("`", arg, "` is of class `", class(x)[1L],
                     "` and length ", length(x), ".")
      ),
      call = call
    )
  }
  invisible(x)
}

#' @rdname is_scalar_number
check_character <- function(x, allow_null = FALSE,
                            arg = rlang::caller_arg(x),
                            call = rlang::caller_env()) {
  if (allow_null && is.null(x)) return(invisible(x))
  if (!is.character(x) || anyNA(x)) {
    rlang::abort(
      c(
        paste0(
          "`", arg, "` must be a character vector with no missing values."
        ),
        "x" = paste0("`", arg, "` is of class `", class(x)[1L], "`.")
      ),
      call = call
    )
  }
  invisible(x)
}

#' @rdname is_scalar_number
check_number <- function(x, lower = -Inf, upper = Inf,
                         arg = rlang::caller_arg(x),
                         call = rlang::caller_env()) {
  if (!is_scalar_number(x) || x < lower || x > upper) {
    rlang::abort(
      c(
        paste0(
          "`", arg, "` must be a single number between ", lower, " and ",
          upper, " (inclusive)."
        ),
        "x" = paste0(
          "`", arg, "` is `", paste(format(x), collapse = ", "), "`."
        )
      ),
      call = call
    )
  }
  invisible(x)
}
