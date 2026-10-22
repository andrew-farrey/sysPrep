# Review facility ED visit counts for data quality assessment

Computes visit counts per facility and flags statistical outliers:
facilities with disproportionately low or high visit volumes relative to
the pull as a whole. Intended as an ongoing data quality monitoring tool
for production surveillance pipelines, where unexpectedly low counts may
indicate feed outages, facility onboarding issues, or non-ED providers,
and unexpectedly high counts may indicate feed duplication or query
misconfiguration.

## Usage

``` r
review_facility_ed_visits(
  data,
  facility_col = NULL,
  facility_type_col = FacilityType,
  date_col = NULL,
  method = c("percentile", "iqr", "both"),
  percentile_low = 0.05,
  percentile_high = 0.95,
  iqr_multiplier = 1.5,
  group_by_type = FALSE,
  return_format = c("outliers_only", "all"),
  clean_names = TRUE,
  verbose = TRUE
)
```

## Arguments

- data:

  A data frame of ESSENCE visit-level records, typically after
  [`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
  and optionally
  [`filter_care_setting()`](https://andrew-farrey.github.io/sysPrep/reference/filter_care_setting.md).

- facility_col:

  Unquoted column name identifying the facility. When not supplied,
  prefers `Hospital`/`C_BioSense_Facility_ID` over `HospitalName` if
  present; see the "Facility identifier preference" section of
  [`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md).
  Accepts both raw ESSENCE names and
  post-[`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)
  equivalents.

- facility_type_col:

  Unquoted column name identifying the facility type. Defaults to
  `FacilityType`. Accepts both raw ESSENCE names and
  post-[`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)
  equivalents.

- date_col:

  Optional. Unquoted column name for the visit date. When supplied,
  outlier detection uses visits per day rather than raw counts. Accepts
  `Date`, `C_Visit_Date`, or
  post-[`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)
  equivalents. Defaults to `NULL`.

- method:

  Character string. Outlier detection method. One of `"percentile"`
  (default), `"iqr"`, or `"both"`. See Details.

- percentile_low:

  Numeric. Lower percentile threshold for `method = "percentile"` or
  `"both"`. Defaults to `0.05`.

- percentile_high:

  Numeric. Upper percentile threshold for `method = "percentile"` or
  `"both"`. Defaults to `0.95`.

- iqr_multiplier:

  Numeric. Fence multiplier for `method = "iqr"` or `"both"`. Defaults
  to `1.5` (Tukey standard). Increase to reduce sensitivity; decrease to
  increase sensitivity to dropouts.

- group_by_type:

  Logical. If `TRUE`, outlier thresholds are computed separately within
  each `FacilityType` group. Defaults to `FALSE`.

- return_format:

  Character string. One of `"outliers_only"` (default) or `"all"`.
  `"outliers_only"` returns only flagged facilities. `"all"` returns all
  facilities with outlier flag columns appended.

- clean_names:

  Logical. If `TRUE` (default), applies
  [`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)
  to standardize column names to snake_case on output. If `FALSE`, the
  input's own column names are restored on output (every function
  normalizes names internally so that column arguments resolve either
  way); any columns the function itself adds keep their snake_case or
  dot-prefixed names.

