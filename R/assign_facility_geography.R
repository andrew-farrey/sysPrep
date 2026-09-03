
# assign_facility_geography() ----
#' Assign facility geography to all visits for incidence-at-location analysis
#'
#' Writes the treating hospital's corresponding geographic fields
#' (`HospitalRegion` and/or `HospitalZip`) to `new_region_col`/`new_zip_col`
#' for **all** visits, regardless of patient residence. By default this
#' writes new columns (`region_facility`/`zip_code_facility`), leaving
#' `Region`/`ZipCode` untouched; set `overwrite = TRUE` to overwrite them in
#' place instead. This scopes geography to true incidence-at-location (to
#' the extent NSSP ESSENCE supports it) by attributing every visit to
#' where care was received rather than where the patient resides.
#'
#' @details
#' ## Why this function exists
#' [assign_treating_geography()] selectively reassigns geography only for
#' out-of-state and `OTHER_REGION` visits, preserving residential geography
#' for in-state patients: a hybrid approach. `assign_facility_geography()`
#' applies reassignment universally: all visits, including in-state patients,
#' receive the treating facility's geography. This produces a dataset scoped
#' entirely to incidence-at-location rather than patient residence.
#'
#' This is functionally equivalent to renaming `HospitalRegion` to `Region`
#' and `HospitalZip` to `ZipCode`, but operates on the existing data structure
#' without column renaming or pipeline restructuring, preserving compatibility
#' with downstream functions that expect `Region` and `ZipCode` by name.
#'
#' ## Incidence-at-location scoping and region-level cluster detection
#' Assigning facility geography to all visits bins every visit to the region
#' in which the treating facility is located, regardless of how many hospitals
#' that region contains. This is a deliberate design choice with two advantages
#' over true hospital-level cluster detection:
#'
#' - **Reduces urban-hospital bias.** Urban regions typically contain more
#'   hospitals than rural regions. Hospital-level scan statistics can evaluate
#'   clusters across individual facility locations, but they generally do not
#'   explicitly model residual spatial autocorrelation or facility-specific
#'   reporting patterns as nuisance structure. In prospective surveillance,
#'   scanning windows may therefore interact with hospital density, catchment
#'   patterns, and data submission variability in ways that can produce apparent
#'   clusters independent of true changes in underlying incidence. This concern
#'   is more pronounced in urban areas where hospitals are denser and submission
#'   patterns may vary across nearby facilities. Region-level binning does not
#'   eliminate this concern, but it reduces facility-level noise by aggregating
#'   across treating facilities within a region rather than treating each
#'   hospital as an independent spatial unit.
#'
#' - **No Master Facility Table lookup required.** Hospital-level spatial
#'   clustering requires latitude/longitude coordinates sourced from the NSSP
#'   Master Facility Table, an additional logistical step outside the standard
#'   ESSENCE data pull. Region-level binning achieves a close approximation of
#'   hospital-level cluster detection using `HospitalRegion`/`HospitalZip`
#'   instead, provided they're included in the pull. Neither is guaranteed
#'   by default; both require being part of your site's default returned
#'   columns or explicitly requested via the API's `&field=` parameter.
#'
#' One consequence of region-level attribution is that detectable cluster
#' polygons are limited to regions that contain at least one participating
#' ESSENCE facility. Regions with no participating hospitals cannot contribute
#' counts and will not appear as cluster candidates, regardless of actual
#' burden in those areas. This is not unique to this approach; it is a
#' general property of facility-based surveillance, but it is worth noting
#' explicitly when interpreting spatial cluster output.
#'
#' This method is currently being evaluated for adoption as an additional
#' scan statistic pipeline for daily prospective overdose surveillance in
#' Kentucky, complementing the hybrid approach implemented in
#' [assign_treating_geography()].
#'
#' ## Use cases
#' - Spatial cluster detection scoped to where patients received care rather
#'   than where they live.
#' - Incidence-at-location burden estimation irrespective of patient origin.
#' - Approximating hospital-level cluster detection without Master Facility
#'   Table lookups or coordinate-based spatial methods.
#' - Comparing total treated volume across urban and rural counties without
#'   differentiating which specific hospital saw each visit, useful when a
#'   facility-to-county lookup table isn't available but `HospitalRegion`/
#'   `HospitalZip` already are. The tradeoff is the one described above: a
#'   county with no participating ESSENCE facility always shows `0`,
#'   regardless of actual resident burden.
#'
#' ## ESSENCE Region field and facility location pulls
#' `HospitalRegion`, like `Region`, is drawn from a maintained zip-to-county
#' mapping rather than a live geocode: by default assigned from the
#' facility's zip code centroid, though site administrators can override
#' this via BioSense Access Management to instead reflect the facility's
#' listed county. `Region`-based output should not be construed as an
#' authoritative county-level count for either patient or facility geography.
#'
#' This function's output is best understood as approximating an ESSENCE
#' **facility location** pull (`va_hosp`): every row is scoped to where care
#' was received, so the resulting population is a combination of
#' jurisdiction residents and visitors who presented at in-jurisdiction
#' facilities. This differs from a **patient location** pull (`va_er`),
#' which [assign_treating_geography()] is closer to preserving; see that
#' function's documentation for the same caveat on `Region` field
#' interpretation.
#'
#' ## Geography types and output columns
#' Both region and zip are attempted by default (`new_region_col` and
#' `new_zip_col` both default to a column name). Pass `NULL` to either to
#' skip that type entirely. If the source columns required for a requested
#' type are absent, that type is skipped with an informative message.
#'
#' By default, results are written to new columns (`region_facility`/
#' `zip_code_facility`), and `region_col`/`zip_col` are never modified. To
#' overwrite `region_col`/`zip_col` in place instead (the only behavior this
#' function had before this parameter existed), pass their own name to
#' `new_region_col`/`new_zip_col` and set `overwrite = TRUE`. `overwrite`
#' guards **any** collision with an existing column, not just the source
#' column; see [assign_treating_geography()]'s documentation for the full
#' behavior, which is identical here.
#'
#' ## Preserved geographies
#' `preserve_original_geographies` only has an effect in `overwrite = TRUE`
#' mode; see [assign_treating_geography()]. When it does apply here, since
#' all rows are reassigned, `original_region`/`original_zip_code` retain the
#' original patient residential geography for every visit, enabling
#' residential vs. treating geography comparisons in a single dataset.
#'
#' @param data A data frame of ESSENCE visit-level records, typically the
#'   output of [dedupe()] and [filter_care_setting()].
#' @param region_col <[`tidy-select`][dplyr::dplyr_tidy_select]> Unquoted
#'   column name for the patient region field. Defaults to `Region`.
#' @param hospital_region_col <[`tidy-select`][dplyr::dplyr_tidy_select]>
#'   Unquoted column name for the hospital region field. Defaults to
#'   `HospitalRegion`. Required when `new_region_col` is not `NULL`.
#' @param zip_col <[`tidy-select`][dplyr::dplyr_tidy_select]> Unquoted
#'   column name for the patient zip code field. Defaults to `ZipCode`.
#'   Required when `new_zip_col` is not `NULL`.
#' @param hospital_zip_col <[`tidy-select`][dplyr::dplyr_tidy_select]>
#'   Unquoted column name for the hospital zip code field. Defaults to
#'   `HospitalZip`. Required when `new_zip_col` is not `NULL`.
#' @param new_region_col Character string or `NULL`. Name of the column to
#'   write facility region values to. Defaults to `"region_facility"`: a
#'   new column, leaving `region_col` untouched. Pass `NULL` to skip region
#'   entirely. Pass `region_col`'s own name (with `overwrite = TRUE`) to
#'   overwrite it in place instead. See Details.
#' @param new_zip_col Character string or `NULL`. Name of the column to
#'   write facility zip code values to. Defaults to `"zip_code_facility"`.
#'   Same behavior as `new_region_col`, independently, for zip.
#' @param overwrite Logical. If `FALSE` (default), `new_region_col`/
#'   `new_zip_col` naming a column that already exists in `data` aborts
#'   rather than silently overwriting it. Set `TRUE` to allow it; this is
#'   required to reproduce the original in-place-overwrite behavior. See
#'   Details.
#' @param preserve_original_geographies Logical. If `TRUE`, adds
#'   `original_region` and/or `original_zip_code` columns before
#'   overwriting. Only has an effect when `overwrite = TRUE`. Defaults to
#'   `FALSE`.
#' @param clean_names Logical. If `TRUE` (default), applies
#'   [janitor::clean_names()] on output.
#' @param verbose Logical. If `FALSE`, suppresses informational messages
#'   (`rlang::inform()`); warnings and errors are always shown regardless.
#'
#' @return The input data frame with facility region and/or zip code values
#'   written to `new_region_col`/`new_zip_col` (or to `region_col`/
#'   `zip_col` in place, when `overwrite = TRUE`) for all rows. A
#'   `.facility_geography` logical column set to `TRUE` for all rows signals
#'   that facility geography has been applied. When `overwrite = TRUE` and
#'   `preserve_original_geographies = TRUE`, `original_region` and/or
#'   `original_zip_code` columns are also present.
#'
#' @examples
#' # Build a deduplicated, filtered base to demonstrate on: essence_clean
#' # itself already has region_hybrid/region_facility applied, so it isn't a
#' # fresh starting point for these examples
#' ed_clean <- essence_raw |>
#'   dedupe(order_by = Arrived_Date_Time) |>
#'   filter_care_setting()
#'
#' # Default: new region_facility/zip_code_facility columns for all visits;
#' # region/zip_code themselves are never touched
#' ed_clean |> assign_facility_geography()
#'
#' # Overwrite region/zip_code in place (the original behavior); requires
#' # naming the source columns explicitly and opting in with overwrite
#' ed_clean |>
#'   assign_facility_geography(
#'     new_region_col = "region",
#'     new_zip_col     = "zip_code",
#'     overwrite       = TRUE,
#'     preserve_original_geographies = TRUE
#'   ) |>
#'   dplyr::mutate(
#'     patient_differs_from_facility = region != original_region
#'   )
#'
#' # Facility geography for cluster detection, alongside the hybrid approach
#' ed_clean |>
#'   assign_treating_geography() |>
#'   assign_facility_geography()
#'
#' @seealso [assign_treating_geography()] for selective reassignment of
#'   out-of-state visits only.
#' @export
assign_facility_geography <- function(data,
                                      region_col                    = Region,
                                      hospital_region_col           = HospitalRegion,
                                      zip_col                       = ZipCode,
                                      hospital_zip_col              = HospitalZip,
                                      new_region_col                = "region_facility",
                                      new_zip_col                   = "zip_code_facility",
                                      overwrite                     = FALSE,
                                      preserve_original_geographies = FALSE,
                                      clean_names                   = TRUE,
                                      verbose                       = TRUE) {

  # Normalize names ----
  data <- clean_names_safe(data)

  # Resolve source columns gracefully ----
  region_sym      <- resolve_col_optional(data, rlang::ensym(region_col))
  hosp_region_sym <- resolve_col_optional(data, rlang::ensym(hospital_region_col))
  zip_sym         <- resolve_col_optional(data, rlang::ensym(zip_col))
  hosp_zip_sym    <- resolve_col_optional(data, rlang::ensym(hospital_zip_col))

  region_col_str      <- if (!is.null(region_sym))      rlang::as_string(region_sym)
  hosp_region_col_str <- if (!is.null(hosp_region_sym)) rlang::as_string(hosp_region_sym)
  zip_col_str         <- if (!is.null(zip_sym))         rlang::as_string(zip_sym)
  hosp_zip_col_str    <- if (!is.null(hosp_zip_sym))    rlang::as_string(hosp_zip_sym)

  # Which geography types to process is driven directly by new_region_col/
  # new_zip_col: NULL skips that type entirely ----
  do_region <- !is.null(new_region_col)
  do_zip    <- !is.null(new_zip_col)

  geog_flags <- validate_geography_cols(
    verbose, do_region, do_zip,
    region_col_str, hosp_region_col_str,
    zip_col_str, hosp_zip_col_str
  )
  do_region <- geog_flags$do_region
  do_zip    <- geog_flags$do_zip

  if (!do_region && !do_zip) {
    rlang::warn("No geography types could be processed. Returning data unchanged.")
    return(if (clean_names) clean_names_safe(data) else data)
  }

  # Resolve output columns: aborts on a reserved-name collision, or on an
  # existing-column collision unless overwrite = TRUE. By default
  # new_region_col/new_zip_col name new columns, leaving region_col/zip_col
  # untouched; passing the source column's own name plus overwrite = TRUE
  # reproduces the original in-place-overwrite behavior ----
  region_output_col_str <- if (do_region) {
    resolve_geography_output_col(
      new_region_col, data, overwrite, ".facility_geography", "new_region_col"
    )
  } else {
    NULL
  }
  zip_output_col_str <- if (do_zip) {
    resolve_geography_output_col(
      new_zip_col, data, overwrite, ".facility_geography", "new_zip_col"
    )
  } else {
    NULL
  }

  region_target_exists <- do_region && region_output_col_str %in% names(data)
  zip_target_exists    <- do_zip    && zip_output_col_str    %in% names(data)

  # Preserve original geographies (only meaningful when the target already
  # held a value, i.e. overwrite = TRUE was used) and reassign all rows with
  # facility geography (mask = all rows, since this function is universal) ----
  data <- assign_geography_reassignment(
    data, do_region, do_zip,
    region_col_str, hosp_region_col_str,
    zip_col_str, hosp_zip_col_str,
    region_output_col_str, zip_output_col_str,
    region_target_exists, zip_target_exists,
    preserve_original_geographies,
    mask = rep(TRUE, nrow(data))
  )

  data <- dplyr::mutate(data, .facility_geography = TRUE)

  output_cols <- c(region_output_col_str, zip_output_col_str)

  if (nrow(data) == 0L) {
    inform_if(verbose, "No rows in data after processing. Returning empty data frame.")
  } else {
    inform_if(
      verbose,
      paste0(
        "Facility geography applied to all ", nrow(data), " visits in `",
        paste(output_cols, collapse = "`/`"), "`."
      )
    )
  }

  if (clean_names) clean_names_safe(data) else data
}
