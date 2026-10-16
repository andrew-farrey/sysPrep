# Shared steps of the geography assignment functions

Internal helpers shared by
[`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md)
and
[`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md).

## Usage

``` r
validate_geography_cols(
  verbose,
  do_region,
  do_zip,
  region_col_str,
  hosp_region_col_str,
  zip_col_str,
  hosp_zip_col_str,
  check_region_col = TRUE
)

resolve_geography_output_col(
  new_col,
  data,
  overwrite,
  reserved_col,
  arg_name,
  call = rlang::caller_env()
)

assign_geography_reassignment(
  data,
  do_region,
  do_zip,
  region_col_str,
  hosp_region_col_str,
  zip_col_str,
  hosp_zip_col_str,
  region_output_col_str,
  zip_output_col_str,
  region_target_exists,
  zip_target_exists,
  preserve_original_geographies,
  mask
)

resolve_geography_sources(
  data,
  region_sym,
  hosp_region_sym,
  zip_sym,
  hosp_zip_sym
)

resolve_geography_outputs(
  data,
  flags,
  new_region_col,
  new_zip_col,
  overwrite,
  reserved_col,
  call = rlang::caller_env()
)

reassign_geography(
  data,
  flags,
  sources,
  outputs,
  preserve_original_geographies,
  mask
)

warn_site_without_region_match(data, region_col_str, site)

flag_out_of_state(data, region_col_str, site)

inform_treating_result(data, outputs, verbose)

inform_facility_result(data, outputs, verbose)
```

## Arguments

- verbose:

  Logical. Whether to emit informational messages.

- do_region, do_zip:

  Logical. Whether region/zip geography is being processed.

- region_col_str, hosp_region_col_str, zip_col_str, hosp_zip_col_str:

  Resolved column names (strings), or `NULL` when the optional column is
  absent.

- check_region_col:

  Logical. Whether to validate `region_col_str` here.

- new_col:

  The user-supplied output column name, or `NULL`.

- data:

  A data frame.

- overwrite:

  Logical. Whether an existing column may be overwritten.

- reserved_col:

  The dot-prefixed bookkeeping column name the output must not collide
  with.

- arg_name:

  The calling function's argument name (for example `"new_region_col"`),
  used in error messages.

- call:

  The environment errors are attributed to; see
  [`resolve_col()`](https://andrew-farrey.github.io/sysPrep/reference/resolve_col.md).

- region_output_col_str, zip_output_col_str:

  Resolved output column names from `resolve_geography_output_col()`, or
  `NULL`.

- region_target_exists, zip_target_exists:

  Logical. Whether the output column already existed in `data`.

- preserve_original_geographies:

  Logical. Whether to add `original_region`/`original_zip_code` columns.

- mask:

  Logical vector, one element per row of `data`: which rows are
  reassigned.

- region_sym, hosp_region_sym, zip_sym, hosp_zip_sym:

  Symbols captured from the four source column arguments (raw ESSENCE or
  snake_case names).

- flags:

  The list returned by `validate_geography_cols()`, with `do_region` and
  `do_zip`.

- new_region_col, new_zip_col:

  The user-supplied output column names, or `NULL` to skip that
  geography type.

- sources:

  The list returned by `resolve_geography_sources()`.

- outputs:

  The list returned by `resolve_geography_outputs()`.

- site:

  The site prefix identifying in-state `Region` values.

## Value

`validate_geography_cols()` returns a list with `do_region` and
`do_zip`. `resolve_geography_sources()` returns a list with `region`,
`hosp_region`, `zip`, and `hosp_zip` (strings or `NULL`).
`resolve_geography_outputs()` returns a list with `region` and `zip`
(strings or `NULL`). `reassign_geography()` and `flag_out_of_state()`
return the updated data frame. `warn_site_without_region_match()` and
`inform_*_result()` are called for their conditions.
`resolve_geography_output_col()` returns the normalized output column
name, or `NULL`. `assign_geography_reassignment()` returns `data` with
the geography columns written.

## Details

`validate_geography_cols()` downgrades `do_region`/`do_zip` to `FALSE`
(with an informational message) when a column required for that
geography type is absent. `check_region_col` controls whether
`region_col_str` itself is validated here:
[`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md)
validates it separately afterward, since it is unconditionally required
there for out-of-state detection regardless of which geography types are
requested, whereas
[`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md)
has no such separate requirement and validates it as part of this check.

`resolve_geography_output_col()` resolves a
`new_region_col`/`new_zip_col` argument (a plain string naming the
output column, or `NULL` to skip that geography type) to its
[`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)-normalized
form. It aborts if the name collides with `reserved_col`, the
bookkeeping column (`.out_of_state`/`.facility_geography`) the calling
function itself adds, which would silently break the return-value
contract. `reserved_col` is passed dot-prefixed, as it is referenced
everywhere else, but
[`janitor::make_clean_names()`](https://sfirke.github.io/janitor/reference/make_clean_names.html)
always strips a leading dot, so the comparison strips it from
`reserved_col` too. It also aborts if the resolved name already exists
in `data` unless `overwrite = TRUE`, which is what makes writing to a
new column non-destructive by default and requires an explicit opt-in
before any existing column can be clobbered.

The remaining helpers are the stages the two exported functions share:
`resolve_geography_sources()` resolves the four optional source columns
to strings (or `NULL` when absent); `resolve_geography_outputs()`
resolves both output column names with `resolve_geography_output_col()`;
`reassign_geography()` works out which output columns already exist and
calls `assign_geography_reassignment()`. Only
[`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md)
uses `warn_site_without_region_match()` (a `site` that matches no
`Region` value, such as a typo, the wrong case, or another state's pull,
would otherwise flag every visit as out-of-state without any sign that
something is off) and `flag_out_of_state()`. `"{site}_UNKNOWN"` (for
example `"KY_UNKNOWN"`) is ESSENCE's placeholder for a known-site record
whose residential geography could not be determined; unlike
`"OTHER_REGION"` it carries the site prefix, so it must be tested for
explicitly or the prefix check would leave it classified as in-state.
`inform_treating_result()` and `inform_facility_result()` report the
outcome.

`assign_geography_reassignment()` applies the "preserve original values,
then reassign from the hospital columns" logic common to both functions.
`mask` marks which rows are reassigned:
[`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md)
passes `.out_of_state` (selective),
[`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md)
an all-`TRUE` vector (universal). The `*_target_exists` flags say
whether the output column already held a value (which
`resolve_geography_output_col()` only allows with `overwrite = TRUE`);
`original_region`/`original_zip_code` are only added in that case, since
writing to a genuinely new column already leaves the original untouched.
They are populated only where `mask` is `TRUE`, so an unmodified row is
always identifiable by `is.na(original_region)`.
