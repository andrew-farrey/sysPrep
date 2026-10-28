# Stages of filter_care_setting()

Internal helpers that
[`filter_care_setting()`](https://andrew-farrey.github.io/sysPrep/reference/filter_care_setting.md)
runs in order, so the exported function reads as a short pipeline.

## Usage

``` r
apply_type_correction(data, type_col_str, mask, fix_to)

resolve_facility_id_str(
  id_col_sym,
  fix_facility_id_vector,
  verbose,
  call = rlang::caller_env()
)

correct_by_facility_id(
  data,
  fac_col_str,
  type_col_str,
  id_col_str,
  fix_facility_id_vector,
  fix_to
)

correct_by_facility_name(
  data,
  fac_col_str,
  type_col_str,
  fix_facility_type_vector,
  fix_to,
  dry_run
)

correct_by_facility_regex(
  data,
  fac_col_str,
  type_col_str,
  fix_facility_type_regex,
  already_corrected,
  fix_to
)

preview_type_corrections(
  data,
  fac_col_str,
  type_col_str,
  id_col_str,
  use_facility_id,
  keep_types
)

inform_dropped_types(
  data,
  type_col_str,
  keep_types,
  verbose,
  type_col_label = type_col_str
)

warn_if_no_rows(
  data,
  result,
  type_col_str,
  keep_types,
  type_col_label = type_col_str
)
```

## Arguments

- data:

  A data frame already passed through
  [`clean_names_safe()`](https://andrew-farrey.github.io/sysPrep/reference/resolve_col.md),
  with the `.original_facility_type` column added.

- type_col_str, fac_col_str, id_col_str:

  Names of the facility type, facility, and facility ID columns in
  `data`.

- mask:

  Logical vector, one element per row: which rows to correct.

- fix_to:

  The facility type value to write.

- id_col_sym:

  The symbol returned by
  [`resolve_col_optional()`](https://andrew-farrey.github.io/sysPrep/reference/resolve_col.md)
  for the facility ID column, or `NULL` when it is absent.

- fix_facility_id_vector, fix_facility_type_vector:

  Values selecting the facilities to correct by ID and by exact name, or
  `NULL`.

- verbose:

  Logical. Whether to emit informational messages.

- call:

  The environment errors are attributed to; see
  [`resolve_col()`](https://andrew-farrey.github.io/sysPrep/reference/resolve_col.md).

- dry_run:

  Logical. Whether the call is a preview.

- fix_facility_type_regex:

  A single regular expression, or `NULL`.

- already_corrected:

  Facility names already corrected by an earlier route, which the regex
  route skips.

- use_facility_id:

  Logical. Whether the ID column is present, so it is included in the
  preview.

- keep_types:

  Character vector of facility types to keep.

- type_col_label:

  The facility type column's name as the caller wrote it (for example
  `FacilityType`), used in the messages from `inform_dropped_types()`
  and `warn_if_no_rows()`. Defaults to `type_col_str`.

- result:

  The filtered data frame. `warn_if_no_rows()` also takes `data`, the
  unfiltered input, to tell an empty input from a filter that matched
  nothing.

## Value

`resolve_facility_id_str()` returns a string. `correct_by_facility_id()`
returns a list with the corrected `data` and the `names` of the
facilities it corrected. The other `correct_by_*()` functions and
`apply_type_correction()` return the corrected data frame.
`preview_type_corrections()` returns the preview tibble.
`inform_dropped_types()` and `warn_if_no_rows()` are called for their
conditions.

## Details

The stages, in the order
[`filter_care_setting()`](https://andrew-farrey.github.io/sysPrep/reference/filter_care_setting.md)
calls them:

1.  `resolve_facility_id_str()` returns the facility ID column name, or
    `NA_character_` when the (optional) column is absent. It aborts if
    `fix_facility_id_vector` was supplied but the column is absent, and
    otherwise informs that ID-based corrections are unavailable.

2.  `correct_by_facility_id()`, `correct_by_facility_name()`, and
    `correct_by_facility_regex()` overwrite the facility type with
    `fix_to` for the facilities each route selects. They run in that
    order; the regex route skips every facility an earlier route already
    corrected, so the three routes combine without double-correcting.

3.  `preview_type_corrections()` builds the `dry_run` preview.

4.  `inform_dropped_types()` and `warn_if_no_rows()` report what the
    `keep_types` filter excluded.

`apply_type_correction()` is the shared primitive behind the three
correction routes: it overwrites the facility type column with `fix_to`
for the rows selected by `mask`, leaving other rows unchanged.
