# Remove duplicate records from an ESSENCE data pull

Retains one row per unique facility x visit identifier combination.
ESSENCE data frequently contains multiple rows for the same visit due to
query overlap, multi-facility pulls, or late-arriving record updates.
This function formalizes the deduplication step prior to case counting,
cluster detection, or geographic attribution.

## Usage

``` r
dedupe(
  data,
  facility_col = NULL,
  visit_col = Visit_ID,
  order_by = NULL,
  keep = "first",
  clean_names = TRUE
)
```

## Arguments

- data:

  A data frame of raw ESSENCE visit-level records.

- facility_col:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Unquoted column name identifying the facility. When not supplied,
  prefers `Hospital`/`C_BioSense_Facility_ID` over `HospitalName` if
  present; see Details. Accepts both raw ESSENCE names and
  post-[`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)
  equivalents.

- visit_col:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Unquoted column name identifying the visit. Defaults to `Visit_ID`.
  Common alternatives include `MedicalRecordNumber`, `MRN`,
  `VisitNumber`, and `C_Unique_Patient_ID`. Accepts both raw ESSENCE
  names and
  post-[`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)
  equivalents.

- order_by:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Optional. Unquoted column name to sort by within each facility x visit
  group before applying `keep`. Ignored when `keep = "most_complete"` (a
  warning is issued). Use `Arrived_Date_Time` to retain the most
  recently transmitted record (`keep = "last"`) or the earliest
  (`keep = "first"`). Other useful options: `C_Visit_Date`,
  `C_Visit_Date_Time`, `Date`. Defaults to `NULL` (row order as
  received).

- keep:

  Character string. Which row to retain per group. One of `"first"`
  (default), `"last"`, or `"most_complete"`. See Details.

- clean_names:

  Logical. If `TRUE` (default), applies
  [`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)
  to standardize column names to snake_case after deduplication.

## Value

A deduplicated data frame with one row per `facility_col` x `visit_col`
combination.

## Details

### Why deduplication is necessary

The ESSENCE API may return multiple rows for a single facility x
Visit_ID combination due to several mechanisms: standard data feed
retransmissions, midnight-crossing visits that trigger recomputation of
C_BioSense_ID, patient identifier corrections mid-visit, and patient
class transitions. Without deduplication, visit counts, rates, and
cluster detection outputs are inflated. See
[`classify_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/classify_duplicates.md)
to understand the mechanism of duplication in a specific pull before
deduplicating.

### Deduplication key

The deduplication key is always `facility_col x visit_col`. Visit_ID is
unique within a facility in ESSENCE; the same Visit_ID at two different
facilities represents two distinct encounters and is not collapsed.

### Missing key values are never treated as duplicates

