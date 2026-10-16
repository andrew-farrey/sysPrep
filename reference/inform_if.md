# Console output helpers

Internal helpers for messages and printed reports.

## Usage

``` r
inform_if(verbose, ...)

print_lines(x, ...)

cli_duplicate_ids_footer(x)
```

## Arguments

- verbose:

  Logical. Whether to emit the message.

- ...:

  Passed to
  [`rlang::inform()`](https://rlang.r-lib.org/reference/abort.html) (for
  `inform_if()`) or to [`print()`](https://rdrr.io/r/base/print.html)
  (for `print_lines()`).

- x:

  For `print_lines()`, any printable object; for
  `cli_duplicate_ids_footer()`, an `essence_dup_summary` or
  `essence_dup_classified` object.

## Value

`inform_if()` returns `NULL` invisibly. `print_lines()` returns a
character vector. `cli_duplicate_ids_footer()` is called for its cli
output side effect.

## Details

`inform_if()` emits an
[`rlang::inform()`](https://rlang.r-lib.org/reference/abort.html)
message only when `verbose` is `TRUE`. It gates informational
(non-fatal, non-warning) messages in functions that have a `verbose`
argument;
[`rlang::warn()`](https://rlang.r-lib.org/reference/abort.html) and
[`rlang::abort()`](https://rlang.r-lib.org/reference/abort.html) calls
never go through it and always fire.

`print_lines()` returns the lines `print(x, ...)` would write as a
character vector, so a [`format()`](https://rdrr.io/r/base/format.html)
method can embed them with
[`cli::cli_verbatim()`](https://cli.r-lib.org/reference/cli_verbatim.html).

`cli_duplicate_ids_footer()` renders the identical "Duplicated Visit
IDs" footer shared by the
[`format()`](https://rdrr.io/r/base/format.html) methods of
`essence_dup_summary` and `essence_dup_classified` objects. It must be
called inside
[`cli::cli_format_method()`](https://cli.r-lib.org/reference/cli_format_method.html).
