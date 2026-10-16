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
#' supplied name and the data's names to snake_case and requires exactly one
#' match. It aborts, attributed to `call`, when no unique match exists.
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
#' `clean_names_safe()` is [janitor::clean_names()] that preserves
#' leading-dot prefixes. `janitor::clean_names()` strips leading dots (for
#' example `.index_encounter` becomes `index_encounter`), which would break
#' references to the metadata columns that sysPrep itself adds
#' (`.index_encounter`, `.out_of_state`, ...). A consequence is that a raw
#' input column must never be given a leading-dot name: it would not
#' normalize like other raw columns.
#'
#' @param data A data frame, normally already passed through
#'   `clean_names_safe()`.
#' @param col_sym A symbol naming a column, in raw ESSENCE or snake_case form.
#'   For `as_string_or_null()`, a symbol returned by `resolve_col_optional()`,
#'   or `NULL`.
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
#'   returns a string, or `NULL` for a `NULL` input. `clean_names_safe()`
#'   returns `data` with snake_case names and any leading-dot names kept.
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
      rename_map <- setNames(present, restore)
      data <- dplyr::rename(data, dplyr::all_of(rename_map))
    }
  }
  data
}
