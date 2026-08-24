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
  facility_col = HospitalName,
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
  Unquoted column name identifying the facility. Defaults to
  `HospitalName`. Use `Hospital` when working with
  `C_BioSense_Facility_ID`-based pulls. Accepts both raw ESSENCE names
  and
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
unique within a facility in ESSENCE – the same Visit_ID at two different
facilities represents two distinct encounters and is not collapsed.

### keep strategies

- `"first"` (default):

  Retains the first row as received. When `order_by` is supplied,
  retains the earliest record by that column. Fastest and most
  transparent.

- `"last"`:

  Retains the final row. When `order_by` is supplied, retains the most
  recently received record – appropriate when ESSENCE records are
  updated chronologically and later rows reflect corrected information.
  Use `Arrived_Date_Time` as `order_by` to retain the most recently
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
# Default: one row per HospitalName x Visit_ID, first row as received
essence_raw |> dedupe()
#> # A tibble: 180 × 18
#>    hospital_name    hospital facility_type hospital_region hospital_zip visit_id
#>    <chr>               <int> <chr>         <chr>           <chr>        <chr>   
#>  1 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V110090…
#>  2 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V161898…
#>  3 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V234672…
#>  4 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V285962…
#>  5 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V293490…
#>  6 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V368132…
#>  7 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V426844…
#>  8 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V472143…
#>  9 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V536810…
#> 10 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V555654…
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
#>  1 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V110090…
#>  2 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V161898…
#>  3 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V234672…
#>  4 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V285962…
#>  5 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V293490…
#>  6 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V368132…
#>  7 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V426844…
#>  8 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V472143…
#>  9 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V536810…
#> 10 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V555654…
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
#>  1 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V110090…
#>  2 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V161898…
#>  3 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V234672…
#>  4 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V285962…
#>  5 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V293490…
#>  6 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V368132…
#>  7 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V426844…
#>  8 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V472143…
#>  9 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V536810…
#> 10 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V555654…
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
#>  1 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V110090…
#>  2 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V161898…
#>  3 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V234672…
#>  4 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V285962…
#>  5 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V293490…
#>  6 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V368132…
#>  7 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V426844…
#>  8 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V472143…
#>  9 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V536810…
#> 10 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V555654…
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

# Deduplicate by patient identifier (MRN-equivalent in ESSENCE)
essence_raw |> dedupe(visit_col = C_Unique_Patient_ID)
#> # A tibble: 183 × 18
#>    hospital_name    hospital facility_type hospital_region hospital_zip visit_id
#>    <chr>               <int> <chr>         <chr>           <chr>        <chr>   
#>  1 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V555654…
#>  2 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V775021…
#>  3 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V536810…
#>  4 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V110090…
#>  5 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V161898…
#>  6 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V426844…
#>  7 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V472143…
#>  8 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V285962…
#>  9 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V368132…
#> 10 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V234672…
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
#>  1 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V110090…
#>  2 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V161898…
#>  3 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V234672…
#>  4 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V285962…
#>  5 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V293490…
#>  6 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V368132…
#>  7 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V426844…
#>  8 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V472143…
#>  9 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V536810…
#> 10 Cardiology Spec…     1010 Medical Spec… KY_Fayette      40508        V555654…
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
#>   - Medical Specialty
#>   - Urgent Care
#>   - Primary Care
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
