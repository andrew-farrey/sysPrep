# Assign facility geography to all visits for incidence-at-location analysis

Overwrites `Region` and/or `ZipCode` with the treating hospital's
corresponding geographic fields (`HospitalRegion` and/or `HospitalZip`)
for **all** visits, regardless of patient residence. This scopes
geography to true incidence-at-location (to the extent NSSP ESSENCE
supports it) – by attributing every visit to where care was received
rather than where the patient resides.

## Usage

``` r
assign_facility_geography(
  data,
  geography = c("region", "zip"),
  region_col = Region,
  hospital_region_col = HospitalRegion,
  zip_col = ZipCode,
  hospital_zip_col = HospitalZip,
  preserve_original_geographies = FALSE,
  clean_names = TRUE,
  verbose = TRUE
)
```

## Arguments

- data:

  A data frame of ESSENCE visit-level records, typically the output of
  [`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
  and
  [`filter_care_setting()`](https://andrew-farrey.github.io/sysPrep/reference/filter_care_setting.md).

- geography:

  Character vector. Which geography types to reassign. One or both of
  `"region"` and `"zip"`. Defaults to `c("region", "zip")`. Types with
  missing required columns are skipped with an informative message.

- region_col:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Unquoted column name for the patient region field. Defaults to
  `Region`.

- hospital_region_col:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Unquoted column name for the hospital region field. Defaults to
  `HospitalRegion`.

- zip_col:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Unquoted column name for the patient zip code field. Defaults to
  `ZipCode`.

- hospital_zip_col:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Unquoted column name for the hospital zip code field. Defaults to
  `HospitalZip`.

- preserve_original_geographies:

  Logical. If `TRUE`, adds `original_region` and/or `original_zip_code`
  columns before overwriting. Defaults to `FALSE`.

- clean_names:

  Logical. If `TRUE` (default), applies
  [`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)
  on output.

