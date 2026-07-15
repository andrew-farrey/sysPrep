
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

# assign_geography_reassignment() ----
# Shared by assign_treating_geography() and assign_facility_geography():
# applies the "preserve original values, then reassign from hospital
# columns" logic common to both. `mask` is a logical vector (same length as
# nrow(data)) marking which rows get reassigned -- assign_treating_geography()
# passes `.out_of_state` (selective); assign_facility_geography() passes an
# all-TRUE vector (universal). `original_region`/`original_zip_code` are only
# populated (non-NA) for rows where `mask` is TRUE, so "unmodified row" is
# always identifiable via `is.na(original_region)` regardless of caller.
assign_geography_reassignment <- function(data, do_region, do_zip,
                                          region_col_str, hosp_region_col_str,
                                          zip_col_str, hosp_zip_col_str,
                                          preserve_original_geographies,
                                          mask) {

  if (preserve_original_geographies) {
    if (do_region) {
      data <- dplyr::mutate(
        data,
        original_region = dplyr::if_else(mask, .data[[region_col_str]], NA)
      )
    }
    if (do_zip) {
      data <- dplyr::mutate(
        data,
        original_zip_code = dplyr::if_else(mask, .data[[zip_col_str]], NA)
      )
    }
  }

  if (do_region) {
    data <- dplyr::mutate(
      data,
      "{region_col_str}" := dplyr::if_else(
        mask, .data[[hosp_region_col_str]], .data[[region_col_str]]
      )
    )
  }

  if (do_zip) {
    data <- dplyr::mutate(
      data,
      "{zip_col_str}" := dplyr::if_else(
        mask, .data[[hosp_zip_col_str]], .data[[zip_col_str]]
      )
    )
  }

  data
}
