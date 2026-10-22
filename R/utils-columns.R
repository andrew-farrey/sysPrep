#' Resolve column arguments against the data
#'
#' Internal helpers that turn a user-supplied column argument (an unquoted
#' name captured with [rlang::ensym()] or [rlang::enquo()]) into the column
#' name actually present in `data`. Every `_col` argument in sysPrep accepts
#' both raw ESSENCE names (`HospitalName`) and their
#' [janitor::clean_names()] equivalents (`hospital_name`), so users never
#' have to know which form their data is in.
#'
#' @details
#' `resolve_col()` tries a direct match first, then normalizes both the
#' supplied name and the data's names to snake_case and matches on that.
#' `janitor::make_clean_names()` makes the names in a vector unique (two
#' columns that would both be `visit_id` become `visit_id` and `visit_id_2`),
#' so at most one column can match a given normalized name; because every
#' exported function normalizes `data` first, this is always the case. It
#' aborts, attributed to `call`, when nothing matches.
#' `resolve_col_optional()` returns `NULL` instead of aborting, for functions
#' that degrade gracefully when an optional column (for example
#' `HospitalZip`) was not pulled. `resolve_col_str()` is `resolve_col()`
#' returning a string, for `.data[[...]]` subsetting.
#'
#' `resolve_facility_col()` is shared by every exported function taking a
#' `facility_col` argument. When the caller did not supply `facility_col` (it
#' checks this with `rlang::quo_is_null()` before evaluating the argument and
#' passes the result as `facility_col_missing`), it prefers the stable numeric
#' `Hospital`/`C_BioSense_Facility_ID` identifier over the mutable
#' `HospitalName` display string: a facility rename or rebrand changes
#' `HospitalName` but not `Hospital`, so grouping or joining by
#' `HospitalName` can silently split one facility's rows across a rename, or
#' merge two different facilities that briefly share a display name. An
#' explicitly supplied `facility_col` is always honored exactly as given.
#'
#' `capture_col_sym()` turns an optional, `NULL`-defaulting column argument,
#' captured by the exported function with `rlang::enquo()`, into a symbol (or
#' `NULL` when it was not supplied). Every function with a `facility_col`
#' argument uses it, so the capture is written once; it aborts with a plain
#' message, attributed to the caller, when given something other than a name
#' (for example `c(a, b)`), where `rlang::as_name()` alone fails with an
#' error about a captured expression.
#'
#' `clean_names_safe()` is [janitor::clean_names()] that preserves
#' leading-dot prefixes. `janitor::clean_names()` strips leading dots (for
#' example `.index_encounter` becomes `index_encounter`), which would break
#' references to the metadata columns that sysPrep itself adds
#' (`.index_encounter`, `.out_of_state`, ...). A consequence is that a raw
#' input column must never be given a leading-dot name: it would not
#' normalize like other raw columns.
#'
#' `input_name_map()`, `restore_input_names()` and `finish_names()` implement
#' `clean_names = FALSE`. Every function normalizes its input names so column
#' arguments resolve either way, which would otherwise make `clean_names =
#' FALSE` a no-op on output. `input_name_map()` records which original name
#' each normalized name came from (positionally, since normalization neither
#' drops nor reorders columns); `restore_input_names()` renames the result's
#' columns back through that map, leaving the columns the function itself
#' added (`.index_encounter`, `region_hybrid`, ...) as they are; and
#' `finish_names()` is the single exit that applies whichever of
#' `clean_names_safe()` or the restore the caller asked for.
#'
#' @param data A data frame, normally already passed through
#'   `clean_names_safe()`.
#' @param original_names,cleaned_names The column names of the input before
#'   and after `clean_names_safe()`, in the same order.
#' @param name_map The named character vector from `input_name_map()`: values
#'   are original names, names are their normalized forms.
#' @param result The data frame about to be returned.
#' @param clean_names Logical. The caller's `clean_names` argument.
#' @param col_sym A symbol naming a column, in raw ESSENCE or snake_case form.
#'   For `as_string_or_null()`, a symbol returned by `resolve_col_optional()`,
#'   or `NULL`.
#' @param col_quo The expression captured by `rlang::enquo()` for an optional
#'   column argument.
#' @param arg The argument's name, used in the error message.
#' @param facility_col_sym A symbol naming the user-supplied `facility_col`,
#'   or `NULL` when it was not supplied.
#' @param facility_col_missing Logical. `TRUE` when the caller did not supply
#'   `facility_col`, so the `Hospital`-preferring default applies.
#' @param call The environment of the exported function that errors should be
#'   attributed to. Defaults to the caller's frame, so an error raised from an
#'   exported function's own call reads "Error in `dedupe()`" rather than
#'   "Error in `resolve_col()`". Wrappers forward their own `call`.
#'
#' @return `resolve_col()`, `resolve_col_optional()`, and
#'   `resolve_facility_col()` return a symbol (`resolve_col_optional()`
#'   returns `NULL` when the column is absent). `resolve_col_str()` and
#'   `resolve_facility_col_str()` return a string. `as_string_or_null()`
#'   returns a string, or `NULL` for a `NULL` input. `capture_col_sym()`
#'   returns a symbol, or `NULL`. `clean_names_safe()`
#'   returns `data` with snake_case names and any leading-dot names kept.
#'   `input_name_map()` returns the named character vector described above.
#'   `restore_input_names()` and `finish_names()` return `result` with its
#'   column names restored or normalized.
#' @keywords internal
resolve_col <- function(data, col_sym, call = rlang::caller_env()) {

  col_str <- rlang::as_string(col_sym)
  nms     <- names(data)

  # 1. Direct match first (fast path) ----
  if (col_str %in% nms) return(rlang::sym(col_str))

  # 2. Normalize both sides to snake_case and match ----
  clean_provided <- janitor::make_clean_names(col_str)
  clean_nms      <- janitor::make_clean_names(nms)
  match_idx      <- which(clean_nms == clean_provided)

  if (length(match_idx) == 1L) return(rlang::sym(nms[match_idx]))

  rlang::abort(
    c(
      paste0("Column `", col_str, "` not found in data."),
      "i" = "Tried a direct match and a snake_case-normalized match.",
      "i" = paste0("Available columns: ", paste(nms, collapse = ", "))
    ),
    call = call
  )
}