- verbose:

  Logical. If `FALSE`, suppresses informational messages
  ([`rlang::inform()`](https://rlang.r-lib.org/reference/abort.html));
  warnings and errors are always shown regardless.

## Value

The input data frame with `Region` and/or `ZipCode` overwritten with
hospital geography for all rows. A `.facility_geography` logical column
set to `TRUE` for all rows signals that facility geography has been
applied. When `preserve_original_geographies = TRUE`, `original_region`
and/or `original_zip_code` columns are also present.

## Details

### Why this function exists

[`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md)
selectively reassigns geography only for out-of-state and `OTHER_REGION`
visits, preserving residential geography for in-state patients – a
hybrid approach. `assign_facility_geography()` applies reassignment
universally: all visits, including in-state patients, receive the
treating facility's geography. This produces a dataset scoped entirely
to incidence-at-location rather than patient residence.

This is functionally equivalent to renaming `HospitalRegion` to `Region`
and `HospitalZip` to `ZipCode`, but operates on the existing data
structure without column renaming or pipeline restructuring, preserving
compatibility with downstream functions that expect `Region` and
`ZipCode` by name.

### Incidence-at-location scoping and region-level cluster detection

Assigning facility geography to all visits bins every visit to the
region in which the treating facility is located, regardless of how many
hospitals that region contains. This is a deliberate design choice with
two advantages over true hospital-level cluster detection:

- **Reduces urban-hospital bias.** Urban regions typically contain more
  hospitals than rural regions. Hospital-level scan statistics can
  evaluate clusters across individual facility locations, but they
  generally do not explicitly model residual spatial autocorrelation or
  facility-specific reporting patterns as nuisance structure. In
  prospective surveillance, scanning windows may therefore interact with
  hospital density, catchment patterns, and data submission variability
  in ways that can produce apparent clusters independent of true changes
  in underlying incidence. This concern is more pronounced in urban
  areas where hospitals are denser and submission patterns may vary
  across nearby facilities. Region-level binning does not eliminate this
  concern, but it reduces facility-level noise by aggregating across
  treating facilities within a region rather than treating each hospital
  as an independent spatial unit.

- **No Master Facility Table lookup required.** Hospital-level spatial
  clustering requires latitude/longitude coordinates sourced from the
  NSSP Master Facility Table, an additional logistical step outside the
  standard ESSENCE data pull. Region-level binning achieves a close
  approximation of hospital-level cluster detection using fields already
  present in the pull.

One consequence of region-level attribution is that detectable cluster
polygons are limited to regions that contain at least one participating
ESSENCE facility. Regions with no participating hospitals cannot
contribute counts and will not appear as cluster candidates, regardless
of actual burden in those areas. This is not unique to this approach –
it is a general property of facility-based surveillance – but it is
worth noting explicitly when interpreting spatial cluster output.

This method is currently being evaluated for adoption as an additional
scan statistic pipeline for daily prospective overdose surveillance in
Kentucky, complementing the hybrid approach implemented in
[`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md).

### Use cases

- Spatial cluster detection scoped to where patients received care
  rather than where they live.

- Incidence-at-location burden estimation irrespective of patient
  origin.

- Approximating hospital-level cluster detection without Master Facility
  Table lookups or coordinate-based spatial methods.

### ESSENCE Region field and facility location pulls

`HospitalRegion`, like `Region`, is drawn from a maintained
zip-to-county mapping rather than a live geocode – by default assigned
from the facility's zip code centroid, though site administrators can
override this via BioSense Access Management to instead reflect the
facility's listed county. `Region`-based output should not be construed
as an authoritative county-level count for either patient or facility
geography.

This function's output is best understood as approximating an ESSENCE
**facility location** pull (`va_hosp`): every row is scoped to where
care was received, so the resulting population is a combination of
jurisdiction residents and visitors who presented at in-jurisdiction
facilities. This differs from a **patient location** pull (`va_er`),
which
[`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md)
is closer to preserving – see that function's documentation for the same
caveat on `Region` field interpretation.

### Preserved geographies

When `preserve_original_geographies = TRUE`, `original_region` and/or
`original_zip_code` columns are added before overwriting. Since all rows
are reassigned, these columns retain the original patient residential
geography for all visits – enabling residential vs. treating geography
comparisons in a single dataset.

## See also

[`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md)
for selective reassignment of out-of-state visits only.

## Examples

``` r
# Default: overwrite both region and zip for all visits
essence_clean |> assign_facility_geography()
#> Facility geography applied to all 160 visits (region and zip).
#> # A tibble: 160 × 20
#>    hospital_name    hospital facility_type hospital_region hospital_zip visit_id
#>    <chr>               <int> <chr>         <chr>           <chr>        <chr>   
#>  1 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V100855…
#>  2 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V121981…
#>  3 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V138461…
#>  4 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V147096…
#>  5 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V154413…
#>  6 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V164608…
#>  7 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V176732…
#>  8 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V179024…
#>  9 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V188198…
#> 10 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V198982…
#> # ℹ 150 more rows
#> # ℹ 14 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, arrived_date_time <dttm>, has_been_e <int>,
#> #   has_been_admitted <int>, region <chr>, zip_code <chr>, sex <chr>,
#> #   c_patient_age <int>, original_region <chr>, original_zip_code <chr>,
#> #   .out_of_state <lgl>, .facility_geography <lgl>

# Preserve residential geography for comparison
essence_clean |>
  assign_facility_geography(preserve_original_geographies = TRUE) |>
  dplyr::mutate(
    patient_differs_from_facility = region != original_region
  )
#> Facility geography applied to all 160 visits (region and zip).
#> # A tibble: 160 × 21
#>    hospital_name    hospital facility_type hospital_region hospital_zip visit_id
#>    <chr>               <int> <chr>         <chr>           <chr>        <chr>   
#>  1 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V100855…
#>  2 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V121981…
#>  3 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V138461…
#>  4 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V147096…
#>  5 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V154413…
#>  6 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V164608…
#>  7 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V176732…
#>  8 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V179024…
#>  9 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V188198…
#> 10 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V198982…
#> # ℹ 150 more rows
#> # ℹ 15 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, arrived_date_time <dttm>, has_been_e <int>,
#> #   has_been_admitted <int>, region <chr>, zip_code <chr>, sex <chr>,
#> #   c_patient_age <int>, original_region <chr>, original_zip_code <chr>,
#> #   .out_of_state <lgl>, .facility_geography <lgl>,
#> #   patient_differs_from_facility <lgl>

# Facility geography for cluster detection
essence_raw |>
  dedupe(order_by = Arrived_Date_Time) |>
  filter_care_setting() |>
  assign_facility_geography(preserve_original_geographies = TRUE)
#> The following `FacilityType` values are not in `keep_types` and will be excluded:
#>   - Medical Specialty
#>   - Urgent Care
#>   - Primary Care
#> Facility geography applied to all 129 visits (region and zip).
#> # A tibble: 129 × 19
#>    hospital_name    hospital facility_type hospital_region hospital_zip visit_id
#>    <chr>               <int> <chr>         <chr>           <chr>        <chr>   
#>  1 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V100855…
#>  2 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V121981…
#>  3 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V138461…
#>  4 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V147096…
#>  5 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V154413…
#>  6 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V164608…
#>  7 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V176732…
#>  8 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V179024…
#>  9 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V188198…
#> 10 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V198982…
#> # ℹ 119 more rows
#> # ℹ 13 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, arrived_date_time <dttm>, has_been_e <int>,
#> #   has_been_admitted <int>, region <chr>, zip_code <chr>, sex <chr>,
#> #   c_patient_age <int>, original_region <chr>, original_zip_code <chr>,
#> #   .facility_geography <lgl>
```
