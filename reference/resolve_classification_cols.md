# Stages of classify_duplicates()

Internal helpers that
[`classify_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/classify_duplicates.md)
runs in order, so the exported function reads as a short pipeline.

## Usage

``` r
resolve_classification_cols(data_clean, call = rlang::caller_env())

resolve_patient_class_col(data_clean, verbose)

summarize_visit_groups(
  data_clean,
  fac_col_str,
  visit_col_str,
  cols,
  patient_class,
  verbose
)

classify_dup_type(visit_groups, has_patient_class)

summarize_dup_by_facility(dup_rows, fac_col_str)

summarize_dup_overall(dup_rows)
```

## Arguments

- data_clean:

  A data frame already passed through
  [`clean_names_safe()`](https://andrew-farrey.github.io/sysPrep/reference/resolve_col.md).

- call:

  The environment errors are attributed to; see
  [`resolve_col()`](https://andrew-farrey.github.io/sysPrep/reference/resolve_col.md).

- verbose:

  Logical. Whether to emit informational messages.

- fac_col_str, visit_col_str:

  Names of the facility and visit columns.

- cols:

  The list returned by `resolve_classification_cols()`.

- patient_class:

  The list returned by `resolve_patient_class_col()`.

- visit_groups:

  The data frame returned by `summarize_visit_groups()`.

- has_patient_class:

  Logical. Whether `C_Patient_Class` is available.

- dup_rows:

  `visit_groups` restricted to rows whose `dup_type` is not
  `"no_duplication"`.

## Value

`resolve_classification_cols()` returns a list with `biosense`, `date`,
and `pid` (strings). `resolve_patient_class_col()` returns a list with
`has_patient_class` and `pc_col_str`. `summarize_visit_groups()` and
`classify_dup_type()` return the visit-group data frame (the latter with
`dup_type`). `summarize_dup_by_facility()` and `summarize_dup_overall()`
return tibbles.

## Details

The stages, in the order
[`classify_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/classify_duplicates.md)
calls them:

1.  `resolve_classification_cols()` resolves the three required columns
    (`C_BioSense_ID`, `Date`, `C_Unique_Patient_ID`), accepting raw
    ESSENCE names,
    [`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)
    output, or variants, and aborts listing every missing one.

2.  `resolve_patient_class_col()` resolves the optional
    `C_Patient_Class` column; without it patient class change detection
    is skipped.

3.  `summarize_visit_groups()` collapses `data` to one row per
    `facility x visit` group with the number of distinct
    `C_BioSense_ID`s, dates, patient identifiers, and patient classes. A
    missing `facility_col` or `visit_col` value means that row's true
    identity is unknown, not confirmed to match every other row with a
    missing value, so it is grouped with
    [`na_safe_group_id()`](https://andrew-farrey.github.io/sysPrep/reference/key_has_na_mask.md)
    rather than
    [`dplyr::group_by()`](https://dplyr.tidyverse.org/reference/group_by.html)
    (which would treat every `NA` as equal and silently classify
    unrelated visits as duplicated).

4.  `classify_dup_type()` assigns the `dup_type` from which fields
    varied: `"no_duplication"` for a single row, `"type_unknown"` for
    several rows with no variation in the assessed fields, one of the
    three single mechanisms, or a compound of two or three joined with
    `+`.

5.  `summarize_dup_by_facility()` and `summarize_dup_overall()` build
    the two summary tables from the rows classified as duplicates.
    `summarize_dup_overall()` builds the empty tibble directly for a
    clean pull, because
    [`janitor::adorn_pct_formatting()`](https://sfirke.github.io/janitor/reference/adorn_pct_formatting.html)
    errors on a 0-row tabyl (it tries to write a `"%"` string into a
    0-row percent column).
