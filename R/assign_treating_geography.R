
# assign_treating_geography() ----
#' Assign treating facility geography to out-of-state and OTHER_REGION visits
#'
#' Identifies visits where the patient's recorded `Region` does not belong to
#' the site of interest -- including out-of-state residents and visits with
#' `OTHER_REGION` or missing `Region` values -- and writes the treating
#' hospital's corresponding geographic fields (`HospitalRegion` and/or
#' `HospitalZip`) for those visits to `new_region_col`/`new_zip_col`. By
#' default this writes new columns (`region_hybrid`/`zip_code_hybrid`),
#' leaving `Region`/`ZipCode` untouched; set `overwrite = TRUE` to overwrite
#' them in place instead. In-state patient visits keep their original
#' geography either way.
#'
#' @details
#' ## Why this function exists
#' ESSENCE surveillance data includes visits from out-of-state residents and
#' patients whose legal address is unavailable to the treating facility
#' (`OTHER_REGION`). Simply discarding these visits understates the true
#' incidence burden experienced by facilities in the surveillance area.
#' This dropping is rarely a deliberate choice -- a region-based map or
#' summary table scoped to in-state values will silently exclude these rows
#' without an explicit filter. EMS-based systems report incidence at the
#' location of care rather than patient residence; this function brings
#' ESSENCE data into that same frame. Assigning the treating facility's
#' geography to these visits retains them in the analytic dataset while
#' approximating both residence-based and incidence-based burden from a
#' single geographic field.
#'
#' ## Site prefix detection
#' The `Region` field uses the format `{SITE}_{REGION}`, where `SITE` is
#' the NSSP Site Short Name and `REGION` is the ESSENCE Region -- a county
#' name derived from a zip-code-to-county lookup table maintained by
#' ESSENCE. Because some site names contain multiple underscores, the
#' prefix is all characters before the **last** underscore. A visit is
#' classified as out-of-state or unknown residence when its `Region` does
#' not begin with `paste0(site, "_")`, or when `Region` is `"OTHER_REGION"`,
#' `paste0(site, "_UNKNOWN")` (e.g. `"KY_UNKNOWN"`), or `NA`. Unlike
#' `"OTHER_REGION"`, the `"{site}_UNKNOWN"` form carries the site prefix --
#' ESSENCE uses it for a known-site record whose residential geography
#' could not be determined, as distinct from a residence that is genuinely
#' unmapped to any region -- so it is checked explicitly rather than relying
#' on the prefix mismatch below. For example, with `site = "KY"`:
#' - `"KY_Jefferson"` -> in-state, unchanged
#' - `"TN_Davidson"` -> out-of-state, region assigned from `HospitalRegion`
#' - `"OTHER_REGION"` -> unknown residence, region assigned from `HospitalRegion`
#' - `"KY_UNKNOWN"` -> unknown residence, region assigned from `HospitalRegion`
#'
#' ## Geography types and output columns
#' Both region and zip are attempted by default (`new_region_col` and
#' `new_zip_col` both default to a column name). Pass `NULL` to either to
#' skip that type entirely -- e.g. `new_zip_col = NULL` to reassign only
#' region. If the source columns required for a requested type are absent,
#' that type is skipped with an informative message regardless of
#' `new_region_col`/`new_zip_col`.
#'
#' By default, results are written to new columns (`region_hybrid`/
#' `zip_code_hybrid`), and `region_col`/`zip_col` are never modified -- safe
#' to call repeatedly without risk of losing the original values. To
#' overwrite `region_col`/`zip_col` in place instead (the only behavior this
#' function had before this parameter existed), pass their own name to
#' `new_region_col`/`new_zip_col` and set `overwrite = TRUE`:
#' `assign_treating_geography(new_region_col = "region", overwrite = TRUE)`.
#' `overwrite` guards **any** collision with an existing column, not just
#' the source column -- if `new_region_col`/`new_zip_col` names a column
#' that already exists in `data` for any reason, `overwrite = TRUE` is
#' required or the function aborts rather than silently overwriting it.
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
#' `preserve_original_geographies` only has an effect in `overwrite = TRUE`
#' mode. When `new_region_col`/`new_zip_col` write to new columns (the
#' default), `region_col`/`zip_col` are never touched, so there is nothing
#' to preserve -- the original values already remain exactly where they
#' were. When `overwrite = TRUE` and `preserve_original_geographies = TRUE`,
#' `original_region` and/or `original_zip_code` columns are added before
#' overwriting, retaining the pre-overwrite values for QA, audit trails, or
#' residential vs. treating geography comparisons.
#'
#' @param data A data frame of ESSENCE visit-level records, typically the
#'   output of [dedupe()] and [filter_care_setting()].
#' @param site Character string. The site prefix used to identify in-state
#'   visits. Defaults to `"KY"`. Visits whose `Region` does not begin with
#'   `paste0(site, "_")` are treated as out-of-state.
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
#'   write reassigned region values to. Defaults to `"region_hybrid"` -- a
#'   new column, leaving `region_col` untouched. Pass `NULL` to skip region
#'   reassignment entirely. Pass `region_col`'s own name (with
#'   `overwrite = TRUE`) to overwrite it in place instead of writing a new
#'   column. See Details.
#' @param new_zip_col Character string or `NULL`. Name of the column to
#'   write reassigned zip code values to. Defaults to `"zip_code_hybrid"`.
#'   Same behavior as `new_region_col`, independently, for zip.
#' @param overwrite Logical. If `FALSE` (default), `new_region_col`/
#'   `new_zip_col` naming a column that already exists in `data` aborts
#'   rather than silently overwriting it. Set `TRUE` to allow it -- this is
#'   required to reproduce the original in-place-overwrite behavior. See
#'   Details.
#' @param preserve_original_geographies Logical. If `TRUE`, adds
#'   `original_region` and/or `original_zip_code` columns containing
#'   pre-overwrite values before reassignment. Only has an effect when
#'   `overwrite = TRUE`. Defaults to `FALSE`.
#' @param clean_names Logical. If `TRUE` (default), applies
#'   [janitor::clean_names()] on output.
#' @param verbose Logical. If `FALSE`, suppresses informational messages
#'   (`rlang::inform()`); warnings and errors are always shown regardless.
#'
#' @return The input data frame with reassigned region and/or zip code
#'   values written to `new_region_col`/`new_zip_col` (or to `region_col`/
#'   `zip_col` in place, when `overwrite = TRUE`). A `.out_of_state` logical
#'   column is added indicating which rows were reassigned. When
#'   `overwrite = TRUE` and `preserve_original_geographies = TRUE`,
#'   `original_region` and/or `original_zip_code` columns are also present.
#'
#' @examples
#' # Build a deduplicated, filtered base to demonstrate on -- essence_clean
#' # itself already has region_hybrid/region_facility applied, so it isn't a
#' # fresh starting point for these examples
#' ed_clean <- essence_raw |>
#'   dedupe(order_by = Arrived_Date_Time) |>
#'   filter_care_setting()
#'
#' # Default: new region_hybrid/zip_code_hybrid columns for out-of-state
#' # visits; region/zip_code themselves are never touched
#' ed_clean |> assign_treating_geography()
#'
#' # Region only -- ZipCode not in pull
#' ed_clean |> assign_treating_geography(new_zip_col = NULL)
#'
#' # Non-Kentucky site
#' ed_clean |> assign_treating_geography(site = "OH")
#'
#' # Overwrite region/zip_code in place (the original behavior) -- requires
#' # naming the source columns explicitly and opting in with overwrite
#' ed_clean |>
#'   assign_treating_geography(
#'     new_region_col = "region",
#'     new_zip_col     = "zip_code",
#'     overwrite       = TRUE,
#'     preserve_original_geographies = TRUE
#'   ) |>
#'   dplyr::filter(region != original_region)
#'
#' # Hybrid + facility geography side by side
#' ed_clean |>
#'   assign_treating_geography() |>
#'   assign_facility_geography()
#'
#' @seealso [assign_facility_geography()] to assign facility geography to
#'   all visits regardless of patient residence.
#' @export
assign_treating_geography <- function(data,
                                      site                          = "KY",
                                      region_col                    = Region,
                                      hospital_region_col           = HospitalRegion,
                                      zip_col                       = ZipCode,
                                      hospital_zip_col              = HospitalZip,
                                      new_region_col                = "region_hybrid",
                                      new_zip_col                   = "zip_code_hybrid",
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
  # new_zip_col -- NULL skips that type entirely ----
  do_region <- !is.null(new_region_col)
  do_zip    <- !is.null(new_zip_col)

  # Validate source columns required for each requested geography type
  # (region_col_str is validated separately below, since it's unconditionally
  # required for out-of-state detection) ----
  geog_flags <- validate_geography_cols(
    verbose, do_region, do_zip,
    region_col_str, hosp_region_col_str,
    zip_col_str, hosp_zip_col_str,
    check_region_col = FALSE
  )
  do_region <- geog_flags$do_region
  do_zip    <- geog_flags$do_zip

  # Region column required for out-of-state detection ----
  if (is.null(region_col_str)) {
    rlang::abort(
      paste0(
        "`Region` (or `region`) is required for out-of-state visit detection. ",
        "Ensure `Region` is included as a field in your ESSENCE API pull."
      )
    )
  }

  if (!do_region && !do_zip) {
    rlang::warn(
      "No geography types could be processed. Returning data unchanged."
    )
    return(if (clean_names) clean_names_safe(data) else data)
  }

  # Resolve output columns -- aborts on a reserved-name collision, or on an
  # existing-column collision unless overwrite = TRUE. By default
  # new_region_col/new_zip_col name new columns, leaving region_col/zip_col
  # untouched; passing the source column's own name plus overwrite = TRUE
  # reproduces the original in-place-overwrite behavior ----
  region_output_col_str <- if (do_region) {
    resolve_geography_output_col(
      new_region_col, data, overwrite, ".out_of_state", "new_region_col"
    )
  } else {
    NULL
  }
  zip_output_col_str <- if (do_zip) {
    resolve_geography_output_col(
      new_zip_col, data, overwrite, ".out_of_state", "new_zip_col"
    )
  } else {
    NULL
  }

  # Identify out-of-state / OTHER_REGION / unknown-residence visits ----
  # `"{site}_UNKNOWN"` (e.g. "KY_UNKNOWN") is ESSENCE's placeholder for a
  # known-site record whose residential geography could not be determined --
  # unlike "OTHER_REGION", it carries the site prefix, so it would otherwise
  # pass the str_starts() check below and be silently left as "in-state" ----
  site_prefix <- paste0(site, "_")

  data <- data |>
    dplyr::mutate(
      .out_of_state = is.na(.data[[region_col_str]]) |
        .data[[region_col_str]] == "OTHER_REGION" |
        .data[[region_col_str]] == paste0(site_prefix, "UNKNOWN") |
        !stringr::str_starts(
          .data[[region_col_str]],
          stringr::fixed(site_prefix)
        )
    )

  region_target_exists <- do_region && region_output_col_str %in% names(data)
  zip_target_exists    <- do_zip    && zip_output_col_str    %in% names(data)

  # Preserve original geographies (only meaningful when the target already
  # held a value, i.e. overwrite = TRUE was used) and reassign ----
  data <- assign_geography_reassignment(
    data, do_region, do_zip,
    region_col_str, hosp_region_col_str,
    zip_col_str, hosp_zip_col_str,
    region_output_col_str, zip_output_col_str,
    region_target_exists, zip_target_exists,
    preserve_original_geographies,
    mask = data$.out_of_state
  )

  n_reassigned <- sum(data$.out_of_state, na.rm = TRUE)
  n_total      <- nrow(data)
  output_cols  <- c(region_output_col_str, zip_output_col_str)

  if (n_total == 0L) {
    inform_if(verbose, "No rows in data after processing. Returning empty data frame.")
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

  if (clean_names) clean_names_safe(data) else data
}
