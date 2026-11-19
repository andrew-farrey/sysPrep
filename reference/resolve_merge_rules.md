# Per-column merge rules for linked episodes

When
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
links an ED record and a separately submitted inpatient record into one
episode, each column of the kept row is reconciled by a rule. The
principle: only the `HasBeen_` flags, `C_Death` and
`DispositionCategory` are collapsed to one value so the row reflects the
whole encounter of care; every other field keeps what either record
holds.

## Usage

``` r
resolve_merge_rules(data, merge_fields, table = merge_field_table)

is_informative(x, extra = NULL)

merge_prefer_primary(primary_value)

merge_prefer_informative(values, primary_value)

merge_earliest(values, primary_value)

merge_max(values, primary_value)

merge_linked_episodes(
  multi_row,
  rules,
  merge_delimiter,
  severity_col,
  has_been_cols
)

merge_union_delimited_all(x, ep, n_ep, delimiter)
```

## Arguments

- data:

  A data frame with the episode columns `.episode_id` and
  `patient_class`.

- merge_fields:

  `NULL`, or a named character vector mapping column names (already in
  [`janitor::make_clean_names()`](https://sfirke.github.io/janitor/reference/make_clean_names.html)
  form) to a strategy from `merge_strategies`. Each entry replaces the
  table's rule for that column.

- table:

  The rule table; defaults to the internal `merge_field_table`. Exposed
  so tests can supply a small table.

- x, values:

  A vector of one column's values.

- extra:

  Extra text values to treat as uninformative for this column.

- primary_value:

  The primary row's value.

- multi_row:

  The rows of the episodes that have more than one row, with
  `.episode_id`, `patient_class` and, when present, `.link_pull`.

- rules:

  The data frame returned by `resolve_merge_rules()`.

- merge_delimiter:

  The delimiter used by the `"union_delimited"` and `"union_ccdd"`
  strategies.

- severity_col:

  The column merged with `"prefer_severity"`, or `NA`.

- has_been_cols:

  Names of the `HasBeen_` flag columns, which take the maximum across an
  episode's rows.

## Value

`resolve_merge_rules()` returns a data frame with one row per merged
column: `column`, `strategy`, and `follow` (the column followed, or the
text column whose length is recomputed, else `NA`).
`merge_linked_episodes()` returns one row per episode.
`is_informative()` returns a logical vector. The `merge_*()` functions
return a single value.

## Details

These helpers resolve and apply those rules.

- `resolve_merge_rules()` assigns a strategy to every column that is
  merged. A column named in `merge_fields` uses that strategy. Otherwise
  the column is looked up in the internal `merge_field_table` (built
  from `data-raw/merge_field_classification.csv`, which follows the NSSP
  ESSENCE data dictionary) by its
  [`janitor::make_clean_names()`](https://sfirke.github.io/janitor/reference/make_clean_names.html)
  name, then by a looser spelling (lower case, no underscores) when that
  spelling points to exactly one table row, so `c_biosense_id` finds
  `C_BioSense_ID`. Anything else follows its type: text keeps both
  records' values (`"concat"`), everything else takes the first
  informative value (`"prefer_informative"`).

- `merge_linked_episodes()` applies the rules to the rows of every
  multi-row episode and returns one row per episode. The rules that need
  no per-episode logic are computed over whole columns at once, and only
  the text-merging rules visit episodes one at a time.

- `is_informative()` says which values carry information: a missing
  value, blank text, or a placeholder such as `"None"` or `"Unknown"`
  does not.

- `merge_prefer_primary()`, `merge_prefer_informative()`,
  `merge_earliest()` and `merge_max()` are the one-episode versions of
  the matching strategies; `merge_linked_episodes()` must agree with
  them.

Rules that need a winning record use the **primary row** (the ED record
when the episode has one, otherwise its first row). A column that takes
"the winning record's value unless it is uninformative" takes the
primary row's value, or, when that is missing or a placeholder, the
first informative value from another record.

Two kinds of rule tie a column to another column's winning record, so
values that belong together never mix records.
`"prefer_informative_disposition"` (discharge and death times) uses the
record that won `DispositionCategory` as its winning record. `"follow"`
(units, derived lookups, durations) takes the value from whichever
record supplied the column it follows, even when that value is missing:
a weight and its units, or a zip code and its region, always come from
one record. A column whose source is absent from the data falls back to
the first informative value.

`"recompute_length"` sets `CCOrig_Length`, `CCParsed_Length` and
`DD_Length` to the number of characters (separators included) in the
merged `ChiefComplaintOrig`, `ChiefComplaintParsed` and
`DischargeDiagnosis`. When the length column is present but its text
column is not, the winning record's value is kept and a warning says so.
