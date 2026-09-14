# Classify the mechanism of duplication in an ESSENCE data pull

Identifies and classifies the mechanism of duplication for each facility
x Visit_ID group containing more than one row. Classification is based
on which key ESSENCE fields vary within a duplicate group: visit date
(via C_BioSense_ID recomputation), patient identifier, and/or patient
class. Intended to be called before
[`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
to inform deduplication strategy and understand the nature of data
quality issues in a specific pull.

## Usage

``` r
classify_duplicates(
  data,
  facility_col = NULL,
  visit_col = Visit_ID,
  return_format = c("list", "tibble"),
  verbose = TRUE
)
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

- return_format:

  Character string. One of `"list"` (default) or `"tibble"`. See
  Details.

- verbose:

  Logical. If `FALSE`, suppresses informational messages
  ([`rlang::inform()`](https://rlang.r-lib.org/reference/abort.html));
  warnings and errors are always shown regardless.

## Value

When `return_format = "list"`, a named list of class
`essence_dup_classified` with:

- `$duplicate_ids`:

  Tibble of facility x visit_col pairs with more than one row.

- `$visit_groups`:

  Tibble with one row per facility x visit_col containing `n_rows`,
  `n_biosense_ids`, `n_dates`, `n_pid`, `n_patient_classes` (if
  available), and `dup_type`.

- `$by_facility`:

  Wide-format count of each `dup_type` per facility, sorted by total
  duplicated Visit IDs descending.

- `$overall`:

  Dataset-level counts and proportions by `dup_type` via
  [`janitor::tabyl()`](https://sfirke.github.io/janitor/reference/tabyl.html).

When `return_format = "tibble"`, the `$visit_groups` tibble only.

## Details

### Columns used

Required: `facility_col`, `visit_col`, `C_BioSense_ID`, `Date`,
`C_Unique_Patient_ID`. Optional: `C_Patient_Class` (enables
`patient_class_change` detection).

### Duplication mechanisms in ESSENCE

Multiple rows for the same facility x Visit_ID arise through distinct
mechanisms, each with different causes and implications:

- `"visit_date_change"`:

  `C_BioSense_ID` is computed by concatenating `C_Visit_Date`,
  `C_BioSense_Facility_ID` (`Hospital`), and `C_Unique_Patient_ID`.
  `C_Visit_Date` itself takes its date value from `C_Visit_Date_Time`.
  When a hospital's system updates `C_Visit_Date_Time` as providers
  interact with the patient, rather than fixing it at initial
  registration, and one such update crosses midnight, `C_Visit_Date`
  changes to the next calendar day, which recomputes `C_BioSense_ID` for
  the same `Visit_ID` and produces two rows that refer to the same
  encounter. This is the most widespread duplication type across NSSP
  sites; the affected proportion of visits is typically small, but the
  impact is disproportionate in small-count syndrome definitions where a
  few inflated counts can trigger anomaly detection alerts that do not
  reflect genuine changes in incidence. The duplicate arises only at
  facilities whose systems continue to update `C_Visit_Date_Time` after
  initial registration. Detected by multiple distinct `C_BioSense_ID`
  values and `Date` values within a group.

- `"pid_change"`:

  `C_Unique_Patient_ID` (which maps to MRN in Kentucky) is also one of
  the three fields concatenated into `C_BioSense_ID`, so updating it
  mid-visit recomputes `C_BioSense_ID` and produces a new row, for
  example, when an initial local (facility- or department-specific) MRN
  is replaced with a community-wide or health-system-level MRN, or with
  a different local MRN. Detected by multiple distinct
  `C_Unique_Patient_ID` values within a group. Not all ESSENCE sites use
  MRN as `C_Unique_Patient_ID`.

- `"patient_class_change"`:

  Under normal HL7 processing, patient class transitions are handled
  without generating duplicate rows: the transition is appended to
  `C_Patient_Class_List` and the `HasBeenE`, `HasBeenI`,
  `HasBeenAdmitted` flags are updated in place. This type is detected
  when the same `Visit_ID` appears with multiple distinct
  `c_patient_class` values, which may indicate a feed configuration
  issue or a concurrent triggering event. Requires `c_patient_class` to
  be present in the data; available via the standard ESSENCE API. See
  also
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  for burden estimation from multi-class episodes.

- `"type_unknown"`:

  Multiple rows exist but all assessed fields are identical across rows.
  The differentiating field was not included in the pull. Consider
  adding `C_BioSense_ID`, `Date`, and `C_Unique_Patient_ID` to your
  ESSENCE pull fields.

- Compound types:

  Any combination of the above joined with `+`, e.g.,
  `"visit_date_change+pid_change"`. Indicates multiple mechanisms acting
  simultaneously on the same visit. All possible combinations of the
  three primary mechanisms are detected and classified.

### Required columns

All classification types require `facility_col`, `visit_col`,
`C_BioSense_ID` (or `c_biosense_id` / `c_bio_sense_id`), `Date` (or
`date`), and `C_Unique_Patient_ID` (or `c_unique_patient_id`). The
function aborts with an informative message if any are absent.

### Missing key values are never classified as duplicates

A row with a missing `facility_col` or `visit_col` value has an unknown
identity, not one confirmed to match every other row with a missing
value. `classify_duplicates()` never groups two such rows together, even
when they share the same facility and both have a missing `visit_col`:
each gets its own `$visit_groups` row with
`dup_type = "no_duplication"`. This differs from grouping directly on
the raw columns (e.g.
[`dplyr::group_by()`](https://dplyr.tidyverse.org/reference/group_by.html)),
which follows SQL's `GROUP BY` convention of treating every `NA` as
equal to every other `NA` and would otherwise classify genuinely
distinct visits as duplicated just because their identifier happened to
be missing.
[`rlang::inform()`](https://rlang.r-lib.org/reference/abort.html) (gated
by `verbose`) reports how many rows were affected whenever this occurs.
See
[`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)'s
"Missing key values" section for the same behavior there.

### Optional patient class detection

Detection of `patient_class_change` requires `c_patient_class` in the
data, available via the standard ESSENCE API as a pull field. When
absent, patient class change detection is skipped and all other types
remain functional.

### Linked vs. unlinked input

`classify_duplicates()` can be run on a raw (unlinked) ESSENCE pull, or
on the long-format output of
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md):
it only requires `facility_col`/`visit_col` and the identifying columns
above, regardless of which record structure they come from. Either way,
`patient_class_change` (and every other type here) is detected from rows
that still exist side-by-side with a shared `facility_col` x `visit_col`
key: it looks for more than one distinct value of a field (here,
`c_patient_class`) across those rows, not from any single row. Once
those rows have already been collapsed into one, e.g. by
[`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md),
or by
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
with `return_format = "collapsed"`, there is only one row left per key,
so `n_rows == 1` and nothing is classified as a duplicate at all,
regardless of what mechanism originally produced the now-merged rows.
Classify before collapsing if you want to see which mechanism was
responsible.

### Return formats

- `"list"` (default):

  A named list of class `essence_dup_classified` with `$duplicate_ids`,
  `$visit_groups`, `$by_facility`, and `$overall`. `$duplicate_ids` is a
  tibble of facility x visit_col pairs with more than one row,
  consistent with
  [`summarize_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/summarize_duplicates.md)`$duplicate_ids`.

- `"tibble"`:

  The visit-group level summary tibble only: one row per facility x
  visit_col with `dup_type` and supporting `n_*` metrics. Suitable for
  joining back to original data or piping into further analysis.

## See also

[`summarize_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/summarize_duplicates.md)
for counts without mechanism detail;
[`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
to remove duplicates after review.

## Examples

``` r
# Default list return
essence_raw |> classify_duplicates()
#> 
#> ── ESSENCE Duplicate Classification ────────────────────────────────────────────
#> 
#> ── Overall ──
#> 
#>                      dup_type n percent
#>                  type_unknown 5   38.5%
#>             visit_date_change 3   23.1%
#>          patient_class_change 2   15.4%
#>                    pid_change 2   15.4%
#>  visit_date_change+pid_change 1    7.7%
#> ── By Facility ──
#> 
#> # A tibble: 5 × 7
#>   hospital patient_class_change pid_change type_unknown visit_date_change
#>      <int>                <int>      <int>        <int>             <int>
#> 1     1001                    1          2            2                 1
#> 2     1005                    0          0            3                 0
#> 3     1002                    0          0            0                 1
#> 4     1003                    0          0            0                 1
#> 5     1004                    1          0            0                 0
#> # ℹ 2 more variables: `visit_date_change+pid_change` <int>,
#> #   n_duplicated_total <dbl>
#> ── Duplicated Visit IDs ──
#> 
#> 13 facility × Visit_ID pair(s) with >1 row. Access via $duplicate_ids.
#> 
#> ── Visit Groups ──
#> 
#> 180 facility × Visit_ID groups total. Access full detail via $visit_groups.

# Tibble return for piping
essence_raw |>
  classify_duplicates(return_format = "tibble") |>
  dplyr::filter(dup_type == "visit_date_change")
#> # A tibble: 3 × 8
#>   hospital visit_id  n_rows n_biosense_ids n_dates n_pid n_patient_classes
#>      <int> <chr>      <int>          <int>   <int> <int>             <int>
#> 1     1002 V28588848      2              2       2     1                 1
#> 2     1001 V48287737      2              2       2     1                 1
#> 3     1003 V86561004      2              2       2     1                 1
#> # ℹ 1 more variable: dup_type <chr>

# Join classifications back to raw data for row-level inspection
# (clean first so join keys match the snake_case output of
# classify_duplicates; essence_raw has Hospital, so that's the
# preferred join key here, not hospital_name -- see Details in ?dedupe)
essence_raw |>
  janitor::clean_names() |>
  dplyr::left_join(
    classify_duplicates(essence_raw, return_format = "tibble"),
    by = c("hospital", "visit_id")
  )
#> # A tibble: 193 × 24
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
#> # ℹ 183 more rows
#> # ℹ 18 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>, n_rows <int>,
#> #   n_biosense_ids <int>, n_dates <int>, n_pid <int>, n_patient_classes <int>,
#> #   dup_type <chr>
```