#' @rdname resolve_col
resolve_col_optional <- function(data, col_sym) {
  tryCatch(
    resolve_col(data, col_sym),
    error = function(e) NULL
  )
}

#' @rdname resolve_col
resolve_col_str <- function(data, col_sym, call = rlang::caller_env()) {
  rlang::as_string(resolve_col(data, col_sym, call = call))
}

#' @rdname resolve_col
resolve_facility_col <- function(data, facility_col_sym, facility_col_missing,
                                 call = rlang::caller_env()) {
  if (facility_col_missing) {
    hospital_id_sym <- resolve_col_optional(data, rlang::sym("Hospital"))
    if (!is.null(hospital_id_sym)) {
      return(hospital_id_sym)
    }
    return(resolve_col(data, rlang::sym("HospitalName"), call = call))
  }
  resolve_col(data, facility_col_sym, call = call)
}

#' @rdname resolve_col
resolve_facility_col_str <- function(data, facility_col_sym,
                                     facility_col_missing,
                                     call = rlang::caller_env()) {
  rlang::as_string(
    resolve_facility_col(
      data, facility_col_sym, facility_col_missing, call = call
    )
  )
}

#' @rdname resolve_col
capture_col_sym <- function(col_quo, arg = "facility_col",
                            call = rlang::caller_env()) {
  if (rlang::quo_is_null(col_quo)) return(NULL)

  expr <- rlang::quo_get_expr(col_quo)
  if (rlang::is_symbol(expr)) return(expr)
  if (rlang::is_string(expr)) return(rlang::sym(expr))

  rlang::abort(
    c(
      paste0("`", arg, "` must be an unquoted column name."),
      "x" = paste0("Got `", rlang::as_label(expr), "`.")
    ),
    call = call
  )
}

#' @rdname resolve_col
as_string_or_null <- function(col_sym) {
  if (is.null(col_sym)) NULL else rlang::as_string(col_sym)
}

#' @rdname resolve_col
clean_names_safe <- function(data) {
  dot_cols <- grep("^\\.", names(data), value = TRUE)
  data     <- janitor::clean_names(data)
  if (length(dot_cols) > 0L) {
    stripped  <- sub("^\\.", "", dot_cols)
    clean_stripped <- janitor::make_clean_names(stripped)
    present   <- intersect(clean_stripped, names(data))
    if (length(present) > 0L) {
      restore   <- paste0(".", present)
      rename_map <- stats::setNames(present, restore)
      data <- dplyr::rename(data, dplyr::all_of(rename_map))
    }
  }
  data
}

#' @rdname resolve_col
input_name_map <- function(original_names, cleaned_names) {
  stats::setNames(original_names, cleaned_names)
}

#' @rdname resolve_col
restore_input_names <- function(result, name_map) {
  idx <- match(names(result), names(name_map))
  hit <- !is.na(idx)
  names(result)[hit] <- unname(name_map)[idx[hit]]
  result
}

#' @rdname resolve_col
finish_names <- function(result, clean_names, name_map) {
  if (clean_names) {
    clean_names_safe(result)
  } else {
    restore_input_names(result, name_map)
  }
}
