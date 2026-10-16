# NA-safe grouping keys

Internal helpers that stop rows with a missing identifier from being
merged into one group. They are shared by
[`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md),
[`summarize_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/summarize_duplicates.md),
[`classify_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/classify_duplicates.md),
and
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md).

## Usage

``` r
key_has_na_mask(data, cols)

na_safe_group_id(data, cols)

inform_na_key_rows(n_na_key, fac_col_str, visit_col_str, inform_fn)
```

## Arguments

- data:

  A data frame.

- cols:

  Character vector of the key column names in `data`.

- n_na_key:

  Integer. Number of rows with a missing key.

- fac_col_str, visit_col_str:

  Names of the facility and visit columns, used in the message.

- inform_fn:

  A function taking a single message string.

## Value

`key_has_na_mask()` returns a logical vector, `TRUE` where any of `cols`
is `NA`. `na_safe_group_id()` returns an integer group id per row.
`inform_na_key_rows()` returns `NULL` invisibly.

## Details

[`dplyr::group_by()`](https://dplyr.tidyverse.org/reference/group_by.html)
and `.by =` follow SQL's `GROUP BY` convention, in which every `NA` is
equal to every other `NA` for grouping purposes, even though `NA == NA`
evaluates to `NA` everywhere else in R. For a `facility_col x visit_col`
key a missing value means the row's true identity is unknown, not
confirmed to match every other row with a missing value, so grouping
`NA`s together silently merges genuinely distinct visits (several rows
with no `Visit_ID` would collapse into one during
[`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md),
or read as artificially "duplicated" in
[`summarize_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/summarize_duplicates.md)/[`classify_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/classify_duplicates.md)).

`na_safe_group_id()` groups rows with no `NA` in `cols` exactly as
[`dplyr::group_by()`](https://dplyr.tidyverse.org/reference/group_by.html)
would, and places every row with any `NA` in `cols` in a singleton group
of its own. The group key joins the columns with the ASCII
unit-separator control character (U+001F), which cannot occur in an
ESSENCE identifier, so two different key pairs can never concatenate to
the same string (for example facility `100` + visit `"15"` versus
facility `1001` + visit `"5"`).

`inform_na_key_rows()` emits the standard informational message when
`na_safe_group_id()` exempted one or more rows. `inform_fn` is either
[`rlang::inform`](https://rlang.r-lib.org/reference/abort.html)
([`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
and
[`summarize_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/summarize_duplicates.md),
which have no `verbose` argument) or a closure over
[`inform_if()`](https://andrew-farrey.github.io/sysPrep/reference/inform_if.md)
([`classify_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/classify_duplicates.md)
and
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md),
which do).
