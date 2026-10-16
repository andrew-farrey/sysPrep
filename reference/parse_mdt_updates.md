# Patient class timing helpers for link_encounters()

Internal helpers that decide the chronological order of an episode's
patient classes and which row represents the episode.

## Usage

``` r
parse_mdt_updates(mdt_str, n_classes)

safe_as_posixct(x)

compute_patient_class_sequence(patient_class, class_time)

pick_primary_row_index(patient_classes)
```

## Arguments

- mdt_str:

  A single `C_Patient_Class_MDT_Updates` string (may be `NA` or empty).

- n_classes:

  Integer. The number of patient classes in the corresponding
  `C_Patient_Class_List` value.

- x:

  A vector of timestamps, as character or anything coercible with
  [`as.character()`](https://rdrr.io/r/base/character.html). A `POSIXct`
  vector is returned unchanged.

- patient_class:

  Character vector of one episode's patient classes, one per row (so a
  class can repeat).

- class_time:

  `POSIXct` vector, parallel to `patient_class`, of the time each row's
  class occurred (`NA` where unknown).

- patient_classes:

  Character vector of an episode's patient classes, one per row.

## Value

`parse_mdt_updates()` returns a character vector of length `n_classes`.
`safe_as_posixct()` returns a `POSIXct` vector the length of `x`.
`compute_patient_class_sequence()` returns a single string, or
`NA_character_` when there is no non-missing patient class.
`pick_primary_row_index()` returns a single integer.

## Details

`parse_mdt_updates()` parses ESSENCE's `C_Patient_Class_MDT_Updates`
encoding: pipe-delimited `{position};timestamp;` segments, one per
patient class, where `position` is the 1-based character position in the
corresponding `C_Patient_Class_List` value (for example
`{1};2026-06-19 16:00:06.000;|{2};2026-06-19 17:55:10.000;` for
`C_Patient_Class_List = "EI"`). It returns a character vector of length
`n_classes` holding the timestamp string at each position, `NA` where no
segment matches that position (for example a class that was never
explicitly updated) or the segment does not match this encoding.

`safe_as_posixct()` parses timestamps for chronological ordering. A
single malformed or non-standard value must not abort the whole
vectorized parse
([`as.POSIXct()`](https://rdrr.io/r/base/as.POSIXlt.html) throws rather
than warns when a string matches none of its `tryFormats`), so values
that cannot be parsed become `NA` and ordering degrades gracefully to
the next tier for just that row instead of failing
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
entirely. It recognizes space- and `T`-separated ISO 8601-style
timestamps (with or without a trailing `Z`) and US-style
`month/day/year` timestamps, trying each format against the whole vector
at once and keeping the first format that parses each element.

`compute_patient_class_sequence()` orders an episode's distinct patient
classes by the earliest `class_time` each class occurs at, for example
`"Direct Admit->ED"` when the direct-admit record's timestamp precedes
the ED record's. It falls back to alphabetical order (matching legacy
behavior) when no usable timestamp exists for the episode at all;
classes with no timestamp sort after timed classes when some but not all
classes in the episode have one.

`pick_primary_row_index()` returns the index of the ED row in an episode
if one exists, else `1` (the first row in original order). This matches
the precedence
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
has always given the ED row via `.index_encounter`.
