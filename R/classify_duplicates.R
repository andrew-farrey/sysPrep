
# classify_duplicates() ----
#' Classify the mechanism of duplication in an ESSENCE data pull
#'
#' Identifies and classifies the mechanism of duplication for each
#' facility x Visit_ID group containing more than one row.
#' Classification is based on which key ESSENCE fields vary within a
#' duplicate group: visit date (via C_BioSense_ID recomputation), patient
#' identifier, and/or patient class. Intended to be called before [dedupe()]
#' to inform deduplication strategy and understand the nature of data quality
#' issues in a specific pull.
#'
#' @details
#' ## Columns used
#' Required: `facility_col`, `visit_col`, `C_BioSense_ID`, `Date`,
#' `C_Unique_Patient_ID`. Optional: `C_Patient_Class` (enables
#' `patient_class_change` detection).
#'
#' ## Duplication mechanisms in ESSENCE
#' Multiple rows for the same facility x Visit_ID arise through distinct
#' mechanisms, each with different causes and implications:
#'
#' \describe{
#'   \item{`"visit_date_change"`}{`C_BioSense_ID` is derived from
#'     `C_Visit_Date` and `C_Visit_Date_Time`, which are frequently populated
#'     from `Admit_Date_Time`. When a hospital treats `C_Visit_Date_Time` as
#'     a modifiable field and submits an update that crosses midnight, NSSP
#'     computes a new `C_BioSense_ID` for the same `Visit_ID` -- producing
#'     two rows that refer to the same encounter. This is the most widespread
#'     duplication type across NSSP sites; the affected proportion of visits
#'     is typically small, but the impact is disproportionate in small-count
#'     syndrome definitions where a few inflated counts can trigger anomaly
#'     detection alerts that do not reflect genuine changes in incidence.
#'     The duplicate arises only at facilities that treat these fields as
#'     modifiable after initial registration. Detected by multiple distinct
#'     `C_BioSense_ID` values and `Date` values within a group.}
#'   \item{`"pid_change"`}{The patient identifier (`C_Unique_Patient_ID`,
#'     which maps to MRN in Kentucky) was updated or corrected mid-visit by
#'     the facility. Detected by multiple distinct `C_Unique_Patient_ID`
#'     values within a group. Not all ESSENCE sites use MRN as
#'     `C_Unique_Patient_ID`.}
#'   \item{`"patient_class_change"`}{Under normal HL7 processing, patient
#'     class transitions are handled without generating duplicate rows --
#'     the transition is appended to `C_Patient_Class_List` and the
#'     `HasBeenE`, `HasBeenI`, `HasBeenAdmitted` flags are updated in place.
#'     This type is detected when the same `Visit_ID` appears with multiple
#'     distinct `c_patient_class` values, which may indicate a feed
#'     configuration issue or a concurrent triggering event. Requires
#'     `c_patient_class` to be present in the data -- available via the
#'     standard ESSENCE API. See also [link_encounters()] for burden
#'     estimation from multi-class episodes.}
#'   \item{`"type_unknown"`}{Multiple rows exist but all assessed fields
#'     are identical across rows. The differentiating field was not included
#'     in the pull. Consider adding `C_BioSense_ID`, `Date`, and
#'     `C_Unique_Patient_ID` to your ESSENCE pull fields.}
#'   \item{Compound types}{Any combination of the above joined with `+`,
#'     e.g., `"visit_date_change+pid_change"`. Indicates multiple mechanisms
#'     acting simultaneously on the same visit. All possible combinations
#'     of the three primary mechanisms are detected and classified.}
#' }
#'
#' ## Required columns
#' All classification types require `facility_col`, `visit_col`,
#' `C_BioSense_ID` (or `c_biosense_id` / `c_bio_sense_id`), `Date` (or `date`), and
#' `C_Unique_Patient_ID` (or `c_unique_patient_id`). The function aborts
#' with an informative message if any are absent.
#'
#' ## Optional patient class detection
#' Detection of `patient_class_change` requires `c_patient_class` in the
#' data, available via the standard ESSENCE API as a pull field. When absent,
#' patient class change detection is skipped and all other types remain
#' functional.
#'
#' ## Linked vs. unlinked input
#' `classify_duplicates()` can be run on a raw (unlinked) ESSENCE pull, or on
#' the long-format output of [link_encounters()] -- it only requires
#' `facility_col`/`visit_col` and the identifying columns above, regardless
#' of which record structure they come from. Either way, `patient_class_change`
#' (and every other type here) is detected from rows that still exist
#' side-by-side with a shared `facility_col` x `visit_col` key: it looks for
#' more than one distinct value of a field (here, `c_patient_class`) across
#' those rows, not from any single row. Once those rows have already been
#' collapsed into one -- e.g. by [dedupe()], or by [link_encounters()] with
#' `return_format = "collapsed"` -- there is only one row left per key, so
#' `n_rows == 1` and nothing is classified as a duplicate at all, regardless
#' of what mechanism originally produced the now-merged rows. Classify before
#' collapsing if you want to see which mechanism was responsible.
#'
#' ## Return formats
#' \describe{
#'   \item{`"list"` (default)}{A named list of class `essence_dup_classified`
#'     with `$duplicate_ids`, `$visit_groups`, `$by_facility`, and
#'     `$overall`. `$duplicate_ids` is a tibble of facility x visit_col
#'     pairs with more than one row, consistent with
#'     [summarize_duplicates()]`$duplicate_ids`.}
#'   \item{`"tibble"`}{The visit-group level summary tibble only -- one row
#'     per facility x visit_col with `dup_type` and supporting `n_*`
#'     metrics. Suitable for joining back to original data or piping into
#'     further analysis.}
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
#' @param return_format Character string. One of `"list"` (default) or
#'   `"tibble"`. See Details.
#' @param verbose Logical. If `FALSE`, suppresses informational messages
#'   (`rlang::inform()`); warnings and errors are always shown regardless.
#'
#' @return When `return_format = "list"`, a named list of class
#'   `essence_dup_classified` with:
#'   \describe{
#'     \item{`$duplicate_ids`}{Tibble of facility x visit_col pairs with
#'       more than one row.}
#'     \item{`$visit_groups`}{Tibble with one row per facility x visit_col
#'       containing `n_rows`, `n_biosense_ids`, `n_dates`, `n_pid`,
#'       `n_patient_classes` (if available), and `dup_type`.}
#'     \item{`$by_facility`}{Wide-format count of each `dup_type` per
#'       facility, sorted by total duplicated Visit IDs descending.}
#'     \item{`$overall`}{Dataset-level counts and proportions by `dup_type`
#'       via [janitor::tabyl()].}
#'   }
#'   When `return_format = "tibble"`, the `$visit_groups` tibble only.
#'
#' @examples
#' # Default list return
#' essence_raw |> classify_duplicates()
#'
#' # Tibble return for piping
#' essence_raw |>
#'   classify_duplicates(return_format = "tibble") |>
#'   dplyr::filter(dup_type == "visit_date_change")
#'
#' # Join classifications back to raw data for row-level inspection
#' # (clean first so join keys match the snake_case output of classify_duplicates)
#' essence_raw |>
#'   janitor::clean_names() |>
#'   dplyr::left_join(
#'     classify_duplicates(essence_raw, return_format = "tibble"),
#'     by = c("hospital_name", "visit_id")
#'   )
#'
#' @seealso [summarize_duplicates()] for counts without mechanism detail;
#'   [dedupe()] to remove duplicates after review.
#' @export
classify_duplicates <- function(data,
                                facility_col  = HospitalName,
                                visit_col     = Visit_ID,
                                return_format = c("list", "tibble"),
                                verbose       = TRUE) {

  return_format <- match.arg(return_format)

  # Normalize names upfront ----
  data_clean    <- clean_names_safe(data)
  fac_col_str   <- resolve_col_str(data_clean, rlang::ensym(facility_col))
  visit_col_str <- resolve_col_str(data_clean, rlang::ensym(visit_col))

  # Resolve required columns -- accept raw ESSENCE names, clean_names() output, or variants ----
  biosense_col <- resolve_col_optional(data_clean, rlang::sym("C_BioSense_ID"))
  date_col     <- resolve_col_optional(data_clean, rlang::sym("Date"))
  pid_col      <- resolve_col_optional(data_clean, rlang::sym("C_Unique_Patient_ID"))

  biosense_col_str <- if (!is.null(biosense_col)) rlang::as_string(biosense_col) else NA_character_
  date_col_str     <- if (!is.null(date_col))     rlang::as_string(date_col)     else NA_character_
  pid_col_str      <- if (!is.null(pid_col))      rlang::as_string(pid_col)      else NA_character_

  # Validate required columns ----
  missing_cols <- character(0L)
  if (is.null(biosense_col)) missing_cols <- c(missing_cols, "C_BioSense_ID")
  if (is.null(date_col))     missing_cols <- c(missing_cols, "Date")
  if (is.null(pid_col))      missing_cols <- c(missing_cols, "C_Unique_Patient_ID")

  if (length(missing_cols) > 0L) {
    rlang::abort(
      paste0(
        "The following required columns are missing from data:\n",
        paste0("  - ", missing_cols, collapse = "\n"),
        "\nAll classification types require: C_BioSense_ID, Date, C_Unique_Patient_ID.",
        "\nEnsure these are included as fields in your ESSENCE API pull."
      )
    )
  }

  # Resolve optional C_Patient_Class ----
  pc_col        <- resolve_col_optional(data_clean, rlang::sym("C_Patient_Class"))
  has_patient_class <- !is.null(pc_col)
  pc_col_str    <- if (has_patient_class) rlang::as_string(pc_col) else NA_character_

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

  # Build visit-group summary ----
  visit_groups <- data_clean |>
    dplyr::group_by(
      .data[[fac_col_str]],
      .data[[visit_col_str]]
    ) |>
    dplyr::summarise(
      n_rows         = dplyr::n(),
      n_biosense_ids = dplyr::n_distinct(.data[[biosense_col_str]], na.rm = TRUE),
      n_dates        = dplyr::n_distinct(.data[[date_col_str]],     na.rm = TRUE),
      n_pid          = dplyr::n_distinct(.data[[pid_col_str]],      na.rm = TRUE),
      n_patient_classes = if (has_patient_class) {
        dplyr::n_distinct(.data[[pc_col_str]], na.rm = TRUE)
      } else {
        1L
      },
      .groups = "drop"
    )

  # Classify duplication type ----
  visit_groups <- visit_groups |>
    dplyr::mutate(
      .date_change  = n_dates > 1L,
      .pid_change   = n_pid   > 1L,
      .class_change = n_patient_classes > 1L & has_patient_class,
      dup_type = dplyr::case_when(
        # No duplication
        n_rows == 1L                                              ~ "no_duplication",
        # Type unknown -- multiple rows, no variation in assessed fields
        n_rows > 1L & !.date_change & !.pid_change & !.class_change ~ "type_unknown",
        # Single mechanisms
        .date_change  & !.pid_change  & !.class_change           ~ "visit_date_change",
        !.date_change &  .pid_change  & !.class_change           ~ "pid_change",
        !.date_change & !.pid_change  &  .class_change           ~ "patient_class_change",
        # Compound -- two mechanisms
        .date_change  &  .pid_change  & !.class_change           ~ "visit_date_change+pid_change",
        .date_change  & !.pid_change  &  .class_change           ~ "visit_date_change+patient_class_change",
        !.date_change &  .pid_change  &  .class_change           ~ "pid_change+patient_class_change",
        # Compound -- all three mechanisms
        .date_change  &  .pid_change  &  .class_change           ~ "visit_date_change+pid_change+patient_class_change",
        TRUE                                                      ~ "type_unknown"
      )
    ) |>
    dplyr::select(-.date_change, -.pid_change, -.class_change)

  # Return tibble early if requested ----
  if (return_format == "tibble") return(visit_groups)

  # Rows classified as an actual duplicate, shared by all three components
  # below ----
  dup_rows <- dplyr::filter(visit_groups, dup_type != "no_duplication")

  # Component: duplicate_ids ----
  duplicate_ids <- dplyr::select(
    dup_rows,
    dplyr::all_of(c(fac_col_str, visit_col_str))
  )

  # Component: by_facility wide summary ----
  by_facility <- dup_rows |>
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

  # Component: overall tabyl-style summary ----
  overall <- dup_rows |>
    janitor::tabyl(dup_type) |>
    janitor::adorn_pct_formatting(digits = 1) |>
    dplyr::arrange(dplyr::desc(n))

  # Assemble and return list ----
  structure(
    list(
      duplicate_ids = duplicate_ids,
      visit_groups  = visit_groups,
      by_facility   = by_facility,
      overall       = overall
    ),
    class             = "essence_dup_classified",
    facility_col      = fac_col_str,
    visit_col         = visit_col_str,
    has_patient_class = has_patient_class
  )
}

# print.essence_dup_classified() ----
#' @export
print.essence_dup_classified <- function(x, ...) {
  has_pc <- attr(x, "has_patient_class")

  cli::cli_h1("ESSENCE Duplicate Classification")

  if (!has_pc) {
    cli::cli_alert_info(
      "Patient class change detection was unavailable (`c_patient_class` absent)."
    )
  }

  cli::cli_h2("Overall")
  print(x$overall)

  cli::cli_h2("By Facility")
  print(x$by_facility, n = Inf)

  cli_duplicate_ids_footer(x)

  cli::cli_h2("Visit Groups")
  cli::cli_text(
    "{nrow(x$visit_groups)} facility \u00d7 Visit_ID groups total. ",
    "Access full detail via $visit_groups."
  )

  invisible(x)
}
