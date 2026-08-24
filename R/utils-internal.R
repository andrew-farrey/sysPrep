
# Internal helpers ----
# These functions are not exported. They support consistent column name
# resolution across all sysPrep functions, accepting both raw ESSENCE column
# names (e.g., HospitalName) and post-janitor::clean_names() equivalents
# (e.g., hospital_name) without requiring the user to know which form is
# present in their data.

# resolve_col() ----
# Resolves a user-supplied column symbol to the actual column name present
# in the data using snake_case normalization on both sides. Aborts with an
# informative error if the column cannot be found.
resolve_col <- function(data, col_sym) {

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
    paste0(
      "Column '", col_str, "' not found in data. ",
      "Tried direct match and snake_case normalization. ",
      "Available columns: ", paste(nms, collapse = ", ")
    )
  )
}

# resolve_col_optional() ----
# Like resolve_col(), but returns NULL instead of aborting when the column
# is not found. Used by functions that degrade gracefully when optional
# columns are absent (e.g., geography functions when HospitalZip is not pulled).
resolve_col_optional <- function(data, col_sym) {
  tryCatch(
    resolve_col(data, col_sym),
    error = function(e) NULL
  )
}

# resolve_col_str() ----
# Convenience wrapper around resolve_col() for the common case where the
# resolved column is needed as a string (e.g. for .data[[...]] subsetting)
# rather than as a symbol.
resolve_col_str <- function(data, col_sym) {
  rlang::as_string(resolve_col(data, col_sym))
}

# clean_names_safe() ----
# Like janitor::clean_names() but preserves leading-dot prefixes on column
# names. janitor::clean_names() strips leading dots (e.g. `.index_encounter`
# becomes `index_encounter`), which breaks references to sysPrep metadata
# columns added by link_encounters(), assign_treating_geography(), etc.
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

# inform_if() ----
# Emits an rlang::inform() message only when verbose is TRUE. Used by
# functions with a `verbose` parameter to gate informational (non-fatal,
# non-warning) console messages -- rlang::warn()/rlang::abort() calls are
# never routed through this helper and always fire regardless of verbose.
inform_if <- function(verbose, ...) {
  if (verbose) rlang::inform(...)
}

# validate_geography_cols() ----
# Shared by assign_treating_geography() and assign_facility_geography():
# downgrades do_region/do_zip to FALSE (with an informative message) when a
# column required for that geography type is absent. `check_region_col`
# controls whether `region_col_str` itself is validated here --
# assign_treating_geography() validates it separately afterward since it is
# unconditionally required there for out-of-state detection, regardless of
# `geography`; assign_facility_geography() has no such separate requirement,
# so it validates region_col_str as part of this check.
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

# apply_type_correction() ----
# Shared by filter_care_setting()'s facility ID, facility name, and regex
# correction blocks: overwrites `type_col_str` with `fix_to` for rows
# matching `mask`, leaving other rows unchanged.
apply_type_correction <- function(data, type_col_str, mask, fix_to) {
  dplyr::mutate(
    data,
    "{type_col_str}" := dplyr::if_else(mask, fix_to, .data[[type_col_str]])
  )
}

# cli_duplicate_ids_footer() ----
# Shared by print.essence_dup_summary() and print.essence_dup_classified():
# renders the identical "$duplicate_ids" access footer for both.
cli_duplicate_ids_footer <- function(x) {
  cli::cli_h2("Duplicated Visit IDs")
  cli::cli_text(
    "{nrow(x$duplicate_ids)} facility \u00d7 Visit_ID pair(s) with >1 row. ",
    "Access via $duplicate_ids."
  )
}

# resolve_geography_output_col() ----
# Shared by assign_treating_geography() and assign_facility_geography():
# resolves a `new_region_col`/`new_zip_col` argument (a plain character
# string naming the output column, or NULL to skip that geography type
# entirely) to its clean_names()-normalized form. Aborts if the resolved
# name collides with `reserved_col` -- the bookkeeping column
# (`.out_of_state`/`.facility_geography`) the calling function itself adds,
# which would silently break the return-value contract callers rely on.
# `reserved_col` is passed dot-prefixed (matching how it's referenced
# everywhere else), but janitor::make_clean_names() -- unlike
# clean_names_safe() -- has no dot-preservation logic and always strips a
# leading dot, so the comparison strips it from `reserved_col` too rather
# than comparing directly.
# Aborts if the resolved name already exists as a column in `data` unless
# `overwrite = TRUE` -- this is what makes writing to a new column
# non-destructive by default and requires an explicit, visible opt-in
# (`overwrite = TRUE`) before any existing column (the source column
# itself, or any other) can be silently clobbered.
resolve_geography_output_col <- function(new_col, data, overwrite,
                                         reserved_col, arg_name) {
  if (is.null(new_col)) return(NULL)

  output_col_str <- janitor::make_clean_names(new_col)

  if (identical(output_col_str, sub("^\\.", "", reserved_col))) {
    rlang::abort(
      paste0(
        "`", arg_name, " = \"", new_col, "\"` collides with `",
        reserved_col, "`, the bookkeeping column this function adds. ",
        "Choose a different column name."
      )
    )
  }

  if (output_col_str %in% names(data) && !overwrite) {
    rlang::abort(
      paste0(
        "Column `", output_col_str, "` already exists in `data`. Set ",
        "`overwrite = TRUE` to overwrite it, or choose a different `",
        arg_name, "` value."
      )
    )
  }

  output_col_str
}

# assign_geography_reassignment() ----
# Shared by assign_treating_geography() and assign_facility_geography():
# applies the "preserve original values, then reassign from hospital
# columns" logic common to both. `mask` is a logical vector (same length as
# nrow(data)) marking which rows get reassigned -- assign_treating_geography()
# passes `.out_of_state` (selective); assign_facility_geography() passes an
# all-TRUE vector (universal).
#
# `region_output_col_str`/`zip_output_col_str` are the resolved target
# column names from resolve_geography_output_col() above -- by default a
# new column distinct from `region_col_str`/`zip_col_str` (source left
# untouched), or the source column itself when `overwrite = TRUE` was used
# to opt into in-place overwrite. `region_target_exists`/`zip_target_exists`
# indicate whether that target already held a value before this call (which
# resolve_geography_output_col() only allows when `overwrite = TRUE`) --
# `preserve_original_geographies`'s `original_region`/`original_zip_code`
# columns are only added when the target already existed, since writing to
# a genuinely new column already leaves the original untouched and a copy
# would be redundant. `original_region`/`original_zip_code` are only
# populated (non-NA) for rows where `mask` is TRUE, so "unmodified row" is
# always identifiable via `is.na(original_region)` regardless of caller.
assign_geography_reassignment <- function(data, do_region, do_zip,
                                          region_col_str, hosp_region_col_str,
                                          zip_col_str, hosp_zip_col_str,
                                          region_output_col_str, zip_output_col_str,
                                          region_target_exists, zip_target_exists,
                                          preserve_original_geographies,
                                          mask) {

  if (preserve_original_geographies) {
    if (region_target_exists) {
      data <- dplyr::mutate(
        data,
        original_region = dplyr::if_else(mask, .data[[region_output_col_str]], NA)
      )
    }
    if (zip_target_exists) {
      data <- dplyr::mutate(
        data,
        original_zip_code = dplyr::if_else(mask, .data[[zip_output_col_str]], NA)
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
