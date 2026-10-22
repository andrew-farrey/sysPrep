# Patient class timing helpers for link_encounters()

Internal helpers that decide the chronological order of an episode's
patient classes and which row represents the episode.

## Usage

``` r
parse_mdt_updates(mdt_str, n_classes)

parse_mdt_segment(seg, n_classes)

safe_as_posixct(x)

episode_class_sequence(episode, patient_class, class_time)

pick_primary_row_index(patient_classes)

episode_primary_row(episode, patient_class)
```

## Arguments

- mdt_str:

  A single `C_Patient_Class_MDT_Updates` string (may be `NA` or empty).

- n_classes:

  Integer. The number of patient classes in the corresponding
  `C_Patient_Class_List` value.

- seg:

  A single trimmed, non-empty `C_Patient_Class_MDT_Updates` segment.

- x:

  A vector of timestamps, as character or anything coercible with
  [`as.character()`](https://rdrr.io/r/base/character.html). A `POSIXct`
  vector is returned unchanged.

- episode:

  Vector identifying the episode each row belongs to (for example
  `.episode_id`); rows with equal values are one episode.

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
`parse_mdt_segment()` returns a list with `idx` (an integer position)
and `time` (a string), or `NULL`. `safe_as_posixct()` returns a
`POSIXct` vector the length of `x`. `episode_class_sequence()` returns a
character vector the length of `episode`: each row's episode sequence,
`NA` for an episode with no non-missing patient class.
`pick_primary_row_index()` returns a single integer.
`episode_primary_row()` returns a logical vector the length of
`episode`, `TRUE` on each episode's primary row.

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

`episode_class_sequence()` orders each episode's distinct patient
classes by the earliest `class_time` each class occurs at, for example
`"Direct Admit->ED"` when the direct-admit record's timestamp precedes
the ED record's, and returns that string for every row of the episode.
It falls back to alphabetical order when no usable timestamp exists for
the episode at all; classes with no timestamp sort after timed classes
when some but not all classes in the episode have one. Classes with
identical timestamps (every class derived from one record shares that
record's timestamp) also fall back to alphabetical order. That is a
tiebreak only: when the timestamps are missing or equal the true order
cannot be determined from the data, so the alphabetical order carries no
clinical meaning.

`parse_mdt_segment()` parses one trimmed, non-empty
`{position};timestamp;` segment into its position and timestamp string,
or returns `NULL` when the segment does not match this encoding or its
position is not between 1 and `n_classes`.

`pick_primary_row_index()` returns the index of the ED row in an episode
if one exists, else `1` (the first row in original order): the row whose
values represent the episode when it is collapsed.
`episode_primary_row()` marks that row in every episode of a long-format
data frame, which is what `.index_encounter` records, so a long-format
count of index encounters always equals the number of rows in the
collapsed output.
