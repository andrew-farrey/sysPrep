# Overwrite facility types for matching rows

Internal helper shared by
[`filter_care_setting()`](https://andrew-farrey.github.io/sysPrep/reference/filter_care_setting.md)'s
facility ID, facility name, and regex correction blocks. Overwrites the
facility type column with `fix_to` for the rows selected by `mask`,
leaving other rows unchanged.

## Usage

``` r
apply_type_correction(data, type_col_str, mask, fix_to)
```

## Arguments

- data:

  A data frame.

- type_col_str:

  Name of the facility type column in `data`.

- mask:

  Logical vector, one element per row: which rows to correct.

- fix_to:

  The facility type value to write.

## Value

`data` with `type_col_str` updated.
