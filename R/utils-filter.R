#' Stages of filter_care_setting()
#'
#' Internal helpers that [filter_care_setting()] runs in order, so the
#' exported function reads as a short pipeline.
#'
#' @details
#' The stages, in the order `filter_care_setting()` calls them:
#' \enumerate{
#'   \item `resolve_facility_id_str()` returns the facility ID column name,
#'     or `NA_character_` when the (optional) column is absent. It aborts if
#'     `fix_facility_id_vector` was supplied but the column is absent, and
#'     otherwise informs that ID-based corrections are unavailable.
#'   \item `correct_by_facility_id()`, `correct_by_facility_name()`, and
#'     `correct_by_facility_regex()` overwrite the facility type with `fix_to`
#'     for the facilities each route selects. They run in that order; the
#'     regex route skips every facility an earlier route already corrected,
#'     so the three routes combine without double-correcting.
#'   \item `preview_type_corrections()` builds the `dry_run` preview.
#'   \item `inform_dropped_types()` and `warn_if_no_rows()` report what the
#'     `keep_types` filter excluded.
#' }
#'
#' `apply_type_correction()` is the shared primitive behind the three
#' correction routes: it overwrites the facility type column with `fix_to`
#' for the rows selected by `mask`, leaving other rows unchanged.
#'
#' @param data A data frame already passed through [clean_names_safe()],
#'   with the `.original_facility_type` column added.
#' @param type_col_str,fac_col_str,id_col_str Names of the facility type,
#'   facility, and facility ID columns in `data`.
#' @param mask Logical vector, one element per row: which rows to correct.
#' @param fix_to The facility type value to write.
#' @param id_col_sym The symbol returned by `resolve_col_optional()` for the
#'   facility ID column, or `NULL` when it is absent.
#' @param fix_facility_id_vector,fix_facility_type_vector Values selecting
#'   the facilities to correct by ID and by exact name, or `NULL`.
#' @param fix_facility_type_regex A single regular expression, or `NULL`.
#' @param already_corrected Facility names already corrected by an earlier
#'   route, which the regex route skips.
#' @param dry_run Logical. Whether the call is a preview.
#' @param use_facility_id Logical. Whether the ID column is present, so it is
#'   included in the preview.
#' @param keep_types Character vector of facility types to keep.
#' @param type_col_label The facility type column's name as the caller wrote
#'   it (for example `FacilityType`), used in the messages from
#'   `inform_dropped_types()` and `warn_if_no_rows()`. Defaults to
#'   `type_col_str`.
#' @param result The filtered data frame. `warn_if_no_rows()` also takes
#'   `data`, the unfiltered input, to tell an empty input from a filter that
#'   matched nothing.
#' @param verbose Logical. Whether to emit informational messages.
#' @param call The environment errors are attributed to; see
#'   [resolve_col()].
#'
#' @return `resolve_facility_id_str()` returns a string.
#'   `correct_by_facility_id()` returns a list with the corrected `data` and
#'   the `names` of the facilities it corrected. The other `correct_by_*()`
#'   functions and `apply_type_correction()` return the corrected data
#'   frame.
#'   `preview_type_corrections()` returns the preview tibble.
#'   `inform_dropped_types()` and `warn_if_no_rows()` are called for their
#'   conditions.
#' @keywords internal
apply_type_correction <- function(data, type_col_str, mask, fix_to) {
  dplyr::mutate(
    data,
    "{type_col_str}" := dplyr::if_else(
      mask %in% TRUE, fix_to, .data[[type_col_str]]
    )
  )
}

#' @rdname apply_type_correction
resolve_facility_id_str <- function(id_col_sym, fix_facility_id_vector,
                                    verbose, call = rlang::caller_env()) {
  use_facility_id <- !is.null(id_col_sym)
  id_col_str      <- if (use_facility_id) {
    rlang::as_string(id_col_sym)
  } else {
    NA_character_
  }

  if (!use_facility_id && !is.null(fix_facility_id_vector)) {
    rlang::abort(
      paste0(
        "`facility_id_col` not found in data, but `fix_facility_id_vector` ",
        "was supplied. Include the facility ID field (e.g. `Hospital`) in ",
        "your ESSENCE API pull, or correct the `facility_id_col` argument."
      ),
      call = call
    )
  }

  if (!use_facility_id && is.null(fix_facility_id_vector)) {
    inform_if(
      verbose,
      paste0(
        "`facility_id_col` (default `Hospital`) not found in data. ID-based ",
        "corrections via `fix_facility_id_vector` are more durable across ",
        "facility name changes than `fix_facility_type_vector`; consider ",
        "including `Hospital` as a field in your ESSENCE API pull."
      )
    )
  }

  id_col_str
}

#' @rdname apply_type_correction
correct_by_facility_id <- function(data, fac_col_str, type_col_str, id_col_str,
                                   fix_facility_id_vector, fix_to) {
  if (is.na(id_col_str) || is.null(fix_facility_id_vector)) {
    return(list(data = data, names = character(0)))
  }

  id_matched_rows <- as_key_text(data[[id_col_str]]) %in%
    as_key_text(fix_facility_id_vector)

  list(
    data  = apply_type_correction(data, type_col_str, id_matched_rows, fix_to),
    names = unique(data[[fac_col_str]][id_matched_rows])
  )
}

