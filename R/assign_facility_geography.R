
# assign_facility_geography() ----
#' Assign facility geography to all visits for incidence-at-location analysis
#'
#' Overwrites `Region` and/or `ZipCode` with the treating hospital's
#' corresponding geographic fields (`HospitalRegion` and/or `HospitalZip`)
#' for **all** visits, regardless of patient residence. This scopes geography
#' to true incidence-at-location (to the extent NSSP ESSENCE supports it) --
#' by attributing every visit to where care was received rather than where the
#' patient resides.
#'
#' @details
#' ## Why this function exists
#' [assign_treating_geography()] selectively reassigns geography only for
#' out-of-state and `OTHER_REGION` visits, preserving residential geography
#' for in-state patients -- a hybrid approach. `assign_facility_geography()`
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
#'   hospital-level cluster detection using fields already present in the pull.
#'
#' One consequence of region-level attribution is that detectable cluster
#' polygons are limited to regions that contain at least one participating
#' ESSENCE facility. Regions with no participating hospitals cannot contribute
#' counts and will not appear as cluster candidates, regardless of actual
#' burden in those areas. This is not unique to this approach -- it is a
#' general property of facility-based surveillance -- but it is worth noting
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
#'
#' ## ESSENCE Region field and facility location pulls
#' `HospitalRegion`, like `Region`, is drawn from a maintained zip-to-county
#' mapping rather than a live geocode -- by default assigned from the
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
#' which [assign_treating_geography()] is closer to preserving -- see that
#' function's documentation for the same caveat on `Region` field
#' interpretation.
#'
#' ## Preserved geographies
#' When `preserve_original_geographies = TRUE`, `original_region` and/or
#' `original_zip_code` columns are added before overwriting. Since all rows
#' are reassigned, these columns retain the original patient residential
#' geography for all visits -- enabling residential vs. treating geography
#' comparisons in a single dataset.
#'
#' @param data A data frame of ESSENCE visit-level records, typically the
#'   output of [dedupe()] and [filter_care_setting()].
#' @param geography Character vector. Which geography types to reassign.
#'   One or both of `"region"` and `"zip"`. Defaults to
#'   `c("region", "zip")`. Types with missing required columns are skipped
#'   with an informative message.
#' @param region_col <[`tidy-select`][dplyr::dplyr_tidy_select]> Unquoted
#'   column name for the patient region field. Defaults to `Region`.
#' @param hospital_region_col <[`tidy-select`][dplyr::dplyr_tidy_select]>
#'   Unquoted column name for the hospital region field. Defaults to
#'   `HospitalRegion`.
#' @param zip_col <[`tidy-select`][dplyr::dplyr_tidy_select]> Unquoted
#'   column name for the patient zip code field. Defaults to `ZipCode`.
#' @param hospital_zip_col <[`tidy-select`][dplyr::dplyr_tidy_select]>
#'   Unquoted column name for the hospital zip code field. Defaults to
#'   `HospitalZip`.
#' @param preserve_original_geographies Logical. If `TRUE`, adds
#'   `original_region` and/or `original_zip_code` columns before
#'   overwriting. Defaults to `FALSE`.
#' @param clean_names Logical. If `TRUE` (default), applies
#'   [janitor::clean_names()] on output.
#' @param verbose Logical. If `FALSE`, suppresses informational messages
#'   (`rlang::inform()`); warnings and errors are always shown regardless.
#'
#' @return The input data frame with `Region` and/or `ZipCode` overwritten
#'   with hospital geography for all rows. A `.facility_geography` logical
#'   column set to `TRUE` for all rows signals that facility geography has
#'   been applied. When `preserve_original_geographies = TRUE`,
#'   `original_region` and/or `original_zip_code` columns are also present.
#'
#' @examples
#' # Default: overwrite both region and zip for all visits
#' essence_clean |> assign_facility_geography()
#'
#' # Preserve residential geography for comparison
#' essence_clean |>
#'   assign_facility_geography(preserve_original_geographies = TRUE) |>
#'   dplyr::mutate(
#'     patient_differs_from_facility = region != original_region
#'   )
#'
#' # Facility geography for cluster detection
#' essence_raw |>
#'   dedupe(order_by = Arrived_Date_Time) |>
#'   filter_care_setting() |>
#'   assign_facility_geography(preserve_original_geographies = TRUE)
#'
#' @seealso [assign_treating_geography()] for selective reassignment of
#'   out-of-state visits only.
#' @export
assign_facility_geography <- function(data,
                                      geography                     = c("region", "zip"),
                                      region_col                    = Region,
                                      hospital_region_col           = HospitalRegion,
                                      zip_col                       = ZipCode,
                                      hospital_zip_col              = HospitalZip,
                                      preserve_original_geographies = FALSE,
                                      clean_names                   = TRUE,
                                      verbose                       = TRUE) {

  geography <- match.arg(geography, choices = c("region", "zip"),
                         several.ok = TRUE)

  # Normalize names ----
  data <- clean_names_safe(data)

  # Resolve columns gracefully ----
  region_sym      <- resolve_col_optional(data, rlang::ensym(region_col))
  hosp_region_sym <- resolve_col_optional(data, rlang::ensym(hospital_region_col))
  zip_sym         <- resolve_col_optional(data, rlang::ensym(zip_col))
  hosp_zip_sym    <- resolve_col_optional(data, rlang::ensym(hospital_zip_col))

  region_col_str      <- if (!is.null(region_sym))      rlang::as_string(region_sym)
  hosp_region_col_str <- if (!is.null(hosp_region_sym)) rlang::as_string(hosp_region_sym)
  zip_col_str         <- if (!is.null(zip_sym))         rlang::as_string(zip_sym)
  hosp_zip_col_str    <- if (!is.null(hosp_zip_sym))    rlang::as_string(hosp_zip_sym)

  do_region <- "region" %in% geography
  do_zip    <- "zip"    %in% geography

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

  # Preserve original geographies and overwrite all rows with facility
  # geography (mask = all rows, since this function is universal) ----
  data <- assign_geography_reassignment(
    data, do_region, do_zip,
    region_col_str, hosp_region_col_str,
    zip_col_str, hosp_zip_col_str,
    preserve_original_geographies,
    mask = rep(TRUE, nrow(data))
  )

  data <- dplyr::mutate(data, .facility_geography = TRUE)

  geog_applied <- c(
    if (do_region) "region" else NULL,
    if (do_zip)    "zip"    else NULL
  )

  if (nrow(data) == 0L) {
    inform_if(verbose, "No rows in data after processing. Returning empty data frame.")
  } else {
    inform_if(
      verbose,
      paste0(
        "Facility geography applied to all ", nrow(data), " visits (",
        paste(geog_applied, collapse = " and "), ")."
      )
    )
  }

  if (clean_names) clean_names_safe(data) else data
}
