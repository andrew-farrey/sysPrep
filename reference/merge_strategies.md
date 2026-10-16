# Merge strategies for link_encounters()

Internal helpers that reconcile one field across the rows of a multi-row
care episode when
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
collapses it to a single row.

## Usage

``` r
merge_strategies

check_merge_fields(merge_fields, call = rlang::caller_env())

merge_field_value(values, patient_classes, primary_value, strategy, delimiter)

merge_concat(values, primary_value)

merge_union_delimited(values, delimiter)

merge_union_ccdd(values, delimiter)

merge_prefer_yes(values, primary_value)

merge_prefer_admission(values, patient_classes, primary_value)
```

## Format

`merge_strategies` is a character vector of the valid strategy names.

## Arguments

- merge_fields:

  A named character vector mapping column names to strategy names.

- call:

  The environment errors are attributed to; see
  [`resolve_col()`](https://andrew-farrey.github.io/sysPrep/reference/resolve_col.md).

- values:

  The field's values across the episode's rows.

- patient_classes:

  The episode's patient classes, one per row.

- primary_value:

  The value on the episode's primary row (see
  [`pick_primary_row_index()`](https://andrew-farrey.github.io/sysPrep/reference/parse_mdt_updates.md)),
  used as the fallback.

- strategy:

  A single strategy name from `merge_strategies`.

- delimiter:

  The delimiter separating individual values within a field.

## Value

`merge_strategies` is a character vector. `check_merge_fields()` returns
`merge_fields` invisibly, or aborts. The `merge_*()` functions and
`merge_field_value()` return a single merged value.

## Details

`merge_strategies` is the set of strategy names accepted by
`merge_fields`. It is validated up front by `check_merge_fields()` and
listed again by `merge_field_value()`'s fallback error, so the two can
never drift apart. `merge_field_value()` dispatches one field's values
to the strategy named in `merge_fields`.

The strategies are:

- `concat`:

  Free-text merge: starting from `primary_value`, appends each other
  non-empty value not already a substring of the accumulated result.

- `union_delimited`:

  Splits each value on `delimiter`, trims whitespace, and returns the
  union of unique parts (in order of first appearance) rejoined with the
  same delimiter.

- `union_ccdd`:

  For the ESSENCE `CCDD`/`CCDDParsed` structure `"CC-values|DD-values"`:
  `|` separates CC from DD (fixed by the ESSENCE convention, not
  user-configurable) and `delimiter` separates values within each half.
  Unions unique values within each half separately, then rejoins.

- `prefer_yes`:

  If any value is affirmative (case-insensitive `"Yes"`, or `1`/`"1"`
  for 0/1-coded flag columns), the merged value is that affirmative
  value; otherwise `primary_value`.

- `prefer_admission`:

  The value from whichever row's `patient_class` indicates an admission
  (Inpatient, Direct Admit, or Admitted), if that row has a non-missing
  value; otherwise `primary_value`.

`check_merge_fields()` aborts, attributed to
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md),
unless `merge_fields` is a named character vector (possibly empty) whose
values are all valid strategies.
