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
summarize_duplicates(data, facility_col = HospitalName, visit_col = Visit_ID)
```

## Arguments

- data:

  A data frame of raw ESSENCE visit-level records.

- facility_col:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Unquoted column name identifying the facility. Defaults to
  `HospitalName`. Accepts both raw ESSENCE names and
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
not constitute a duplicate – `Visit_ID` is unique only within a
facility. Duplicate detection is therefore always scoped to
`facility x visit_col`.

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
#> • Total rows in pull: 197
#> • Unique visits (facility x ID): 184
#> • Duplicated Visit IDs: 13 (7.1%)
#> • Excess rows to remove: 13
#> 
#> ── By Facility (most duplicated first) ──
#> 
#> # A tibble: 5 × 5
#>   hospital_name     n_visits n_duplicated_visit_ids n_excess_rows pct_duplicated
#>   <chr>                <int>                  <int>         <int>          <dbl>
#> 1 Central Medical …       38                      6             6           15.8
#> 2 Metro Health Sys…       28                      3             3           10.7
#> 3 North County Hos…       20                      2             2           10  
#> 4 Lakeside Communi…       21                      1             1            4.8
#> 5 River Valley Med…       15                      1             1            6.7
#> ── Duplicated Visit IDs ──
#> 
#> 13 facility × Visit_ID pair(s) with >1 row. Access via $duplicate_ids.

# Inspect components
dups <- summarize_duplicates(essence_raw)
dups$overall
#> # A tibble: 1 × 5
#>   n_total_rows n_unique_visits n_duplicated_visit_ids n_excess_rows
#>          <int>           <int>                  <int>         <int>
#> 1          197             184                     13            13
#> # ℹ 1 more variable: pct_duplicated <dbl>
dups$by_facility
#> # A tibble: 5 × 5
#>   hospital_name     n_visits n_duplicated_visit_ids n_excess_rows pct_duplicated
#>   <chr>                <int>                  <int>         <int>          <dbl>
#> 1 Central Medical …       38                      6             6           15.8
#> 2 Metro Health Sys…       28                      3             3           10.7
#> 3 North County Hos…       20                      2             2           10  
#> 4 Lakeside Communi…       21                      1             1            4.8
#> 5 River Valley Med…       15                      1             1            6.7
dups$duplicate_ids
#> # A tibble: 13 × 2
#>    hospital_name               visit_id 
#>    <chr>                       <chr>    
#>  1 Central Medical Center      V10085501
#>  2 Central Medical Center      V14709603
#>  3 Central Medical Center      V37919657
#>  4 Central Medical Center      V48287737
#>  5 Central Medical Center      V60047491
#>  6 Central Medical Center      V89270420
#>  7 Lakeside Community Hospital V71515667
#>  8 Metro Health System East    V38278064
#>  9 Metro Health System East    V82754314
#> 10 Metro Health System East    V85359976
#> 11 North County Hospital       V28588848
#> 12 North County Hospital       V64229194
#> 13 River Valley Medical        V86561004

# Filter raw data to duplicated visits for manual review
# (clean first so join keys match snake_case output of $duplicate_ids)
essence_raw |>
  janitor::clean_names() |>
  dplyr::semi_join(
    summarize_duplicates(essence_raw)$duplicate_ids,
    by = c("hospital_name", "visit_id")
  )
#> # A tibble: 26 × 19
#>    hospital_name    hospital facility_type hospital_region hospital_zip visit_id
#>    <chr>               <int> <chr>         <chr>           <chr>        <chr>   
#>  1 North County Ho…     1002 Emergency Ca… KY_Kenton       41011        V642291…
#>  2 Lakeside Commun…     1004 Emergency Ca… KY_Boone        41042        V715156…
#>  3 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V147096…
#>  4 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V147096…
#>  5 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V853599…
#>  6 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V853599…
#>  7 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V382780…
#>  8 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V600474…
#>  9 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V600474…
#> 10 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V382780…
#> # ℹ 16 more rows
#> # ℹ 13 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>,
#> #   pull_source <chr>
```
