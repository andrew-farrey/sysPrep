#' Stages of classify_duplicates()
#'
#' Internal helpers that [classify_duplicates()] runs in order, so the
#' exported function reads as a short pipeline.
#'
#' @details
#' The stages, in the order `classify_duplicates()` calls them:
#' \enumerate{
#'   \item `resolve_classification_cols()` resolves the three required
#'     columns (`C_BioSense_ID`, `Date`, `C_Unique_Patient_ID`), accepting
#'     raw ESSENCE names, [janitor::clean_names()] output, or variants, and
#'     aborts listing every missing one.
#'   \item `resolve_patient_class_col()` resolves the optional
#'     `C_Patient_Class` column; without it patient class change detection is
#'     skipped.
#'   \item `summarize_visit_groups()` collapses `data` to one row per
#'     `facility x visit` group with the number of distinct
#'     `C_BioSense_ID`s, dates, patient identifiers, and patient classes. A
#'     missing `facility_col` or `visit_col` value means that row's true
#'     identity is unknown, not confirmed to match every other row with a
#'     missing value, so it is grouped with [na_safe_group_id()] rather than
#'     `dplyr::group_by()` (which would treat every `NA` as equal and
#'     silently classify unrelated visits as duplicated).
#'   \item `classify_dup_type()` assigns the `dup_type` from which fields
#'     varied: `"no_duplication"` for a single row, `"type_unknown"` for
#'     several rows with no variation in the assessed fields, one of the
#'     three single mechanisms, or a compound of two or three joined with
#'     `+`.
#'   \item `summarize_dup_by_facility()` and `summarize_dup_overall()` build
#'     the two summary tables from the rows classified as duplicates.
#'     `summarize_dup_overall()` builds the empty tibble directly for a
#'     clean pull, because `janitor::adorn_pct_formatting()` errors on a
#'     0-row tabyl (it tries to write a `"%"` string into a 0-row percent
#'     column).
#' }
#'
#' @param data_clean A data frame already passed through [clean_names_safe()].
#' @param call The environment errors are attributed to; see
#'   [resolve_col()].
#' @param verbose Logical. Whether to emit informational messages.
#' @param fac_col_str,visit_col_str Names of the facility and visit columns.
#' @param cols The list returned by `resolve_classification_cols()`.
#' @param patient_class The list returned by `resolve_patient_class_col()`.
#' @param visit_groups The data frame returned by `summarize_visit_groups()`.
#' @param has_patient_class Logical. Whether `C_Patient_Class` is available.
#' @param dup_rows `visit_groups` restricted to rows whose `dup_type` is not
#'   `"no_duplication"`.
#'
#' @return `resolve_classification_cols()` returns a list with `biosense`,
#'   `date`, and `pid` (strings). `resolve_patient_class_col()` returns a list
#'   with `has_patient_class` and `pc_col_str`. `summarize_visit_groups()`
#'   and `classify_dup_type()` return the visit-group data frame (the latter
#'   with `dup_type`). `summarize_dup_by_facility()` and
#'   `summarize_dup_overall()` return tibbles.
#' @keywords internal
resolve_classification_cols <- function(data_clean,
                                        call = rlang::caller_env()) {
  required_cols <- c(
    biosense = "C_BioSense_ID",
    date     = "Date",
    pid      = "C_Unique_Patient_ID"
  )
  resolved_cols <- lapply(
    required_cols,
    function(col) resolve_col_optional(data_clean, rlang::sym(col))
  )

  missing_cols <- required_cols[vapply(resolved_cols, is.null, logical(1L))]

  if (length(missing_cols) > 0L) {
    missing_bullets <- stats::setNames(
      paste0("`", missing_cols, "`"),
      rep("x", length(missing_cols))
    )
    rlang::abort(
      c(
        "The following required columns are missing from `data`:",
        missing_bullets,
        "i" = paste0(
          "All classification types require `C_BioSense_ID`, `Date`, and ",
          "`C_Unique_Patient_ID`."
        ),
        "i" = "Include them as fields in your ESSENCE API pull."
      ),
      call = call
    )
  }

  list(
    biosense = rlang::as_string(resolved_cols$biosense),
    date     = rlang::as_string(resolved_cols$date),
    pid      = rlang::as_string(resolved_cols$pid)
  )
}

