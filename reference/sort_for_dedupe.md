# Stages of dedupe() and summarize_duplicates()

Internal helpers that
[`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
and
[`summarize_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/summarize_duplicates.md)
run in order, so each exported function reads as a short pipeline.

## Usage

``` r
sort_for_dedupe(
  data,
  facility_col,
  visit_col,
  order_by_quo,
  keep,
  call = rlang::caller_env()
)

keep_group_rows(data, fac_col_str, visit_col_str, keep)

count_visit_row_groups(data_clean, fac_col_str, visit_col_str)

dup_summary_by_facility(data_clean, fac_col_str, dup_group_ids)

dup_summary_overall(data_clean, group_counts, dup_groups)
```

## Arguments

- data:

  A data frame already passed through
  [`clean_names_safe()`](https://andrew-farrey.github.io/sysPrep/reference/resolve_col.md).

- facility_col, visit_col:

  Symbols for the resolved facility and visit columns.

- order_by_quo:

  The captured `order_by` expression (a `quosure` from
  [`rlang::enquo()`](https://rlang.r-lib.org/reference/enquo.html)),
  possibly `NULL`.

- keep:

  One of `"first"`, `"last"`, or `"most_complete"`.

- call:

  The environment errors are attributed to; see
  [`resolve_col()`](https://andrew-farrey.github.io/sysPrep/reference/resolve_col.md).

- fac_col_str, visit_col_str:

  Names of the facility and visit columns.

- data_clean:

  A data frame already passed through
  [`clean_names_safe()`](https://andrew-farrey.github.io/sysPrep/reference/resolve_col.md).

- dup_group_ids:

  The `.group_id` values of the groups with more than one row.

- group_counts:

  The data frame returned by `count_visit_row_groups()`.

- dup_groups:

  `group_counts` restricted to groups with `n_rows > 1`.

## Value

`sort_for_dedupe()` returns `data`, sorted when `order_by` applies.
`keep_group_rows()` returns the deduplicated data frame.
`count_visit_row_groups()` returns a list with `data` (with a
`.group_id` column) and `counts`. `dup_summary_by_facility()` and
`dup_summary_overall()` return tibbles.

## Details

[`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
calls `sort_for_dedupe()` (apply the optional `order_by`, which
`keep = "most_complete"` ignores with a warning) and then
`keep_group_rows()` (apply the `keep` strategy within each
`facility x visit` group).

[`summarize_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/summarize_duplicates.md)
calls `count_visit_row_groups()` (one row per `facility x visit` group
with its row count), `dup_summary_by_facility()`, and
`dup_summary_overall()`.

Grouping directly on `facility_col`/`visit_col` would follow the `dplyr`
SQL-style convention of treating every `NA` as equal to every other
`NA`, silently collapsing rows with a missing identifier into a single
"duplicate" even though a missing value means the row's true identity is
unknown, not confirmed to match. Both exported functions therefore group
with
[`na_safe_group_id()`](https://andrew-farrey.github.io/sysPrep/reference/key_has_na_mask.md),
which gives each NA-key row its own singleton group, and report how many
rows were affected.

For `keep = "most_complete"`, `dplyr::pick(dplyr::everything())` already
excludes `.group_id`:
[`dplyr::pick()`](https://dplyr.tidyverse.org/reference/pick.html) never
includes the active grouping variable(s) among the columns it can pick,
so no explicit exclusion is needed (or possible, since `pick()` errors
if asked to exclude a column it never included).