- verbose:

  Logical. If `FALSE`, suppresses informational messages
  ([`rlang::inform()`](https://rlang.r-lib.org/reference/abort.html));
  warnings and errors are always shown regardless. Defaults to `TRUE`.

## Value

A tibble with one row per facility containing facility identifier,
facility type, `n_visits`, optionally `visits_per_day` and `n_days`, and
outlier flag columns `.outlier_low`, `.outlier_high`, `.outlier_flag`,
`.outlier_direction`, and `.outlier_method` (the criterion that flagged
the facility: `"percentile"`, `"iqr"`, or `"percentile+iqr"`; `NA` for
facilities that were not flagged).

## Details

### Interpreting results

Low-count outliers are expected and normal for narrow syndrome
definitions, particularly at small rural hospitals. A rural ED with two
opioid overdose visits in a given month is not a data quality problem;
it may reflect true low incidence. This function is best used on
**denominator data** (all-cause ED visits) where facility volumes are
stable and comparable. When applied to narrow case definitions, some ED
facilities will routinely appear as low outliers. The function is
intended to make routine QA assessment easier, not to drive exclusion
decisions. Always review flagged facilities in context.

### Outlier methods

- `"percentile"` (default):

  Flags facilities below `percentile_low` and above `percentile_high` of
  the visit count distribution. This is a tail ranking, not a test for
  unusual values: it flags roughly the most extreme
  `percentile_low + (1 - percentile_high)` share of facilities whether
  or not any of them is actually abnormal (with the default thresholds
  and fewer than about 20 facilities it flags the lowest and the highest
  facility every time). Use it to produce a short, ordered list to look
  at; use `"iqr"` when you want only facilities that are unusual
  relative to the spread of the rest.

- `"iqr"`:

  Flags facilities below `Q1 - iqr_multiplier * IQR` and above
  `Q3 + iqr_multiplier * IQR`. Tukey fences with the default multiplier
  of 1.5 flag nothing when facilities are similar, and are sensitive to
  data dropouts when `date_col` is supplied: a facility that abruptly
  stops sending visits during a pull window will fall well below the
  lower fence. Increase `iqr_multiplier` to reduce sensitivity.

- `"both"`:

  Applies both methods independently. A facility is flagged if it meets
  either criterion. `.outlier_method` records which criterion fired:
  `"percentile"`, `"iqr"`, or `"percentile+iqr"`.

### Time normalization

When `date_col` is supplied, visits per day is computed and outlier
detection is applied to the normalized rate rather than raw counts.
`visits_per_day` is a facility's `n_visits` divided by the number of
distinct dates in the whole pull, not by the days that facility sent
data (`n_days`, reported alongside for reference). A facility that sends
data every day of a 30-day pull and one that sends the same daily volume
for 10 days and then stops therefore get different rates, so a mid-pull
dropout falls below the lower fence instead of being hidden. This also
makes pulls of different durations comparable.

### Grouped detection

When `group_by_type = TRUE`, outlier thresholds are computed separately
within each `FacilityType`. This prevents large academic medical centers
from inflating thresholds that mask low counts at smaller facilities.

## See also

[`filter_care_setting()`](https://andrew-farrey.github.io/sysPrep/reference/filter_care_setting.md)
for removing non-ED facilities before review.

## Examples

``` r
# Default: percentile method, outliers only
essence_clean |> review_facility_ed_visits()
#> Low-count facilities are expected for narrow syndrome definitions, particularly at small rural hospitals. Low outliers do not necessarily indicate a data quality problem. For most reliable outlier detection, use denominator (all-cause ED visit) data.
#> No `date_col` supplied; using raw visit counts. Supply a date column (e.g., `date_col = Date`) to normalize to visits per day for dropout detection or cross-pull comparisons.
#> 2 of 8 facilities flagged as outliers (25%) using `method = "percentile"`.
#> # A tibble: 2 × 8
#>   hospital facility_type  n_visits .outlier_low .outlier_high .outlier_flag
#>      <int> <chr>             <int> <lgl>        <lgl>         <lgl>        
#> 1     1006 Emergency Care        8 TRUE         FALSE         TRUE         
#> 2     1001 Emergency Care       38 FALSE        TRUE          TRUE         
#> # ℹ 2 more variables: .outlier_direction <chr>, .outlier_method <chr>

# All facilities with flags
essence_clean |> review_facility_ed_visits(return_format = "all")
#> Low-count facilities are expected for narrow syndrome definitions, particularly at small rural hospitals. Low outliers do not necessarily indicate a data quality problem. For most reliable outlier detection, use denominator (all-cause ED visit) data.
#> No `date_col` supplied; using raw visit counts. Supply a date column (e.g., `date_col = Date`) to normalize to visits per day for dropout detection or cross-pull comparisons.
#> 2 of 8 facilities flagged as outliers (25%) using `method = "percentile"`.
#> # A tibble: 8 × 8
#>   hospital facility_type  n_visits .outlier_low .outlier_high .outlier_flag
#>      <int> <chr>             <int> <lgl>        <lgl>         <lgl>        
#> 1     1006 Emergency Care        8 TRUE         FALSE         TRUE         
#> 2     1001 Emergency Care       38 FALSE        TRUE          TRUE         
#> 3     1008 Emergency Care       13 FALSE        FALSE         FALSE        
#> 4     1003 Emergency Care       15 FALSE        FALSE         FALSE        
#> 5     1007 Emergency Care       18 FALSE        FALSE         FALSE        
#> 6     1002 Emergency Care       19 FALSE        FALSE         FALSE        
#> 7     1004 Emergency Care       21 FALSE        FALSE         FALSE        
#> 8     1005 Emergency Care       28 FALSE        FALSE         FALSE        
#> # ℹ 2 more variables: .outlier_direction <chr>, .outlier_method <chr>

# IQR method with time normalization for dropout detection
essence_clean |>
  review_facility_ed_visits(
    method   = "iqr",
    date_col = Date
  )
#> Low-count facilities are expected for narrow syndrome definitions, particularly at small rural hospitals. Low outliers do not necessarily indicate a data quality problem. For most reliable outlier detection, use denominator (all-cause ED visit) data.
#> 1 of 8 facilities flagged as outliers (12.5%) using `method = "iqr"`.
#> # A tibble: 1 × 10
#>   hospital facility_type  n_visits n_days visits_per_day .outlier_low
#>      <int> <chr>             <int>  <int>          <dbl> <lgl>       
#> 1     1001 Emergency Care       38     38          0.286 FALSE       
#> # ℹ 4 more variables: .outlier_high <lgl>, .outlier_flag <lgl>,
#> #   .outlier_direction <chr>, .outlier_method <chr>

# Both methods, grouped by facility type
essence_clean |>
  review_facility_ed_visits(
    method        = "both",
    group_by_type = TRUE,
    return_format = "all"
  )
#> Low-count facilities are expected for narrow syndrome definitions, particularly at small rural hospitals. Low outliers do not necessarily indicate a data quality problem. For most reliable outlier detection, use denominator (all-cause ED visit) data.
#> No `date_col` supplied; using raw visit counts. Supply a date column (e.g., `date_col = Date`) to normalize to visits per day for dropout detection or cross-pull comparisons.
#> 2 of 8 facilities flagged as outliers (25%) using `method = "both"` within FacilityType groups.
#> # A tibble: 8 × 8
#>   hospital facility_type  n_visits .outlier_low .outlier_high .outlier_flag
#>      <int> <chr>             <int> <lgl>        <lgl>         <lgl>        
#> 1     1006 Emergency Care        8 TRUE         FALSE         TRUE         
#> 2     1001 Emergency Care       38 FALSE        TRUE          TRUE         
#> 3     1008 Emergency Care       13 FALSE        FALSE         FALSE        
#> 4     1003 Emergency Care       15 FALSE        FALSE         FALSE        
#> 5     1007 Emergency Care       18 FALSE        FALSE         FALSE        
#> 6     1002 Emergency Care       19 FALSE        FALSE         FALSE        
#> 7     1004 Emergency Care       21 FALSE        FALSE         FALSE        
#> 8     1005 Emergency Care       28 FALSE        FALSE         FALSE        
#> # ℹ 2 more variables: .outlier_direction <chr>, .outlier_method <chr>
```