#' @rdname apply_type_correction
correct_by_facility_name <- function(data, fac_col_str, type_col_str,
                                     fix_facility_type_vector, fix_to,
                                     dry_run) {
  if (is.null(fix_facility_type_vector)) return(data)

  matched   <- fix_facility_type_vector[
    fix_facility_type_vector %in% data[[fac_col_str]]
  ]
  unmatched <- setdiff(fix_facility_type_vector, matched)

  if (dry_run && length(unmatched) > 0L) {
    rlang::warn(
      paste0(
        length(unmatched),
        " facility name(s) in `fix_facility_type_vector` not found in data ",
        "and will be ignored:\n",
        paste0("  - ", unmatched, collapse = "\n"),
        "\nCheck for trailing whitespace or name changes since the last ",
        "data pull."
      )
    )
  }

  apply_type_correction(
    data, type_col_str,
    data[[fac_col_str]] %in% fix_facility_type_vector,
    fix_to
  )
}

#' @rdname apply_type_correction
correct_by_facility_regex <- function(data, fac_col_str, type_col_str,
                                      fix_facility_type_regex,
                                      already_corrected, fix_to) {
  if (is.null(fix_facility_type_regex)) return(data)

  # `str_detect()` returns NA for a missing facility name; `%in% TRUE` turns
  # that into "not matched", so such rows keep their original type instead of
  # having it overwritten with NA (and no NA is listed as a matched name) ----
  to_correct <- (
    !data[[fac_col_str]] %in% already_corrected &
      stringr::str_detect(data[[fac_col_str]], fix_facility_type_regex)
  ) %in% TRUE

  regex_matched <- unique(data[[fac_col_str]][to_correct])

  if (length(regex_matched) == 0L) return(data)

  rlang::warn(
    paste0(
      length(regex_matched),
      " facility/facilities matched by `fix_facility_type_regex` ",
      "and corrected to `", fix_to, "`:\n",
      paste0("  - ", regex_matched, collapse = "\n"),
      "\nConsider promoting these to `fix_facility_type_vector` or ",
      "`fix_facility_id_vector` for explicitness and reproducibility."
    )
  )

  apply_type_correction(data, type_col_str, to_correct, fix_to)
}

#' @rdname apply_type_correction
preview_type_corrections <- function(data, fac_col_str, type_col_str,
                                     id_col_str, use_facility_id, keep_types) {
  group_cols <- c(
    fac_col_str,
    if (use_facility_id) id_col_str else NULL,
    ".original_facility_type",
    type_col_str
  )

  preview <- data |>
    dplyr::group_by(dplyr::across(dplyr::all_of(group_cols))) |>
    dplyr::summarise(n_visits = dplyr::n(), .groups = "drop") |>
    dplyr::rename(
      facility                = dplyr::all_of(fac_col_str),
      original_facility_type  = .original_facility_type,
      corrected_facility_type = dplyr::all_of(type_col_str)
    )

  if (use_facility_id) {
    preview <- dplyr::rename(preview, facility_id = dplyr::all_of(id_col_str))
  }

  preview |>
    dplyr::mutate(
      .would_keep = corrected_facility_type %in% keep_types
    ) |>
    dplyr::arrange(dplyr::desc(n_visits))
}

#' @rdname apply_type_correction
inform_dropped_types <- function(data, type_col_str, keep_types, verbose,
                                 type_col_label = type_col_str) {
  dropped_types <- setdiff(unique(data[[type_col_str]]), keep_types)

  if (length(dropped_types) > 0L) {
    inform_if(
      verbose,
      paste0(
        "The following `", type_col_label, "` values are not in `keep_types` ",
        "and will be excluded:\n",
        paste0("  - ", dropped_types, collapse = "\n")
      )
    )
  }
}

#' @rdname apply_type_correction
warn_if_no_rows <- function(data, result, type_col_str, keep_types,
                            type_col_label = type_col_str) {
  if (nrow(result) > 0L) {
    return(invisible(NULL))
  }

  if (nrow(data) == 0L) {
    rlang::warn(paste0(
      "No rows remain after filtering. `data` has no rows, so there is ",
      "nothing to filter."
    ))
    return(invisible(NULL))
  }

  present <- unique(stats::na.omit(as.character(data[[type_col_str]])))
  present_text <- if (length(present) > 0L) {
    paste0("(", paste(present, collapse = ", "), ")")
  } else {
    "(all missing)"
  }

  # Matching is exact, so name any value that differs from a keep_types entry
  # only by letter case ----
  case_only <- present[
    tolower(present) %in% tolower(keep_types) & !present %in% keep_types
  ]
  case_hint <- if (length(case_only) > 0L) {
    paste0(
      " Matching is exact; ",
      paste0("\"", case_only, "\"", collapse = ", "),
      " differs from a `keep_types` value only in letter case."
    )
  } else {
    ""
  }

  rlang::warn(
    paste0(
      "No rows remain after filtering. None of the `", type_col_label,
      "` values in the data ", present_text, " is in `keep_types` (",
      paste(keep_types, collapse = ", "), ").", case_hint
    )
  )
}
