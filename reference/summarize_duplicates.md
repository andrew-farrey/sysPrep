# Summarize duplicate records in an ESSENCE data pull

Identifies visits with more than one row per facility x Visit_ID
combination and returns a named list with three components: a tibble of
duplicated facility x Visit_ID pairs for filtering or review, a
facility-level summary arranged from most to least duplicated, and an
overall count and proportion of affected visits. Intended to be called
on raw or minimally processed ESSENCE data before
[`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md).

## Usage

``` r
summarize_duplicates(data, facility_col = NULL, visit_col = Visit_ID)
```

## Arguments

- data:

  A data frame of raw ESSENCE visit-level records.

- facility_col:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Unquoted column name identifying the facility. When not supplied,
  prefers `Hospital`/`C_BioSense_Facility_ID` over `HospitalName` if
  present; see
  [`?dedupe`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)'s
  "Facility identifier preference" section for the full rationale.
  Accepts both raw ESSENCE names and
  post-[`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)
  equivalents.

- visit_col:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Unquoted column name identifying the visit. Defaults to `Visit_ID`.
  Accepts both raw ESSENCE names and
  post-[`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)
  equivalents.

## Value

A named list of class `essence_dup_summary` with components
`$duplicate_ids`, `$by_facility`, and `$overall`.

## Details

### Duplicate definition

A duplicate is any `facility_col x visit_col` group containing more than
one row. The same `Visit_ID` appearing at two different facilities does
not constitute a duplicate: `Visit_ID` is unique only within a facility.
Duplicate detection is therefore always scoped to
`facility x visit_col`.

### Missing key values are never counted as duplicates

A row with a missing `facility_col` or `visit_col` value has an unknown
identity, not one confirmed to match every other row with a missing
value. `summarize_duplicates()` never groups two such rows together,
even when they share the same facility and both have a missing
`visit_col`: each counts as its own distinct visit in `$overall` and
`$by_facility`. This differs from grouping directly on the raw columns
(e.g.
[`dplyr::group_by()`](https://dplyr.tidyverse.org/reference/group_by.html)),
which follows SQL's `GROUP BY` convention of treating every `NA` as
equal to every other `NA` and would otherwise report genuinely distinct
visits as duplicated just because their identifier happened to be
missing.
[`rlang::inform()`](https://rlang.r-lib.org/reference/abort.html)
reports how many rows were affected whenever this occurs. See
[`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)'s
"Missing key values" section for the same behavior there.

### Return value components

- `$duplicate_ids`:

  A tibble of `facility_col x visit_col` pairs where more than one row
  exists. Use for targeted review, semi-joins, or anti-joins prior to
  deduplication.

- `$by_facility`:

  A tibble of facility-level duplicate metrics arranged from most to
  least duplicated by `n_excess_rows`.

- `$overall`:

  A single-row tibble with dataset-level counts and proportions.

## See also

[`classify_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/classify_duplicates.md)
for mechanism-level classification;
[`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
to remove duplicates after review.

## Examples

``` r
# Basic usage before deduplication
essence_raw |> summarize_duplicates()
#> 
#> ── ESSENCE Duplicate Summary ───────────────────────────────────────────────────
#> 
#> ── Overall ──
#> 
#> • Total rows in pull: 193
#> • Unique visits (facility x ID): 180
#> • Duplicated Visit IDs: 13 (7.2%)
#> • Excess rows to remove: 13
#> 
#> ── By Facility (most duplicated first) ──
#> 
#> # A tibble: 5 × 5
#>   hospital n_visits n_duplicated_visit_ids n_excess_rows pct_duplicated
#>      <int>    <int>                  <int>         <int>          <dbl>
#> 1     1001       38                      6             6           15.8
#> 2     1005       28                      3             3           10.7
#> 3     1002       19                      2             2           10.5
#> 4     1003       15                      1             1            6.7
#> 5     1004       21                      1             1            4.8
#> ── Duplicated Visit IDs ──
#> 
#> 13 facility × Visit_ID pair(s) with >1 row. Access via $duplicate_ids.

# Inspect components
dups <- summarize_duplicates(essence_raw)
dups$overall
#> # A tibble: 1 × 5
#>   n_total_rows n_unique_visits n_duplicated_visit_ids n_excess_rows
#>          <int>           <int>                  <int>         <int>
#> 1          193             180                     13            13
#> # ℹ 1 more variable: pct_duplicated <dbl>
dups$by_facility
#> # A tibble: 5 × 5
#>   hospital n_visits n_duplicated_visit_ids n_excess_rows pct_duplicated
#>      <int>    <int>                  <int>         <int>          <dbl>
#> 1     1001       38                      6             6           15.8
#> 2     1005       28                      3             3           10.7
#> 3     1002       19                      2             2           10.5
#> 4     1003       15                      1             1            6.7
#> 5     1004       21                      1             1            4.8
dups$duplicate_ids
#> # A tibble: 13 × 2
#>    hospital visit_id 
#>       <int> <chr>    
#>  1     1001 V89270420
#>  2     1005 V85359976
#>  3     1001 V37919657
#>  4     1002 V64229194
#>  5     1002 V28588848
#>  6     1001 V10085501
#>  7     1005 V38278064
#>  8     1001 V48287737
#>  9     1001 V60047491
#> 10     1005 V82754314
#> 11     1003 V86561004
#> 12     1004 V71515667
#> 13     1001 V14709603

# Filter raw data to duplicated visits for manual review
# (clean first so join keys match snake_case output of $duplicate_ids;
# essence_raw has Hospital, so that's the preferred join key here,
# not hospital_name -- see Details in ?dedupe)
essence_raw |>
  janitor::clean_names() |>
  dplyr::semi_join(
    summarize_duplicates(essence_raw)$duplicate_ids,
    by = c("hospital", "visit_id")
  )
#> # A tibble: 26 × 18
#>    hospital_name    hospital facility_type hospital_region hospital_zip visit_id
#>    <chr>               <int> <chr>         <chr>           <chr>        <chr>   
#>  1 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V892704…
#>  2 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V853599…
#>  3 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V379196…
#>  4 North County Ho…     1002 Emergency Ca… KY_Kenton       41011        V642291…
#>  5 North County Ho…     1002 Emergency Ca… KY_Kenton       41011        V285888…
#>  6 North County Ho…     1002 Emergency Ca… KY_Kenton       41011        V642291…
#>  7 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V892704…
#>  8 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V100855…
#>  9 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V382780…
#> 10 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V482877…
#> # ℹ 16 more rows
#> # ℹ 12 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>
```
