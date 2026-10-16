# Stages of review_facility_ed_visits()

Internal helpers that
[`review_facility_ed_visits()`](https://andrew-farrey.github.io/sysPrep/reference/review_facility_ed_visits.md)
runs in order, so the exported function reads as a short pipeline.

## Usage

``` r
check_percentile_order(
  percentile_low,
  percentile_high,
  call = rlang::caller_env()
)

resolve_review_date_col(data, date_col_quo)

inform_review_defaults(
  data,
  type_col_str,
  use_time_norm,
  group_by_type,
  verbose
)

count_facility_visits(
  data,
  fac_col_str,
  type_col_str,
  use_time_norm,
  date_col_str
)

add_outlier_thresholds(
  facility_counts,
  detect_col,
  type_col_str,
  group_by_type,
  method,
  percentile_low,
  percentile_high,
  iqr_multiplier
)

flag_outliers(facility_counts, detect_col, method)

arrange_review_result(facility_counts, detect_col, return_format)

inform_review_summary(facility_counts, method, group_by_type, verbose)
```

## Arguments

- percentile_low, percentile_high:

  Lower and upper percentile thresholds, each already validated as a
  number in `[0, 1]`.

- call:

  The environment errors are attributed to; see
  [`resolve_col()`](https://andrew-farrey.github.io/sysPrep/reference/resolve_col.md).

- data:

  A data frame already passed through
  [`clean_names_safe()`](https://andrew-farrey.github.io/sysPrep/reference/resolve_col.md).

- date_col_quo:

  The captured `date_col` expression (a `quosure` from
  [`rlang::enquo()`](https://rlang.r-lib.org/reference/enquo.html)),
  possibly `NULL`.

- type_col_str, fac_col_str:

  Names of the facility type and facility columns in `data`.

- use_time_norm:

  Logical. Whether visits are normalized to visits per day.

- group_by_type:

  Logical. Whether thresholds are computed within facility types.

- verbose:

  Logical. Whether to emit informational messages.

- date_col_str:

  Name of the date column, or `NULL`.

- facility_counts:

  The per-facility count data frame built so far.

- detect_col:

  Name of the count column outliers are detected on: `"visits_per_day"`
  or `"n_visits"`.

- method:

  One of `"percentile"`, `"iqr"`, or `"both"`.

- iqr_multiplier:

  Non-negative number: the IQR fence multiplier.

- return_format:

  One of `"outliers_only"` or `"all"`.

## Value

`check_percentile_order()` returns `NULL` invisibly or aborts.
`resolve_review_date_col()` returns a list with `use_time_norm` and
`date_col_str`. `inform_review_defaults()` and `inform_review_summary()`
are called for their messages. The remaining stages return the updated
`facility_counts` data frame.

## Details

The stages, in the order
[`review_facility_ed_visits()`](https://andrew-farrey.github.io/sysPrep/reference/review_facility_ed_visits.md)
calls them:

1.  `check_percentile_order()` aborts unless `percentile_low` is below
    `percentile_high`.

2.  `resolve_review_date_col()` resolves the optional `date_col`,
    warning and falling back to raw visit counts when it is absent.

3.  `inform_review_defaults()` emits the informational messages about
    the defaults in effect.

4.  `count_facility_visits()` counts visits per facility and facility
    type, normalized to visits per day when a date column is available.

5.  `add_outlier_thresholds()` adds the percentile and/or IQR
    thresholds, optionally within facility types. Only the quantiles the
    chosen `method` actually uses are computed: the IQR quantiles would
    be wasted work (recomputed per group) under the default
    `method = "percentile"`, and vice versa.

6.  `flag_outliers()` adds the `.outlier_*` columns and drops the
    threshold helper columns. `method` is a single scalar for the whole
    call, so the comparison is chosen once with `if`/`else` rather than
    [`dplyr::case_when()`](https://dplyr.tidyverse.org/reference/case-and-replace-when.html),
    which is deprecated for a scalar condition as of dplyr 1.2.0.

7.  `arrange_review_result()` applies `return_format`.

8.  `inform_review_summary()` reports how many facilities were flagged.
