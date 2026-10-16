#' Shared steps of the geography assignment functions
#'
#' Internal helpers shared by [assign_treating_geography()] and
#' [assign_facility_geography()].
#'
#' @details
#' `validate_geography_cols()` downgrades `do_region`/`do_zip` to `FALSE`
#' (with an informational message) when a column required for that geography
#' type is absent. `check_region_col` controls whether `region_col_str`
#' itself is validated here: [assign_treating_geography()] validates it
#' separately afterward, since it is unconditionally required there for
#' out-of-state detection regardless of which geography types are requested,
#' whereas [assign_facility_geography()] has no such separate requirement and
#' validates it as part of this check.
#'
#' `resolve_geography_output_col()` resolves a `new_region_col`/`new_zip_col`
#' argument (a plain string naming the output column, or `NULL` to skip that
#' geography type) to its [janitor::clean_names()]-normalized form. It aborts
#' if the name collides with `reserved_col`, the bookkeeping column
#' (`.out_of_state`/`.facility_geography`) the calling function itself adds,
#' which would silently break the return-value contract. `reserved_col` is
#' passed dot-prefixed, as it is referenced everywhere else, but
#' `janitor::make_clean_names()` always strips a leading dot, so the
#' comparison strips it from `reserved_col` too. It also aborts if the
#' resolved name already exists in `data` unless `overwrite = TRUE`, which is
#' what makes writing to a new column non-destructive by default and requires
#' an explicit opt-in before any existing column can be clobbered.
#'
#' `assign_geography_reassignment()` applies the "preserve original values,
#' then reassign from the hospital columns" logic common to both functions.
#' `mask` marks which rows are reassigned: [assign_treating_geography()]
#' passes `.out_of_state` (selective), [assign_facility_geography()] an
#' all-`TRUE` vector (universal). The `*_target_exists` flags say whether the
#' output column already held a value (which `resolve_geography_output_col()`
#' only allows with `overwrite = TRUE`); `original_region`/`original_zip_code`
#' are only added in that case, since writing to a genuinely new column
#' already leaves the original untouched. They are populated only where
#' `mask` is `TRUE`, so an unmodified row is always identifiable by
#' `is.na(original_region)`.
#'
#' @param verbose Logical. Whether to emit informational messages.
#' @param do_region,do_zip Logical. Whether region/zip geography is being
#'   processed.
#' @param region_col_str,hosp_region_col_str,zip_col_str,hosp_zip_col_str
#'   Resolved column names (strings), or `NULL` when the optional column is
#'   absent.
#' @param check_region_col Logical. Whether to validate `region_col_str` here.
#' @param new_col The user-supplied output column name, or `NULL`.
#' @param data A data frame.
#' @param overwrite Logical. Whether an existing column may be overwritten.
#' @param reserved_col The dot-prefixed bookkeeping column name the output
#'   must not collide with.
#' @param arg_name The calling function's argument name (for example
#'   `"new_region_col"`), used in error messages.
#' @param call The environment errors are attributed to; see
#'   [resolve_col()].
#' @param region_output_col_str,zip_output_col_str Resolved output column
#'   names from `resolve_geography_output_col()`, or `NULL`.
#' @param region_target_exists,zip_target_exists Logical. Whether the output
#'   column already existed in `data`.
#' @param preserve_original_geographies Logical. Whether to add
#'   `original_region`/`original_zip_code` columns.
#' @param mask Logical vector, one element per row of `data`: which rows are
#'   reassigned.
#'
#' @return `validate_geography_cols()` returns a list with `do_region` and
#'   `do_zip`. `resolve_geography_output_col()` returns the normalized output
#'   column name, or `NULL`. `assign_geography_reassignment()` returns `data`
#'   with the geography columns written.
#' @keywords internal
validate_geography_cols <- function(verbose, do_region, do_zip,
                                    region_col_str, hosp_region_col_str,
                                    zip_col_str, hosp_zip_col_str,
                                    check_region_col = TRUE) {
  if (do_region) {
    if (check_region_col && is.null(region_col_str)) {
      inform_if(
        verbose,
        "Region geography skipped: `Region` not found in data."
      )
      do_region <- FALSE
    } else if (is.null(hosp_region_col_str)) {
      inform_if(
        verbose,
        "Region geography skipped: `HospitalRegion` not found in data."
      )
      do_region <- FALSE
    }
  }

  if (do_zip) {
    if (is.null(zip_col_str)) {
      inform_if(verbose, "Zip geography skipped: `ZipCode` not found in data.")
      do_zip <- FALSE
    } else if (is.null(hosp_zip_col_str)) {
      inform_if(
        verbose,
        "Zip geography skipped: `HospitalZip` not found in data."
      )
      do_zip <- FALSE
    }
  }

  list(do_region = do_region, do_zip = do_zip)
}

#' @rdname validate_geography_cols
resolve_geography_output_col <- function(new_col, data, overwrite,
                                         reserved_col, arg_name,
                                         call = rlang::caller_env()) {
  if (is.null(new_col)) return(NULL)

  check_string(new_col, arg = arg_name, call = call)
  output_col_str <- janitor::make_clean_names(new_col)

  if (identical(output_col_str, sub("^\\.", "", reserved_col))) {
    rlang::abort(
      paste0(
        "`", arg_name, " = \"", new_col, "\"` collides with `",
        reserved_col, "`, the bookkeeping column this function adds. ",
        "Choose a different column name."
      ),
      call = call
    )
  }

  if (output_col_str %in% names(data) && !overwrite) {
    rlang::abort(
      paste0(
        "Column `", output_col_str, "` already exists in `data`. Set ",
        "`overwrite = TRUE` to overwrite it, or choose a different `",
        arg_name, "` value."
      ),
      call = call
    )
  }

  output_col_str
}

#' @rdname validate_geography_cols
assign_geography_reassignment <- function(data, do_region, do_zip,
                                          region_col_str, hosp_region_col_str,
                                          zip_col_str, hosp_zip_col_str,
                                          region_output_col_str,
                                          zip_output_col_str,
                                          region_target_exists,
                                          zip_target_exists,
                                          preserve_original_geographies,
                                          mask) {

  if (preserve_original_geographies) {
    if (region_target_exists) {
      data <- dplyr::mutate(
        data,
        original_region = dplyr::if_else(
          mask, .data[[region_output_col_str]], NA
        )
      )
    }
    if (zip_target_exists) {
      data <- dplyr::mutate(
        data,
        original_zip_code = dplyr::if_else(
          mask, .data[[zip_output_col_str]], NA
        )
      )
    }
  }

  if (do_region) {
    data <- dplyr::mutate(
      data,
      "{region_output_col_str}" := dplyr::if_else(
        mask, .data[[hosp_region_col_str]], .data[[region_col_str]]
      )
    )
  }

  if (do_zip) {
    data <- dplyr::mutate(
      data,
      "{zip_output_col_str}" := dplyr::if_else(
        mask, .data[[hosp_zip_col_str]], .data[[zip_col_str]]
      )
    )
  }

  data
}
