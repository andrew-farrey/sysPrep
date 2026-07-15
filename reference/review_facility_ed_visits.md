# Review facility ED visit counts for data quality assessment

Computes visit counts per facility and flags statistical outliers –
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
  facility_col = HospitalName,
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

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Unquoted column name identifying the facility. Defaults to
  `HospitalName`.

- facility_type_col:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Unquoted column name identifying the facility type. Defaults to
  `FacilityType`.

- date_col:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
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
  to standardize column names on output.

- verbose:

  Logical. If `FALSE`, suppresses informational messages
  ([`rlang::inform()`](https://rlang.r-lib.org/reference/abort.html));
  warnings and errors are always shown regardless.

## Value

A tibble with one row per facility containing facility identifier,
facility type, `n_visits`, optionally `visits_per_day` and `n_days`, and
outlier flag columns `.outlier_low`, `.outlier_high`, `.outlier_flag`,
`.outlier_direction`, and `.outlier_method`.

## Details

### Interpreting results

Low-count outliers are expected and normal for narrow syndrome
definitions, particularly at small rural hospitals. A rural ED with two
opioid overdose visits in a given month is not a data quality problem –
it may reflect true low incidence. This function is best used on
**denominator data** (all-cause ED visits) where facility volumes are
stable and comparable. When applied to narrow case definitions, some ED
facilities will routinely appear as low outliers. The function is
intended to make routine QA assessment easier, not to drive exclusion
decisions. Always review flagged facilities in context.

### Outlier methods

- `"percentile"` (default):

  Flags facilities below `percentile_low` and above `percentile_high` of
  the visit count distribution. Default thresholds of 5th and 95th
  percentile are interpretable and robust to skewed count distributions.

- `"iqr"`:

  Flags facilities below `Q1 - iqr_multiplier * IQR` and above
  `Q3 + iqr_multiplier * IQR`. Tukey fences with the default multiplier
  of 1.5 are sensitive to data dropouts – a facility that abruptly stops
  sending visits during a pull window will fall well below the lower
  fence. Increase `iqr_multiplier` to reduce sensitivity.

- `"both"`:

  Applies both methods independently. A facility is flagged if it meets
  either criterion. `.outlier_method` indicates which method triggered.

### Time normalization

When `date_col` is supplied, visits per day is computed and outlier
detection is applied to the normalized rate rather than raw counts. This
makes pulls of different durations comparable and improves sensitivity
to within-pull data dropouts (e.g., a facility that stops sending data
mid-month).

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
#> No `date_col` supplied -- using raw visit counts. Supply a date column (e.g., `date_col = Date`) to normalize to visits per day for dropout detection or cross-pull comparisons.
#> 2 of 8 facilities flagged as outliers (25%) using method = 'percentile'.
#> # A tibble: 2 × 8
#>   hospital_name  facility_type n_visits .outlier_low .outlier_high .outlier_flag
#>   <chr>          <chr>            <int> <lgl>        <lgl>         <lgl>        
#> 1 Rural Health … Emergency Ca…        8 TRUE         FALSE         TRUE         
#> 2 Central Medic… Emergency Ca…       38 FALSE        TRUE          TRUE         
#> # ℹ 2 more variables: .outlier_direction <chr>, .outlier_method <chr>

# All facilities with flags
essence_clean |> review_facility_ed_visits(return_format = "all")
#> Low-count facilities are expected for narrow syndrome definitions, particularly at small rural hospitals. Low outliers do not necessarily indicate a data quality problem. For most reliable outlier detection, use denominator (all-cause ED visit) data.
#> No `date_col` supplied -- using raw visit counts. Supply a date column (e.g., `date_col = Date`) to normalize to visits per day for dropout detection or cross-pull comparisons.
#> 2 of 8 facilities flagged as outliers (25%) using method = 'percentile'.
#> # A tibble: 8 × 8
#>   hospital_name  facility_type n_visits .outlier_low .outlier_high .outlier_flag
#>   <chr>          <chr>            <int> <lgl>        <lgl>         <lgl>        
#> 1 Rural Health … Emergency Ca…        8 TRUE         FALSE         TRUE         
#> 2 Central Medic… Emergency Ca…       38 FALSE        TRUE          TRUE         
#> 3 Downtown Emer… Emergency Ca…       13 FALSE        FALSE         FALSE        
#> 4 River Valley … Emergency Ca…       15 FALSE        FALSE         FALSE        
#> 5 Hillside FSED  Emergency Ca…       18 FALSE        FALSE         FALSE        
#> 6 North County … Emergency Ca…       19 FALSE        FALSE         FALSE        
#> 7 Lakeside Comm… Emergency Ca…       21 FALSE        FALSE         FALSE        
#> 8 Metro Health … Emergency Ca…       28 FALSE        FALSE         FALSE        
#> # ℹ 2 more variables: .outlier_direction <chr>, .outlier_method <chr>

# IQR method with time normalization for dropout detection
essence_clean |>
  review_facility_ed_visits(
    method   = "iqr",
    date_col = Date
  )
#> Low-count facilities are expected for narrow syndrome definitions, particularly at small rural hospitals. Low outliers do not necessarily indicate a data quality problem. For most reliable outlier detection, use denominator (all-cause ED visit) data.
#> 0 of 8 facilities flagged as outliers (0%) using method = 'iqr'.
#> # A tibble: 0 × 10
#> # ℹ 10 variables: hospital_name <chr>, facility_type <chr>, n_visits <int>,
#> #   n_days <int>, visits_per_day <dbl>, .outlier_low <lgl>,
#> #   .outlier_high <lgl>, .outlier_flag <lgl>, .outlier_direction <chr>,
#> #   .outlier_method <chr>

# Both methods, grouped by facility type
essence_clean |>
  review_facility_ed_visits(
    method        = "both",
    group_by_type = TRUE,
    return_format = "all"
  )
#> Low-count facilities are expected for narrow syndrome definitions, particularly at small rural hospitals. Low outliers do not necessarily indicate a data quality problem. For most reliable outlier detection, use denominator (all-cause ED visit) data.
#> No `date_col` supplied -- using raw visit counts. Supply a date column (e.g., `date_col = Date`) to normalize to visits per day for dropout detection or cross-pull comparisons.
#> 2 of 8 facilities flagged as outliers (25%) using method = 'both' within FacilityType groups.
#> # A tibble: 8 × 8
#>   hospital_name  facility_type n_visits .outlier_low .outlier_high .outlier_flag
#>   <chr>          <chr>            <int> <lgl>        <lgl>         <lgl>        
#> 1 Rural Health … Emergency Ca…        8 TRUE         FALSE         TRUE         
#> 2 Central Medic… Emergency Ca…       38 FALSE        TRUE          TRUE         
#> 3 Downtown Emer… Emergency Ca…       13 FALSE        FALSE         FALSE        
#> 4 River Valley … Emergency Ca…       15 FALSE        FALSE         FALSE        
#> 5 Hillside FSED  Emergency Ca…       18 FALSE        FALSE         FALSE        
#> 6 North County … Emergency Ca…       19 FALSE        FALSE         FALSE        
#> 7 Lakeside Comm… Emergency Ca…       21 FALSE        FALSE         FALSE        
#> 8 Metro Health … Emergency Ca…       28 FALSE        FALSE         FALSE        
#> # ℹ 2 more variables: .outlier_direction <chr>, .outlier_method <chr>
```
