# Assign treating facility geography to out-of-state and OTHER_REGION visits

Identifies visits where the patient's recorded `Region` does not belong
to the site of interest, including out-of-state residents and visits
with `OTHER_REGION` or missing `Region` values, and writes the treating
hospital's corresponding geographic fields (`HospitalRegion` and/or
`HospitalZip`) for those visits to `new_region_col`/`new_zip_col`. By
default this writes new columns (`region_hybrid`/`zip_code_hybrid`),
leaving `Region`/`ZipCode` untouched; set `overwrite = TRUE` to
overwrite them in place instead. In-state patient visits keep their
original geography either way.

## Usage

``` r
assign_treating_geography(
  data,
  site = "KY",
  region_col = Region,
  hospital_region_col = HospitalRegion,
  zip_col = ZipCode,
  hospital_zip_col = HospitalZip,
  new_region_col = "region_hybrid",
  new_zip_col = "zip_code_hybrid",
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

- site:

  Character string. The site prefix used to identify in-state visits.
  Defaults to `"KY"`. Visits whose `Region` does not begin with
  `paste0(site, "_")` are treated as out-of-state.

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

  Character string or `NULL`. Name of the column to write reassigned
  region values to. Defaults to `"region_hybrid"`: a new column, leaving
  `region_col` untouched. Pass `NULL` to skip region reassignment
  entirely. Pass `region_col`'s own name (with `overwrite = TRUE`) to
  overwrite it in place instead of writing a new column. See Details.

- new_zip_col:

  Character string or `NULL`. Name of the column to write reassigned zip
  code values to. Defaults to `"zip_code_hybrid"`. Same behavior as
  `new_region_col`, independently, for zip.

- overwrite:

  Logical. If `FALSE` (default), `new_region_col`/ `new_zip_col` naming
  a column that already exists in `data` aborts rather than silently
  overwriting it. Set `TRUE` to allow it; this is required to reproduce
  the original in-place-overwrite behavior. See Details.

- preserve_original_geographies:

  Logical. If `TRUE`, adds `original_region` and/or `original_zip_code`
  columns containing pre-overwrite values before reassignment. Only has
  an effect when `overwrite = TRUE`. Defaults to `FALSE`.

- clean_names:

  Logical. If `TRUE` (default), applies
  [`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)
  on output.

