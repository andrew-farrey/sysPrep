#' Shared steps of the geography assignment functions
#'
#' Internal helpers shared by [assign_treating_geography()] and
#' [assign_facility_geography()].
#'
#' @details
#' `validate_geography_cols()` downgrades `do_region`/`do_zip` to `FALSE`
#' (with an informational message) when a column required for that geography
#' type is absent. The facility columns (`HospitalRegion`, `HospitalZip`) are
#' always required for their type. The patient columns (`Region`, `ZipCode`)
#' are only the "leave this row alone" values of a selective reassignment, so
#' whether they are required depends on the caller. This function never
#' validates `Region`: [assign_treating_geography()] checks it separately
#' afterward, since it is unconditionally required there for out-of-state
#' detection regardless of which geography types are requested, and
#' [assign_facility_geography()] never reads it. `check_zip_col` says whether
#' to validate `ZipCode` here: [assign_treating_geography()] needs it, while
#' [assign_facility_geography()] reassigns every row, so it never reads the
#' patient columns (unless `overwrite = TRUE` names one as its output).
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
#' The remaining helpers are the stages the two exported functions share:
#' `resolve_geography_sources()` resolves the four optional source columns
#' to strings (or `NULL` when absent); `resolve_geography_outputs()` resolves
#' both output column names with `resolve_geography_output_col()`;
#' `reassign_geography()` works out which output columns already exist and
#' calls `assign_geography_reassignment()`. Only [assign_treating_geography()]
#' uses `warn_site_without_region_match()` (a `site` that matches no `Region`
#' value, such as a typo, the wrong case, or another state's pull, would
#' otherwise flag every visit as out-of-state without any sign that something
#' is off) and `flag_out_of_state()`. `"{site}_UNKNOWN"` (for example
#' `"KY_UNKNOWN"`) is ESSENCE's placeholder for a known-site record whose
#' residential geography could not be determined; unlike `"OTHER_REGION"` it
#' carries the site prefix, so it must be tested for explicitly or the prefix
#' check would leave it classified as in-state. `inform_treating_result()`
#' and `inform_facility_result()` report the outcome.
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
#' @param region_sym,hosp_region_sym,zip_sym,hosp_zip_sym Symbols captured
#'   from the four source column arguments (raw ESSENCE or snake_case names).
#' @param flags The list returned by `validate_geography_cols()`, with
#'   `do_region` and `do_zip`.
#' @param sources The list returned by `resolve_geography_sources()`.
#' @param outputs The list returned by `resolve_geography_outputs()`.
#' @param new_region_col,new_zip_col The user-supplied output column names, or
#'   `NULL` to skip that geography type.
#' @param site The site prefix identifying in-state `Region` values.
#' @param do_region,do_zip Logical. Whether region/zip geography is being
#'   processed.
#' @param region_col_str,hosp_region_col_str,zip_col_str,hosp_zip_col_str
#'   Resolved column names (strings), or `NULL` when the optional column is
#'   absent.
#' @param check_zip_col Logical. Whether to validate `zip_col_str` (the
#'   patient zip column) here.
#' @param new_col The user-supplied output column name, or `NULL`.
#' @param data A data frame.
#' @param col_str A resolved column name, or `NULL` when the column is absent.
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
#'   `do_zip`. `resolve_geography_sources()` returns a list with `region`,
#'   `hosp_region`, `zip`, and `hosp_zip` (strings or `NULL`).
#'   `resolve_geography_outputs()` returns a list with `region` and `zip`
#'   (strings or `NULL`). `reassign_geography()` and `flag_out_of_state()`
#'   return the updated data frame. `warn_site_without_region_match()` and
#'   `inform_*_result()` are called for their conditions.
#'   `resolve_geography_output_col()` returns the normalized output column
#'   name, or `NULL`. `assign_geography_reassignment()` returns `data` with
#'   the geography columns written. `patient_geography()` returns the patient
#'   column's values, or a single `NA` when the column is absent.
#' @keywords internal
validate_geography_cols <- function(verbose, do_region, do_zip,
                                    region_col_str, hosp_region_col_str,
                                    zip_col_str, hosp_zip_col_str,
                                    check_zip_col = TRUE) {
  if (do_region) {
    if (is.null(hosp_region_col_str)) {
      inform_if(
        verbose,
        "Region geography skipped: `HospitalRegion` not found in data."
      )
      do_region <- FALSE
    }
  }

  if (do_zip) {
    if (check_zip_col && is.null(zip_col_str)) {
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

  # The patient column may be absent when no row keeps its own value (the
  # facility function, mask all TRUE); NA stands in for it then ----
  if (do_region) {
    keep_region <- patient_geography(data, region_col_str)
    data <- dplyr::mutate(
      data,
      "{region_output_col_str}" := dplyr::if_else(
        mask, .data[[hosp_region_col_str]], !!keep_region
      )
    )
  }

  if (do_zip) {
    keep_zip <- patient_geography(data, zip_col_str)
    data <- dplyr::mutate(
      data,
      "{zip_output_col_str}" := dplyr::if_else(
        mask, .data[[hosp_zip_col_str]], !!keep_zip
      )
    )
  }

  data
}

#' @rdname validate_geography_cols
patient_geography <- function(data, col_str) {
  if (is.null(col_str)) NA_character_ else data[[col_str]]
}

#' @rdname validate_geography_cols
resolve_geography_sources <- function(data, region_sym, hosp_region_sym,
                                      zip_sym, hosp_zip_sym) {
  resolve_str <- function(sym) {
    as_string_or_null(resolve_col_optional(data, sym))
  }

  list(
    region      = resolve_str(region_sym),
    hosp_region = resolve_str(hosp_region_sym),
    zip         = resolve_str(zip_sym),
    hosp_zip    = resolve_str(hosp_zip_sym)
  )
}

#' @rdname validate_geography_cols
resolve_geography_outputs <- function(data, flags, new_region_col, new_zip_col,
                                      overwrite, reserved_col,
                                      call = rlang::caller_env()) {
  # Aborts on a reserved-name collision, or on an existing-column collision
  # unless overwrite = TRUE. By default new_region_col/new_zip_col name new
  # columns, leaving region_col/zip_col untouched; passing the source
  # column's own name plus overwrite = TRUE reproduces the original
  # in-place-overwrite behavior ----
  list(
    region = if (flags$do_region) {
      resolve_geography_output_col(
        new_region_col, data, overwrite, reserved_col, "new_region_col",
        call = call
      )
    },
    zip = if (flags$do_zip) {
      resolve_geography_output_col(
        new_zip_col, data, overwrite, reserved_col, "new_zip_col",
        call = call
      )
    }
  )
}

#' @rdname validate_geography_cols
reassign_geography <- function(data, flags, sources, outputs,
                               preserve_original_geographies, mask) {
  region_target_exists <- flags$do_region &&
    outputs$region %in% names(data)
  zip_target_exists    <- flags$do_zip && outputs$zip %in% names(data)

  # Preserve original geographies (only meaningful when the target already
  # held a value, i.e. overwrite = TRUE was used) and reassign ----
  assign_geography_reassignment(
    data, flags$do_region, flags$do_zip,
    sources$region, sources$hosp_region,
    sources$zip, sources$hosp_zip,
    outputs$region, outputs$zip,
    region_target_exists, zip_target_exists,
    preserve_original_geographies,
    mask = mask
  )
}

#' @rdname validate_geography_cols
warn_site_without_region_match <- function(data, region_col_str, site) {
  site_prefix <- paste0(site, "_")

  if (nrow(data) > 0L &&
        !any(startsWith(as.character(data[[region_col_str]]), site_prefix),
             na.rm = TRUE)) {
    rlang::warn(
      c(
        paste0(
          "No `", region_col_str, "` value begins with `", site_prefix,
          "`, so every visit will be treated as out-of-state."
        ),
        "i" = paste0(
          "Check that `site` (currently \"", site, "\") matches the prefix ",
          "of your ESSENCE Region values; it is case-sensitive."
        )
      )
    )
  }
}

#' @rdname validate_geography_cols
flag_out_of_state <- function(data, region_col_str, site) {
  site_prefix <- paste0(site, "_")

  dplyr::mutate(
    data,
    .out_of_state = is.na(.data[[region_col_str]]) |
      .data[[region_col_str]] == "OTHER_REGION" |
      .data[[region_col_str]] == paste0(site_prefix, "UNKNOWN") |
      !stringr::str_starts(
        .data[[region_col_str]],
        stringr::fixed(site_prefix)
      )
  )
}

#' @rdname validate_geography_cols
inform_treating_result <- function(data, outputs, verbose) {
  n_reassigned <- sum(data$.out_of_state, na.rm = TRUE)
  n_total      <- nrow(data)
  output_cols  <- c(outputs$region, outputs$zip)

  if (n_total == 0L) {
    inform_if(
      verbose,
      "No rows in data after processing. Returning empty data frame."
    )
  } else {
    inform_if(
      verbose,
      paste0(
        n_reassigned, " of ", n_total, " visits (",
        round(n_reassigned / n_total * 100, 1), "%) ",
        "identified as out-of-state or OTHER_REGION and assigned treating ",
        "facility geography in `", paste(output_cols, collapse = "`/`"), "`."
      )
    )
  }
}

#' @rdname validate_geography_cols
inform_facility_result <- function(data, outputs, verbose) {
  output_cols <- c(outputs$region, outputs$zip)

  if (nrow(data) == 0L) {
    inform_if(
      verbose,
      "No rows in data after processing. Returning empty data frame."
    )
  } else {
    inform_if(
      verbose,
      paste0(
        "Facility geography applied to all ", nrow(data), " visits in `",
        paste(output_cols, collapse = "`/`"), "`."
      )
    )
  }
}