#' @rdname resolve_classification_cols
resolve_patient_class_col <- function(data_clean, verbose) {
  pc_col <- resolve_col_optional(
    data_clean, rlang::sym("C_Patient_Class")
  )
  has_patient_class <- !is.null(pc_col)
  pc_col_str <- if (has_patient_class) {
    rlang::as_string(pc_col)
  } else {
    NA_character_
  }

  if (!has_patient_class) {
    inform_if(
      verbose,
      paste0(
        "`c_patient_class` not found in data. ",
        "Patient class change detection will be skipped. ",
        "To enable, include `c_patient_class` as a field in your ESSENCE ",
        "API pull. All other duplication types will still be classified."
      )
    )
  }

  list(has_patient_class = has_patient_class, pc_col_str = pc_col_str)
}

#' @rdname resolve_classification_cols
summarize_visit_groups <- function(data_clean, fac_col_str, visit_col_str,
                                   cols, patient_class, verbose) {
  n_na_key <- sum(key_has_na_mask(data_clean, c(fac_col_str, visit_col_str)))
  inform_na_key_rows(
    n_na_key, fac_col_str, visit_col_str,
    function(...) inform_if(verbose, ...)
  )

  data_clean$.group_id <- na_safe_group_id(
    data_clean, c(fac_col_str, visit_col_str)
  )

  biosense_col_str  <- cols$biosense
  date_col_str      <- cols$date
  pid_col_str       <- cols$pid
  has_patient_class <- patient_class$has_patient_class
  pc_col_str        <- patient_class$pc_col_str

  data_clean |>
    dplyr::group_by(.group_id) |>
    dplyr::summarise(
      "{fac_col_str}"   := dplyr::first(.data[[fac_col_str]]),
      "{visit_col_str}" := dplyr::first(.data[[visit_col_str]]),
      n_rows         = dplyr::n(),
      n_biosense_ids = dplyr::n_distinct(
        .data[[biosense_col_str]], na.rm = TRUE
      ),
      n_dates        = dplyr::n_distinct(.data[[date_col_str]], na.rm = TRUE),
      n_pid          = dplyr::n_distinct(.data[[pid_col_str]], na.rm = TRUE),
      n_patient_classes = if (has_patient_class) {
        dplyr::n_distinct(.data[[pc_col_str]], na.rm = TRUE)
      } else {
        1L
      },
      .groups = "drop"
    ) |>
    dplyr::select(-.group_id)
}

#' @rdname resolve_classification_cols
classify_dup_type <- function(visit_groups, has_patient_class) {
  visit_groups |>
    dplyr::mutate(
      .date_change  = n_dates > 1L,
      .pid_change   = n_pid   > 1L,
      .class_change = n_patient_classes > 1L & has_patient_class,
      dup_type = dplyr::case_when(
        # No duplication
        n_rows == 1L ~ "no_duplication",
        # Type unknown: multiple rows, no variation in assessed fields
        n_rows > 1L & !.date_change & !.pid_change & !.class_change ~
          "type_unknown",
        # Single mechanisms
        .date_change & !.pid_change & !.class_change ~ "visit_date_change",
        !.date_change & .pid_change & !.class_change ~ "pid_change",
        !.date_change & !.pid_change & .class_change ~ "patient_class_change",
        # Compound: two mechanisms
        .date_change & .pid_change & !.class_change ~
          "visit_date_change+pid_change",
        .date_change & !.pid_change & .class_change ~
          "visit_date_change+patient_class_change",
        !.date_change & .pid_change & .class_change ~
          "pid_change+patient_class_change",
        # Compound: all three mechanisms
        .date_change & .pid_change & .class_change ~
          "visit_date_change+pid_change+patient_class_change",
        TRUE ~ "type_unknown"
      )
    ) |>
    dplyr::select(-.date_change, -.pid_change, -.class_change)
}

#' @rdname resolve_classification_cols
summarize_dup_by_facility <- function(dup_rows, fac_col_str) {
  dup_rows |>
    dplyr::count(
      .data[[fac_col_str]],
      dup_type
    ) |>
    tidyr::pivot_wider(
      names_from  = dup_type,
      values_from = n,
      values_fill = 0L
    ) |>
    dplyr::mutate(
      n_duplicated_total = rowSums(
        dplyr::pick(-dplyr::all_of(fac_col_str))
      )
    ) |>
    dplyr::arrange(dplyr::desc(n_duplicated_total))
}

#' @rdname resolve_classification_cols
summarize_dup_overall <- function(dup_rows) {
  if (nrow(dup_rows) == 0L) {
    return(
      tibble::tibble(
        dup_type = character(0L),
        n        = integer(0L),
        percent  = character(0L)
      )
    )
  }

  dup_rows |>
    janitor::tabyl(dup_type) |>
    janitor::adorn_pct_formatting(digits = 1) |>
    dplyr::arrange(dplyr::desc(n))
}
