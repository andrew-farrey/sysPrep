# Assign facility geography to all visits for incidence-at-location analysis

Writes the treating hospital's corresponding geographic fields
(`HospitalRegion` and/or `HospitalZip`) to
`new_region_col`/`new_zip_col` for **all** visits, regardless of patient
residence. By default this writes new columns
(`region_facility`/`zip_code_facility`), leaving `Region`/`ZipCode`
untouched; set `overwrite = TRUE` to overwrite them in place instead.
This scopes geography to true incidence-at-location (to the extent NSSP
ESSENCE supports it) – by attributing every visit to where care was
received rather than where the patient resides.

## Usage

``` r
assign_facility_geography(
  data,
  region_col = Region,
  hospital_region_col = HospitalRegion,
  zip_col = ZipCode,
  hospital_zip_col = HospitalZip,
  new_region_col = "region_facility",
  new_zip_col = "zip_code_facility",
  overwrite = FALSE,
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

- region_col:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Unquoted column name for the patient region field. Defaults to
  `Region`.

- hospital_region_col:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Unquoted column name for the hospital region field. Defaults to
  `HospitalRegion`. Required when `new_region_col` is not `NULL`.

- zip_col:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Unquoted column name for the patient zip code field. Defaults to
  `ZipCode`. Required when `new_zip_col` is not `NULL`.

- hospital_zip_col:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Unquoted column name for the hospital zip code field. Defaults to
  `HospitalZip`. Required when `new_zip_col` is not `NULL`.

- new_region_col:

  Character string or `NULL`. Name of the column to write facility
  region values to. Defaults to `"region_facility"` – a new column,
  leaving `region_col` untouched. Pass `NULL` to skip region entirely.
  Pass `region_col`'s own name (with `overwrite = TRUE`) to overwrite it
  in place instead. See Details.

- new_zip_col:

  Character string or `NULL`. Name of the column to write facility zip
  code values to. Defaults to `"zip_code_facility"`. Same behavior as
  `new_region_col`, independently, for zip.

- overwrite:

  Logical. If `FALSE` (default), `new_region_col`/ `new_zip_col` naming
  a column that already exists in `data` aborts rather than silently
  overwriting it. Set `TRUE` to allow it – this is required to reproduce
  the original in-place-overwrite behavior. See Details.

- preserve_original_geographies:

  Logical. If `TRUE`, adds `original_region` and/or `original_zip_code`
  columns before overwriting. Only has an effect when
  `overwrite = TRUE`. Defaults to `FALSE`.

- clean_names:

  Logical. If `TRUE` (default), applies
  [`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)
  on output.

- verbose:

  Logical. If `FALSE`, suppresses informational messages
  ([`rlang::inform()`](https://rlang.r-lib.org/reference/abort.html));
  warnings and errors are always shown regardless.

## Value

The input data frame with facility region and/or zip code values written
to `new_region_col`/`new_zip_col` (or to `region_col`/ `zip_col` in
place, when `overwrite = TRUE`) for all rows. A `.facility_geography`
logical column set to `TRUE` for all rows signals that facility
geography has been applied. When `overwrite = TRUE` and
`preserve_original_geographies = TRUE`, `original_region` and/or
`original_zip_code` columns are also present.

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

### Geography types and output columns

Both region and zip are attempted by default (`new_region_col` and
`new_zip_col` both default to a column name). Pass `NULL` to either to
skip that type entirely. If the source columns required for a requested
type are absent, that type is skipped with an informative message.

By default, results are written to new columns (`region_facility`/
`zip_code_facility`), and `region_col`/`zip_col` are never modified. To
overwrite `region_col`/`zip_col` in place instead (the only behavior
this function had before this parameter existed), pass their own name to
`new_region_col`/`new_zip_col` and set `overwrite = TRUE`. `overwrite`
guards **any** collision with an existing column, not just the source
column – see
[`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md)'s
documentation for the full behavior, which is identical here.

### Preserved geographies

`preserve_original_geographies` only has an effect in `overwrite = TRUE`
mode – see
[`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md).
When it does apply here, since all rows are reassigned,
`original_region`/`original_zip_code` retain the original patient
residential geography for every visit, enabling residential vs. treating
geography comparisons in a single dataset.

## See also

[`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md)
for selective reassignment of out-of-state visits only.

## Examples

``` r
# Build a deduplicated, filtered base to demonstrate on -- essence_clean
# itself already has region_hybrid/region_facility applied, so it isn't a
# fresh starting point for these examples
ed_clean <- essence_raw |>
  dedupe(order_by = Arrived_Date_Time) |>
  filter_care_setting()
#> The following `FacilityType` values are not in `keep_types` and will be excluded:
#>   - Medical Specialty
#>   - Urgent Care
#>   - Primary Care

# Default: new region_facility/zip_code_facility columns for all visits;
# region/zip_code themselves are never touched
ed_clean |> assign_facility_geography()
#> Facility geography applied to all 129 visits in `region_facility`/`zip_code_facility`.
#> # A tibble: 129 × 21
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
#> # ℹ 15 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>,
#> #   region_facility <chr>, zip_code_facility <chr>, .facility_geography <lgl>

# Overwrite region/zip_code in place (the original behavior) -- requires
# naming the source columns explicitly and opting in with overwrite
ed_clean |>
  assign_facility_geography(
    new_region_col = "region",
    new_zip_col     = "zip_code",
    overwrite       = TRUE,
    preserve_original_geographies = TRUE
  ) |>
  dplyr::mutate(
    patient_differs_from_facility = region != original_region
  )
#> Facility geography applied to all 129 visits in `region`/`zip_code`.
#> # A tibble: 129 × 22
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
#> # ℹ 16 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>,
#> #   original_region <chr>, original_zip_code <chr>, .facility_geography <lgl>,
#> #   patient_differs_from_facility <lgl>

# Facility geography for cluster detection, alongside the hybrid approach
ed_clean |>
  assign_treating_geography() |>
  assign_facility_geography()
#> 24 of 129 visits (18.6%) identified as out-of-state or OTHER_REGION and assigned treating facility geography in `region_hybrid`/`zip_code_hybrid`.
#> Facility geography applied to all 129 visits in `region_facility`/`zip_code_facility`.
#> # A tibble: 129 × 24
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
#> # ℹ 18 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>,
#> #   .out_of_state <lgl>, region_hybrid <chr>, zip_code_hybrid <chr>,
#> #   region_facility <chr>, zip_code_facility <chr>, .facility_geography <lgl>
```
