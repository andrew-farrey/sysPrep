
# assign_treating_geography() ----
#' Assign treating facility geography to out-of-state and OTHER_REGION visits
#'
#' Identifies visits where the patient's recorded `Region` does not belong to
#' the site of interest -- including out-of-state residents and visits with
#' `OTHER_REGION` or missing `Region` values -- and replaces their `Region`
#' and/or `ZipCode` with the treating hospital's corresponding geographic
#' fields (`HospitalRegion` and/or `HospitalZip`). In-state patient visits
#' are left unchanged.
#'
#' @details
#' ## Why this function exists
#' ESSENCE surveillance data includes visits from out-of-state residents and
#' patients whose legal address is unavailable to the treating facility
#' (`OTHER_REGION`). Simply discarding these visits understates the true
#' incidence burden experienced by facilities in the surveillance area.
#' Assigning the treating facility's geography to these visits retains them
#' in the analytic dataset while approximating both residence-based and
#' incidence-based burden from a single geographic field.
#'
#' ## Site prefix detection
#' The `Region` field uses the format `{SITE}_{REGION}`, where `SITE` is
#' the NSSP Site Short Name and `REGION` is the ESSENCE Region -- a county
#' name derived from a zip-code-to-county lookup table maintained by
#' ESSENCE. Because some site names contain multiple underscores, the
#' prefix is all characters before the **last** underscore. A visit is
#' classified as out-of-state when its
#' `Region` does not begin with `paste0(site, "_")`, or when `Region` is
#' `"OTHER_REGION"` or `NA`. For example, with `site = "KY"`:
#' - `"KY_Jefferson"` -> in-state, unchanged
#' - `"TN_Davidson"` -> out-of-state, region assigned from `HospitalRegion`
#' - `"OTHER_REGION"` -> unknown residence, region assigned from `HospitalRegion`
#'
#' ## Geography types
#' Both `"region"` and `"zip"` are attempted by default. If the columns
#' required for a geography type are absent, that type is skipped with an
#' informative message. Specify `geography = "region"` or `geography = "zip"`
#' explicitly to suppress messages about the other type when columns are
#' intentionally absent.
#'
#' ## Hybrid geography assignment and cluster detection
#' This function implements a hybrid geography assignment strategy: in-state
#' patient residential geography is preserved unchanged, while out-of-state
#' and `OTHER_REGION` visits are attributed to the treating facility's
#' geography rather than discarded. This matters for cluster detection: a
#' geographically concentrated surge of out-of-state overdoses at a single
#' facility -- common near state borders or in tourist destinations -- will
#' appear in facility-level and county-level signals only if those visits
#' are attributed to the treating location. Discarding them suppresses the
#' signal entirely.
#'
#' Because residential geography is preserved for the in-state majority,
#' the resulting dataset behaves similarly to what most ESSENCE practitioners
#' expect from a standard query, with out-of-state and `OTHER_REGION` visits
#' retained rather than dropped. This makes `assign_treating_geography()` the
#' more conservative of the two geography assignment methods in this package
#' and the recommended starting point for most surveillance applications.
#' This approach is implemented at scale in Kentucky's statewide syndromic
#' overdose alert system.
#'
#' The tradeoff is mixed semantics in the `Region` column: it represents
#' residential geography for most rows and treating-location geography for
#' reassigned rows. Analytic notes should document this when reporting rates.
#'
#' ## ESSENCE Region field
#' `Region` is a formal ESSENCE geographic entity mapped relationally to a
#' county-to-zip code lookup table in the NSSP BioSense database, representing
#' the patient's approximated county of residence. It is the preferred geography
#' for county-level burden estimation. Custom region fields supplied to NSSP by
#' states (e.g., health planning districts, local health department districts,
#' community mental health center service areas) are pre-computed from `Region`
#' and would need to be recomputed after reassignment if used downstream.
#' Because the underlying lookup table is not publicly accessible, this function
#' does not support reassigning NSSP-site-submitted custom region fields.
#'
#' `Region` is a maintained many-to-one zip-to-county mapping
#' (`Zipcode_to_CountyRegionMapping`), not a live geocode of the record --
#' zip codes are assigned to a region by centroid by default, but individual
#' assignments may be overridden by site or state administrators to better
#' reflect where the bulk of a zip code's population lives. Because of this
#' approximation, `Region`-based results should not be construed as the
#' authoritative county-level count; they are ESSENCE's standardized
#' construct for enabling consistent sub-state reporting across data
#' sources, not ground truth. This function reassigns `Region` using
#' whatever mapping is already present in `HospitalRegion` -- it does not
#' independently geocode or validate that mapping.
#'
#' `essence_raw`/`essence_clean` and the examples throughout this package
#' model an ESSENCE **patient location** pull (`va_er`), where `Region`
#' reflects patient residence for the jurisdiction of interest. In a
#' **facility location** pull (`va_hosp`), the population represented
#' includes both residents and visitors who presented for care at
#' in-jurisdiction facilities -- `assign_facility_geography()` is the
#' more natural fit for that data source, since it scopes every row to
#' where care was received rather than mixing residence-based and
#' visitor rows under one semantic.
#'
#' ## Preserved geographies
#' When `preserve_original_geographies = TRUE`, `original_region` and/or
#' `original_zip_code` columns are added before overwriting, retaining
#' pre-assignment values for QA, audit trails, or residential vs. treating
#' geography comparisons.
#'
#' @param data A data frame of ESSENCE visit-level records, typically the
#'   output of [dedupe()] and [filter_care_setting()].
#' @param site Character string. The site prefix used to identify in-state
#'   visits. Defaults to `"KY"`. Visits whose `Region` does not begin with
#'   `paste0(site, "_")` are treated as out-of-state.
#' @param geography Character vector. Which geography types to reassign.
#'   One or both of `"region"` and `"zip"`. Defaults to
#'   `c("region", "zip")`. Types with missing required columns are skipped
#'   with an informative message.
#' @param region_col <[`tidy-select`][dplyr::dplyr_tidy_select]> Unquoted
#'   column name for the patient region field. Defaults to `Region`.
#' @param hospital_region_col <[`tidy-select`][dplyr::dplyr_tidy_select]>
#'   Unquoted column name for the hospital region field. Defaults to
#'   `HospitalRegion`. Required when `"region"` is in `geography`.
#' @param zip_col <[`tidy-select`][dplyr::dplyr_tidy_select]> Unquoted
#'   column name for the patient zip code field. Defaults to `ZipCode`.
#'   Required when `"zip"` is in `geography`.
#' @param hospital_zip_col <[`tidy-select`][dplyr::dplyr_tidy_select]>
#'   Unquoted column name for the hospital zip code field. Defaults to
#'   `HospitalZip`. Required when `"zip"` is in `geography`.
#' @param preserve_original_geographies Logical. If `TRUE`, adds
#'   `original_region` and/or `original_zip_code` columns containing
#'   pre-overwrite values before reassignment. Defaults to `FALSE`.
#' @param clean_names Logical. If `TRUE` (default), applies
#'   [janitor::clean_names()] on output.
#' @param verbose Logical. If `FALSE`, suppresses informational messages
#'   (`rlang::inform()`); warnings and errors are always shown regardless.
#'
#' @return The input data frame with `Region` and/or `ZipCode` reassigned for
#'   out-of-state and `OTHER_REGION` visits. A `.out_of_state` logical column
#'   is added indicating which rows were reassigned. When
#'   `preserve_original_geographies = TRUE`, `original_region` and/or
#'   `original_zip_code` columns are also present.
#'
#' @examples
#' # Default: reassign both region and zip for out-of-state visits
#' essence_clean |> assign_treating_geography()
#'
#' # Region only -- ZipCode not in pull
#' essence_clean |> assign_treating_geography(geography = "region")
#'
#' # Non-Kentucky site
#' essence_clean |> assign_treating_geography(site = "OH")
#'
#' # Preserve original values for QA
#' essence_clean |>
#'   assign_treating_geography(preserve_original_geographies = TRUE) |>
#'   dplyr::filter(region != original_region)
#'
#' # Full pipeline
#' essence_raw |>
#'   dedupe(order_by = Arrived_Date_Time) |>
#'   filter_care_setting() |>
#'   assign_treating_geography(preserve_original_geographies = TRUE)
#'
#' @seealso [assign_facility_geography()] to assign facility geography to
#'   all visits regardless of patient residence.
#' @export
assign_treating_geography <- function(data,
                                      site                          = "KY",
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

  # Validate region geography ----
  if (do_region && is.null(hosp_region_col_str)) {
    inform_if(verbose, "Region geography skipped: `HospitalRegion` not found in data.")
    do_region <- FALSE
  }

  # Validate zip geography ----
  if (do_zip) {
    if (is.null(zip_col_str)) {
      inform_if(verbose, "Zip geography skipped: `ZipCode` not found in data.")
      do_zip <- FALSE
    } else if (is.null(hosp_zip_col_str)) {
      inform_if(verbose, "Zip geography skipped: `HospitalZip` not found in data.")
      do_zip <- FALSE
    }
  }

  # Region column required for out-of-state detection ----
  if (is.null(region_col_str)) {
    rlang::abort(
      paste0(
        "`Region` (or `region`) is required for out-of-state visit detection ",
        "regardless of `geography` type. Ensure `Region` is included as a ",
        "field in your ESSENCE API pull."
      )
    )
  }

  if (!do_region && !do_zip) {
    rlang::warn(
      "No geography types could be processed. Returning data unchanged."
    )
    return(if (clean_names) clean_names_safe(data) else data)
  }

  # Identify out-of-state / OTHER_REGION visits ----
  site_prefix <- paste0(site, "_")

  data <- data |>
    dplyr::mutate(
      .out_of_state = is.na(.data[[region_col_str]]) |
        .data[[region_col_str]] == "OTHER_REGION" |
        !stringr::str_starts(
          .data[[region_col_str]],
          stringr::fixed(site_prefix)
        )
    )

  # Preserve original geographies (out-of-state rows only) and reassign ----
  data <- assign_geography_reassignment(
    data, do_region, do_zip,
    region_col_str, hosp_region_col_str,
    zip_col_str, hosp_zip_col_str,
    preserve_original_geographies,
    mask = data$.out_of_state
  )

  n_reassigned <- sum(data$.out_of_state, na.rm = TRUE)
  n_total      <- nrow(data)

  if (n_total == 0L) {
    inform_if(verbose, "No rows in data after processing. Returning empty data frame.")
  } else {
    inform_if(
      verbose,
      paste0(
        n_reassigned, " of ", n_total, " visits (",
        round(n_reassigned / n_total * 100, 1), "%) ",
        "identified as out-of-state or OTHER_REGION and assigned ",
        "treating facility geography."
      )
    )
  }

  if (clean_names) clean_names_safe(data) else data
}