A row with a missing `facility_col` or `visit_col` value has an unknown
identity, not one confirmed to match every other row with a missing
value. `dedupe()` never groups two such rows together, even when they
share the same facility and both have a missing `visit_col`: each is
retained as its own distinct row. This differs from grouping directly on
the raw columns (e.g.
[`dplyr::group_by()`](https://dplyr.tidyverse.org/reference/group_by.html)),
which follows SQL's `GROUP BY` convention of treating every `NA` as
equal to every other `NA` and would otherwise silently discard genuinely
distinct visits whose identifier happened to be missing.
[`rlang::inform()`](https://rlang.r-lib.org/reference/abort.html)
reports how many rows were affected whenever this occurs.

### Facility identifier preference

When `facility_col` is not explicitly supplied, `dedupe()` prefers
`Hospital`/`C_BioSense_Facility_ID` (a stable numeric facility
identifier) over `HospitalName` whenever it's present in the data,
falling back to `HospitalName` only if `Hospital` isn't available. A
facility rename or rebrand changes `HospitalName` but not `Hospital`;
deduplicating by name can silently split what should be one facility's
rows across a rename, or merge two different facilities that briefly
share a display name. Explicitly passing `facility_col` (either column)
always overrides this preference exactly as given.

### keep strategies

- `"first"` (default):

  Retains the first row as received. When `order_by` is supplied,
  retains the earliest record by that column. Fastest and most
  transparent.

- `"last"`:

  Retains the final row. When `order_by` is supplied, retains the most
  recently received record; appropriate when ESSENCE records are updated
  chronologically and later rows reflect corrected information. Use
  `Arrived_Date_Time` as `order_by` to retain the most recently
  transmitted version of each record.

- `"most_complete"`:

  Retains the row with the fewest `NA` values across all columns. Useful
  when records vary in completeness due to late-arriving lab or
  disposition fields. `order_by` is ignored and a warning is issued if
  supplied.

### Column name flexibility

All `_col` arguments accept both raw ESSENCE column names (e.g.,
`HospitalName`) and
post-[`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)
equivalents (e.g., `hospital_name`). The function normalizes both the
supplied name and the data's column names to snake_case for matching,
then returns results using the actual column names present in the data.

## See also

[`summarize_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/summarize_duplicates.md)
to count duplicates before deduplication;
[`classify_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/classify_duplicates.md)
to understand duplication mechanisms.

## Examples

``` r
# Default: one row per Hospital x Visit_ID (Hospital is preferred over
# HospitalName since essence_raw has it), first row as received
essence_raw |> dedupe()
#> # A tibble: 180 × 18
#>    hospital_name    hospital facility_type hospital_region hospital_zip visit_id
#>    <chr>               <int> <chr>         <chr>           <chr>        <chr>   
#>  1 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V138461…
#>  2 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V892704…
#>  3 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V853599…
#>  4 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V379196…
#>  5 North County Ho…     1002 Emergency Ca… KY_Kenton       41011        V908652…
#>  6 North County Ho…     1002 Emergency Ca… KY_Kenton       41011        V642291…
#>  7 Hillside FSED        1007 Urgent Care   KY_Jefferson    40202        V787824…
#>  8 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V229451…
#>  9 North County Ho…     1002 Emergency Ca… KY_Kenton       41011        V285888…
#> 10 Rural Health Ce…     1006 Emergency Ca… KY_Madison      40390        V511888…
#> # ℹ 170 more rows
#> # ℹ 12 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>

# Retain earliest record by visit date
essence_raw |> dedupe(order_by = Date, keep = "first")
#> # A tibble: 180 × 18
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
#> # ℹ 170 more rows
#> # ℹ 12 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>

# Retain most recently transmitted record (best for rolling pulls)
essence_raw |> dedupe(order_by = Arrived_Date_Time, keep = "last")
#> # A tibble: 180 × 18
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
#> # ℹ 170 more rows
#> # ℹ 12 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>

# Retain most complete record per visit
essence_raw |> dedupe(keep = "most_complete")
#> # A tibble: 180 × 18
#>    hospital_name    hospital facility_type hospital_region hospital_zip visit_id
#>    <chr>               <int> <chr>         <chr>           <chr>        <chr>   
#>  1 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V138461…
#>  2 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V892704…
#>  3 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V853599…
#>  4 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V379196…
#>  5 North County Ho…     1002 Emergency Ca… KY_Kenton       41011        V908652…
#>  6 North County Ho…     1002 Emergency Ca… KY_Kenton       41011        V642291…
#>  7 Hillside FSED        1007 Urgent Care   KY_Jefferson    40202        V787824…
#>  8 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V229451…
#>  9 North County Ho…     1002 Emergency Ca… KY_Kenton       41011        V285888…
#> 10 Rural Health Ce…     1006 Emergency Ca… KY_Madison      40390        V511888…
#> # ℹ 170 more rows
#> # ℹ 12 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>

# Use numeric facility ID instead of name
essence_raw |> dedupe(facility_col = Hospital)
#> # A tibble: 180 × 18
#>    hospital_name    hospital facility_type hospital_region hospital_zip visit_id
#>    <chr>               <int> <chr>         <chr>           <chr>        <chr>   
#>  1 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V138461…
#>  2 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V892704…
#>  3 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V853599…
#>  4 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V379196…
#>  5 North County Ho…     1002 Emergency Ca… KY_Kenton       41011        V908652…
#>  6 North County Ho…     1002 Emergency Ca… KY_Kenton       41011        V642291…
#>  7 Hillside FSED        1007 Urgent Care   KY_Jefferson    40202        V787824…
#>  8 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V229451…
#>  9 North County Ho…     1002 Emergency Ca… KY_Kenton       41011        V285888…
#> 10 Rural Health Ce…     1006 Emergency Ca… KY_Madison      40390        V511888…
#> # ℹ 170 more rows
#> # ℹ 12 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>

# Deduplicate by patient identifier (MRN-equivalent in ESSENCE)
essence_raw |> dedupe(visit_col = C_Unique_Patient_ID)
#> # A tibble: 183 × 18
#>    hospital_name    hospital facility_type hospital_region hospital_zip visit_id
#>    <chr>               <int> <chr>         <chr>           <chr>        <chr>   
#>  1 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V138461…
#>  2 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V892704…
#>  3 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V853599…
#>  4 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V379196…
#>  5 North County Ho…     1002 Emergency Ca… KY_Kenton       41011        V908652…
#>  6 North County Ho…     1002 Emergency Ca… KY_Kenton       41011        V642291…
#>  7 Hillside FSED        1007 Urgent Care   KY_Jefferson    40202        V787824…
#>  8 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V229451…
#>  9 North County Ho…     1002 Emergency Ca… KY_Kenton       41011        V285888…
#> 10 Rural Health Ce…     1006 Emergency Ca… KY_Madison      40390        V511888…
#> # ℹ 173 more rows
#> # ℹ 12 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>

# Works with post-clean_names() column names too
essence_raw |>
  janitor::clean_names() |>
  dedupe(order_by = arrived_date_time, keep = "last")
#> # A tibble: 180 × 18
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
#> # ℹ 170 more rows
#> # ℹ 12 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>

# Full recommended pre-processing pipeline
essence_raw |>
  dedupe(order_by = Arrived_Date_Time, keep = "last") |>
  filter_care_setting() |>
  assign_treating_geography()
#> The following `FacilityType` values are not in `keep_types` and will be excluded:
#>   - Urgent Care
#>   - Primary Care
#>   - Medical Specialty
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
```
