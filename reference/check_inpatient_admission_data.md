# Stages of link_encounters()

Internal helpers that
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
runs in order. Each takes the data produced by the previous stage and
returns the next, so the exported function reads as a short pipeline and
each stage can be understood and tested on its own.

## Usage

``` r
check_inpatient_admission_data(
  inpatient_admission_data,
  is_missing,
  call = rlang::caller_env()
)

detect_patient_class_source(ed_data)

validate_has_been_flags(ed_data, verbose, call = rlang::caller_env())

split_patient_class_list(pc_list)

pair_mdt_timestamps(ed_data, pc_split_list, use_mdt, mdt_col_str)

long_from_patient_class_list(
  ed_data,
  pc_list_str,
  use_mdt,
  mdt_col_str,
  verbose
)

long_from_has_been_flags(ed_data, exclude_from_pivot, verbose)

bind_direct_admits(ed_long, inpatient_admission_data, verbose)

add_class_time(ed_long)

build_episode_ids(
  ed_long,
  fac_col_str,
  visit_col_str,
  has_fallback,
  fallback_col_str,
  verbose
)

add_episode_metadata(ed_long, episode_id_vec)

collapse_episodes(result, merge_fields, merge_delimiter)
```

## Arguments

- inpatient_admission_data:

  A data frame of inpatient admissions. For `bind_direct_admits()`, the
  raw (not yet normalized) data frame.

- is_missing:

  Logical. Whether `inpatient_admission_data` was omitted from the call.

- call:

  The environment errors are attributed to; see
  [`resolve_col()`](https://andrew-farrey.github.io/sysPrep/reference/resolve_col.md).

- ed_data:

  The normalized ED data frame
  ([`clean_names_safe()`](https://andrew-farrey.github.io/sysPrep/reference/resolve_col.md)
  already applied).

- verbose:

  Logical. Whether to emit informational messages.

- pc_list:

  A vector of `C_Patient_Class_List` values.

- pc_split_list:

  The list returned by `split_patient_class_list()`: one character
  vector of patient classes per row of `ed_data`.

- use_mdt:

  Logical. Whether `C_Patient_Class_MDT_Updates` is usable.

- mdt_col_str:

  Name of the `C_Patient_Class_MDT_Updates` column, or `NA_character_`.

- pc_list_str:

  Name of the `C_Patient_Class_List` column.

- exclude_from_pivot:

  Character vector of `HasBeen_` columns to leave out of the pivot.

- ed_long:

  The long-format data frame (one row per patient class) built so far.

- fac_col_str, visit_col_str:

  Names of the facility and visit columns in `ed_long`.

- has_fallback:

  Logical. Whether `fallback_visit_col` was supplied.

- fallback_col_str:

  Name of the `fallback_visit_col` column, or `NULL`.

- episode_id_vec:

  Character vector of `.episode_id` values, one per row of `ed_long`.

- result:

  The long-format data frame with episode metadata.

- merge_fields:

  Named character vector of merge strategies, with snake_case names.

- merge_delimiter:

  Delimiter used by the delimited merge strategies.

## Value

`check_inpatient_admission_data()` returns its input invisibly or
aborts. `detect_patient_class_source()` returns a list with
`use_pc_list`, `pc_list_str`, `use_mdt`, and `mdt_col_str`.
`validate_has_been_flags()` returns the `HasBeen_` columns to exclude
from the pivot. The remaining stages return the updated long-format data
frame, except `build_episode_ids()`, which returns a character vector.

## Details

The stages, in the order
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
calls them:

1.  `check_inpatient_admission_data()` aborts unless a data frame was
    supplied for `inpatient_admission_data` (there is no single-pull
    mode).

2.  `detect_patient_class_source()` finds the optional
    `C_Patient_Class_List` and `C_Patient_Class_MDT_Updates` columns,
    which decide how patient classes are derived.

3.  `validate_has_been_flags()` (only without `C_Patient_Class_List`)
    checks that the `HasBeen_` flags needed to derive patient classes
    are present and reports which admission flag will be used.

4.  `long_from_patient_class_list()` or `long_from_has_been_flags()`
    reshapes `ed_data` to one row per patient class.
    `long_from_patient_class_list()` uses `split_patient_class_list()`
    to split each `C_Patient_Class_List` value into its classes and
    `pair_mdt_timestamps()` to attach `C_Patient_Class_MDT_Updates`
    timestamps to them.

5.  `bind_direct_admits()` tags `inpatient_admission_data` as
    `"Direct Admit"` and appends it.

6.  `add_class_time()` fills the `.class_time` ordering column.

7.  `build_episode_ids()` builds the `.episode_id` for every row.

8.  `add_episode_metadata()` adds `.episode_id`,
    `.patient_class_sequence`, `.episode_n_rows`, and
    `.index_encounter`.

9.  `collapse_episodes()` reduces each episode to one row
    (`return_format = "collapsed"` only).

`long_from_has_been_flags()` pivots the `HasBeen_` flags to long format.
It preserves a copy of each pivoted column under an `_orig` name first,
since `pivot_longer()` consumes the columns it pivots on. Every
synthetic row produced from one original record describes that same
record, so each should keep that record's true `has_been_*` values
regardless of which flag triggered its own creation: an "Admitted-\>ED"
escalation splits one row (`HasBeenE = 1`, `HasBeenAdmitted = 1`) into
two synthetic rows (`ED` and `Admitted`), and both must still show
`has_been_e = 1` and `has_been_admitted = 1`. Without this, `has_been_*`
end up `NA` (or, worse, silently wrong after cross-pull
[`max()`](https://rdrr.io/r/base/Extremes.html) reconciliation) for any
row that never came from `inpatient_admission_data` directly.
`HasBeenI`, when excluded to prefer `HasBeenAdmitted`, is deliberately
left out of the pivot rather than dropped from the data, so its true 0/1
value survives on every row.

`build_episode_ids()` treats a missing `facility_col` or `visit_col`
value as an unknown identity, not as a match for every other missing
value (see
[`na_safe_group_id()`](https://andrew-farrey.github.io/sysPrep/reference/key_has_na_mask.md)),
so only NA-key rows get a unique `.episode_id` and every other row keeps
the normal `"{facility}_{visit}"` format. `fallback_visit_col` is the
one deliberate exception: a row missing `visit_col` can still be
confirmed to match another row via a secondary identifier. The three
candidate id strings are built as plain vectors, not inside a dplyr
verb, so the fallback lookup is never attempted when no
`fallback_visit_col` was supplied.

`collapse_episodes()` deliberately avoids a per-episode helper applied
through
[`dplyr::group_modify()`](https://dplyr.tidyverse.org/reference/group_map.html):
that slices out a full-width single-row data frame per episode and binds
all of them back together, which is the source of the memory and time
blowup on a full year of data. It reconciles only the columns that
change (`has_been_*` flags and `merge_fields`) as vectorized,
per-episode-grouped column operations on the multi-row episodes, then
keeps one row per episode.