- verbose:

  Logical. If `FALSE`, suppresses informational messages
  ([`rlang::inform()`](https://rlang.r-lib.org/reference/abort.html));
  warnings and errors are always shown regardless.

## Value

The input data frame with reassigned region and/or zip code values
written to `new_region_col`/`new_zip_col` (or to `region_col`/ `zip_col`
in place, when `overwrite = TRUE`). A `.out_of_state` logical column is
added indicating which rows were reassigned. When `overwrite = TRUE` and
`preserve_original_geographies = TRUE`, `original_region` and/or
`original_zip_code` columns are also present.

## Details

### Why this function exists

ESSENCE surveillance data includes visits from out-of-state residents
and patients whose legal address is unavailable to the treating facility
(`OTHER_REGION`). Simply discarding these visits understates the true
incidence burden experienced by facilities in the surveillance area.
This dropping is rarely a deliberate choice: a region-based map or
summary table scoped to in-state values will silently exclude these rows
without an explicit filter. EMS-based systems report incidence at the
location of care rather than patient residence; this function brings
ESSENCE data into that same frame. Assigning the treating facility's
geography to these visits retains them in the analytic dataset while
approximating both residence-based and incidence-based burden from a
single geographic field.

### Site prefix detection

The `Region` field uses the format `{SITE}_{REGION}`, where `SITE` is
the NSSP Site Short Name and `REGION` is the ESSENCE Region, a county
name derived from a zip-code-to-county lookup table maintained by
ESSENCE. Because some site names contain multiple underscores, the
prefix is all characters before the **last** underscore. A visit is
classified as out-of-state or unknown residence when its `Region` does
not begin with `paste0(site, "_")`, or when `Region` is
`"OTHER_REGION"`, `paste0(site, "_UNKNOWN")` (e.g. `"KY_UNKNOWN"`), or
`NA`. Unlike `"OTHER_REGION"`, the `"{site}_UNKNOWN"` form carries the
site prefix: ESSENCE uses it for a known-site record whose residential
geography could not be determined, as distinct from a residence that is
genuinely unmapped to any region, so it is checked explicitly rather
than relying on the prefix mismatch below. For example, with
`site = "KY"`:

- `"KY_Jefferson"` -\> in-state, unchanged

- `"TN_Davidson"` -\> out-of-state, region assigned from
  `HospitalRegion`

- `"OTHER_REGION"` -\> unknown residence, region assigned from
  `HospitalRegion`

- `"KY_UNKNOWN"` -\> unknown residence, region assigned from
  `HospitalRegion`

### Geography types and output columns

Both region and zip are attempted by default (`new_region_col` and
`new_zip_col` both default to a column name). Pass `NULL` to either to
skip that type entirely, e.g. `new_zip_col = NULL` to reassign only
region. If the source columns required for a requested type are absent,
that type is skipped with an informative message regardless of
`new_region_col`/`new_zip_col`.

By default, results are written to new columns (`region_hybrid`/
`zip_code_hybrid`), and `region_col`/`zip_col` are never modified; safe
to call repeatedly without risk of losing the original values. To
overwrite `region_col`/`zip_col` in place instead (the only behavior
this function had before this parameter existed), pass their own name to
`new_region_col`/`new_zip_col` and set `overwrite = TRUE`:
`assign_treating_geography(new_region_col = "region", overwrite = TRUE)`.
`overwrite` guards **any** collision with an existing column, not just
the source column: if `new_region_col`/`new_zip_col` names a column that
already exists in `data` for any reason, `overwrite = TRUE` is required
or the function aborts rather than silently overwriting it.

### Hybrid geography assignment and cluster detection

This function implements a hybrid geography assignment strategy:
in-state patient residential geography is preserved unchanged, while
out-of-state and `OTHER_REGION` visits are attributed to the treating
facility's geography rather than discarded. This matters for cluster
detection: a geographically concentrated surge of out-of-state overdoses
at a single facility, common near state borders or in tourist
destinations, will appear in facility-level and county-level signals
only if those visits are attributed to the treating location. Discarding
them suppresses the signal entirely.

Because residential geography is preserved for the in-state majority,
the resulting dataset behaves similarly to what most ESSENCE
practitioners expect from a standard query, with out-of-state and
`OTHER_REGION` visits retained rather than dropped. This makes
`assign_treating_geography()` the more conservative of the two geography
assignment methods in this package and the recommended starting point
for most surveillance applications. This approach is implemented at
scale in Kentucky's statewide syndromic overdose alert system.

The tradeoff is mixed semantics in the `Region` column: it represents
residential geography for most rows and treating-location geography for
reassigned rows. Analytic notes should document this when reporting
rates.

### ESSENCE Region field

`Region` is a formal ESSENCE geographic entity mapped relationally to a
county-to-zip code lookup table in the NSSP BioSense database,
representing the patient's approximated county of residence. It is the
preferred geography for county-level burden estimation. Custom region
fields supplied to NSSP by states (e.g., health planning districts,
local health department districts, community mental health center
service areas) are pre-computed from `Region` and would need to be
recomputed after reassignment if used downstream. Because the underlying
lookup table is not publicly accessible, this function does not support
reassigning NSSP-site-submitted custom region fields.

`Region` is a maintained many-to-one zip-to-county mapping
(`Zipcode_to_CountyRegionMapping`), not a live geocode of the record;
zip codes are assigned to a region by centroid by default, but
individual assignments may be overridden by site or state administrators
to better reflect where the bulk of a zip code's population lives.
Because of this approximation, `Region`-based results should not be
construed as the authoritative county-level count; they are ESSENCE's
standardized construct for enabling consistent sub-state reporting
across data sources, not ground truth. This function reassigns `Region`
using whatever mapping is already present in `HospitalRegion`; it does
not independently geocode or validate that mapping.

`essence_raw`/`essence_clean` and the examples throughout this package
model an ESSENCE **patient location** pull (`va_er`), where `Region`
reflects patient residence for the jurisdiction of interest. In a
**facility location** pull (`va_hosp`), the population represented
includes both residents and visitors who presented for care at
in-jurisdiction facilities;
[`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md)
is the more natural fit for that data source, since it scopes every row
to where care was received rather than mixing residence-based and
visitor rows under one semantic.

### Preserved geographies

`preserve_original_geographies` only has an effect in `overwrite = TRUE`
mode. When `new_region_col`/`new_zip_col` write to new columns (the
default), `region_col`/`zip_col` are never touched, so there is nothing
to preserve: the original values already remain exactly where they were.
When `overwrite = TRUE` and `preserve_original_geographies = TRUE`,
`original_region` and/or `original_zip_code` columns are added before
overwriting, retaining the pre-overwrite values for QA, audit trails, or
residential vs. treating geography comparisons.

## See also

[`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md)
to assign facility geography to all visits regardless of patient
residence.

## Examples

``` r
# Build a deduplicated, filtered base to demonstrate on: essence_clean
# itself already has region_hybrid/region_facility applied, so it isn't a
# fresh starting point for these examples
ed_clean <- essence_raw |>
  dedupe(order_by = Arrived_Date_Time) |>
  filter_care_setting()
#> The following `FacilityType` values are not in `keep_types` and will be excluded:
#>   - Medical Specialty
#>   - Urgent Care
#>   - Primary Care

# Default: new region_hybrid/zip_code_hybrid columns for out-of-state
# visits; region/zip_code themselves are never touched
ed_clean |> assign_treating_geography()
#> 24 of 129 visits (18.6%) identified as out-of-state or OTHER_REGION and assigned treating facility geography in `region_hybrid`/`zip_code_hybrid`.
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
#> #   .out_of_state <lgl>, region_hybrid <chr>, zip_code_hybrid <chr>

# Region only: ZipCode not in pull
ed_clean |> assign_treating_geography(new_zip_col = NULL)
#> 24 of 129 visits (18.6%) identified as out-of-state or OTHER_REGION and assigned treating facility geography in `region_hybrid`.
#> # A tibble: 129 × 20
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
#> # ℹ 14 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>,
#> #   .out_of_state <lgl>, region_hybrid <chr>

# Non-Kentucky site
ed_clean |> assign_treating_geography(site = "OH")
#> 123 of 129 visits (95.3%) identified as out-of-state or OTHER_REGION and assigned treating facility geography in `region_hybrid`/`zip_code_hybrid`.
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
#> #   .out_of_state <lgl>, region_hybrid <chr>, zip_code_hybrid <chr>

# Overwrite region/zip_code in place (the original behavior); requires
# naming the source columns explicitly and opting in with overwrite
ed_clean |>
  assign_treating_geography(
    new_region_col = "region",
    new_zip_col     = "zip_code",
    overwrite       = TRUE,
    preserve_original_geographies = TRUE
  ) |>
  dplyr::filter(region != original_region)
#> 24 of 129 visits (18.6%) identified as out-of-state or OTHER_REGION and assigned treating facility geography in `region`/`zip_code`.
#> # A tibble: 18 × 21
#>    hospital_name    hospital facility_type hospital_region hospital_zip visit_id
#>    <chr>               <int> <chr>         <chr>           <chr>        <chr>   
#>  1 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V100855…
#>  2 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V147096…
#>  3 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V154413…
#>  4 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V447417…
#>  5 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V500746…
#>  6 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V529450…
#>  7 Lakeside Commun…     1004 Emergency Ca… KY_Boone        41042        V196531…
#>  8 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V316293…
#>  9 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V330175…
#> 10 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V372552…
#> 11 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V501001…
#> 12 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V952627…
#> 13 North County Ho…     1002 Emergency Ca… KY_Kenton       41011        V245143…
#> 14 North County Ho…     1002 Emergency Ca… KY_Kenton       41011        V285888…
#> 15 North County Ho…     1002 Emergency Ca… KY_Kenton       41011        V873983…
#> 16 North County Ho…     1002 Emergency Ca… KY_Kenton       41011        V908652…
#> 17 North County Ho…     1002 Emergency Ca… KY_Kenton       41011        V934759…
#> 18 River Valley Me…     1003 Emergency Ca… KY_Warren       42101        V269975…
#> # ℹ 15 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>,
#> #   .out_of_state <lgl>, original_region <chr>, original_zip_code <chr>

# Hybrid + facility geography side by side
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
