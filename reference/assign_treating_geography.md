# Assign treating facility geography to out-of-state and OTHER_REGION visits

Identifies visits where the patient's recorded `Region` does not belong
to the site of interest – including out-of-state residents and visits
with `OTHER_REGION` or missing `Region` values – and replaces their
`Region` and/or `ZipCode` with the treating hospital's corresponding
geographic fields (`HospitalRegion` and/or `HospitalZip`). In-state
patient visits are left unchanged.

## Usage

``` r
assign_treating_geography(
  data,
  site = "KY",
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

- site:

  Character string. The site prefix used to identify in-state visits.
  Defaults to `"KY"`. Visits whose `Region` does not begin with
  `paste0(site, "_")` are treated as out-of-state.

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
  `HospitalRegion`. Required when `"region"` is in `geography`.

- zip_col:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Unquoted column name for the patient zip code field. Defaults to
  `ZipCode`. Required when `"zip"` is in `geography`.

- hospital_zip_col:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Unquoted column name for the hospital zip code field. Defaults to
  `HospitalZip`. Required when `"zip"` is in `geography`.

- preserve_original_geographies:

  Logical. If `TRUE`, adds `original_region` and/or `original_zip_code`
  columns containing pre-overwrite values before reassignment. Defaults
  to `FALSE`.

- clean_names:

  Logical. If `TRUE` (default), applies
  [`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)
  on output.

- verbose:

  Logical. If `FALSE`, suppresses informational messages
  ([`rlang::inform()`](https://rlang.r-lib.org/reference/abort.html));
  warnings and errors are always shown regardless.

## Value

The input data frame with `Region` and/or `ZipCode` reassigned for
out-of-state and `OTHER_REGION` visits. A `.out_of_state` logical column
is added indicating which rows were reassigned. When
`preserve_original_geographies = TRUE`, `original_region` and/or
`original_zip_code` columns are also present.

## Details

### Why this function exists

ESSENCE surveillance data includes visits from out-of-state residents
and patients whose legal address is unavailable to the treating facility
(`OTHER_REGION`). Simply discarding these visits understates the true
incidence burden experienced by facilities in the surveillance area.
Assigning the treating facility's geography to these visits retains them
in the analytic dataset while approximating both residence-based and
incidence-based burden from a single geographic field.

### Site prefix detection

The `Region` field uses the format `{SITE}_{REGION}`, where `SITE` is
the NSSP Site Short Name and `REGION` is the ESSENCE Region – a county
name derived from a zip-code-to-county lookup table maintained by
ESSENCE. Because some site names contain multiple underscores, the
prefix is all characters before the **last** underscore. A visit is
classified as out-of-state when its `Region` does not begin with
`paste0(site, "_")`, or when `Region` is `"OTHER_REGION"` or `NA`. For
example, with `site = "KY"`:

- `"KY_Jefferson"` -\> in-state, unchanged

- `"TN_Davidson"` -\> out-of-state, region assigned from
  `HospitalRegion`

- `"OTHER_REGION"` -\> unknown residence, region assigned from
  `HospitalRegion`

### Geography types

Both `"region"` and `"zip"` are attempted by default. If the columns
required for a geography type are absent, that type is skipped with an
informative message. Specify `geography = "region"` or
`geography = "zip"` explicitly to suppress messages about the other type
when columns are intentionally absent.

### Hybrid geography assignment and cluster detection

This function implements a hybrid geography assignment strategy:
in-state patient residential geography is preserved unchanged, while
out-of-state and `OTHER_REGION` visits are attributed to the treating
facility's geography rather than discarded. This matters for cluster
detection: a geographically concentrated surge of out-of-state overdoses
at a single facility – common near state borders or in tourist
destinations – will appear in facility-level and county-level signals
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
(`Zipcode_to_CountyRegionMapping`), not a live geocode of the record –
zip codes are assigned to a region by centroid by default, but
individual assignments may be overridden by site or state administrators
to better reflect where the bulk of a zip code's population lives.
Because of this approximation, `Region`-based results should not be
construed as the authoritative county-level count; they are ESSENCE's
standardized construct for enabling consistent sub-state reporting
across data sources, not ground truth. This function reassigns `Region`
using whatever mapping is already present in `HospitalRegion` – it does
not independently geocode or validate that mapping.

`essence_raw`/`essence_clean` and the examples throughout this package
model an ESSENCE **patient location** pull (`va_er`), where `Region`
reflects patient residence for the jurisdiction of interest. In a
**facility location** pull (`va_hosp`), the population represented
includes both residents and visitors who presented for care at
in-jurisdiction facilities –
[`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md)
is the more natural fit for that data source, since it scopes every row
to where care was received rather than mixing residence-based and
visitor rows under one semantic.

### Preserved geographies

When `preserve_original_geographies = TRUE`, `original_region` and/or
`original_zip_code` columns are added before overwriting, retaining
pre-assignment values for QA, audit trails, or residential vs. treating
geography comparisons.

## See also

[`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md)
to assign facility geography to all visits regardless of patient
residence.

## Examples

``` r
# Default: reassign both region and zip for out-of-state visits
essence_clean |> assign_treating_geography()
#> 0 of 160 visits (0%) identified as out-of-state or OTHER_REGION and assigned treating facility geography.
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
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>,
#> #   .out_of_state <lgl>, original_region <chr>, original_zip_code <chr>

# Region only -- ZipCode not in pull
essence_clean |> assign_treating_geography(geography = "region")
#> 0 of 160 visits (0%) identified as out-of-state or OTHER_REGION and assigned treating facility geography.
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
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>,
#> #   .out_of_state <lgl>, original_region <chr>, original_zip_code <chr>

# Non-Kentucky site
essence_clean |> assign_treating_geography(site = "OH")
#> 160 of 160 visits (100%) identified as out-of-state or OTHER_REGION and assigned treating facility geography.
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
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>,
#> #   .out_of_state <lgl>, original_region <chr>, original_zip_code <chr>

# Preserve original values for QA
essence_clean |>
  assign_treating_geography(preserve_original_geographies = TRUE) |>
  dplyr::filter(region != original_region)
#> 0 of 160 visits (0%) identified as out-of-state or OTHER_REGION and assigned treating facility geography.
#> # A tibble: 0 × 21
#> # ℹ 21 variables: hospital_name <chr>, hospital <int>, facility_type <chr>,
#> #   hospital_region <chr>, hospital_zip <chr>, visit_id <chr>,
#> #   c_bio_sense_id <chr>, c_unique_patient_id <chr>, date <date>,
#> #   c_visit_date_time <dttm>, arrived_date_time <dttm>, has_been_e <int>,
#> #   has_been_admitted <int>, c_patient_class <chr>, region <chr>,
#> #   zip_code <chr>, sex <chr>, c_patient_age <int>, .out_of_state <lgl>,
#> #   original_region <chr>, original_zip_code <chr>

# Full pipeline
essence_raw |>
  dedupe(order_by = Arrived_Date_Time) |>
  filter_care_setting() |>
  assign_treating_geography(preserve_original_geographies = TRUE)
#> The following `FacilityType` values are not in `keep_types` and will be excluded:
#>   - Medical Specialty
#>   - Urgent Care
#>   - Primary Care
#> 24 of 129 visits (18.6%) identified as out-of-state or OTHER_REGION and assigned treating facility geography.
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
#> #   .out_of_state <lgl>, original_region <chr>, original_zip_code <chr>
```
