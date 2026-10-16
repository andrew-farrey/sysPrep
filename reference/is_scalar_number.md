# Validate the arguments of exported functions

Internal argument checkers called at the top of every exported function.
Each aborts with a classed `rlang_error` whose message names the
offending argument, attributed to the exported function the user
actually called (via `call`) rather than to the checker. They exist so a
wrong argument fails with a plain message instead of an error raised
from deep inside a dplyr verb or from a base R `if ()` ("missing value
where TRUE/FALSE needed").

## Usage

``` r
is_scalar_number(x)

check_data_frame(x, arg = rlang::caller_arg(x), call = rlang::caller_env())

check_flag(x, arg = rlang::caller_arg(x), call = rlang::caller_env())

check_string(
  x,
  allow_null = FALSE,
  arg = rlang::caller_arg(x),
  call = rlang::caller_env()
)

check_character(
  x,
  allow_null = FALSE,
  arg = rlang::caller_arg(x),
  call = rlang::caller_env()
)

check_number(
  x,
  lower = -Inf,
  upper = Inf,
  arg = rlang::caller_arg(x),
  call = rlang::caller_env()
)
```

## Arguments

- x:

  The value to check.

- arg:

  The argument name to use in the error message. Defaults to the
  caller's expression for `x`.

- call:

  The environment the error is attributed to. Defaults to the caller's
  frame, i.e. the exported function.

- allow_null:

  Logical. If `TRUE`, `NULL` passes the check.

- lower, upper:

  Inclusive numeric bounds for `check_number()`.

## Value

`is_scalar_number()` returns a single logical. The `check_*()` functions
return `x` invisibly when it is valid, and otherwise abort.

## Details

By default `arg` is `rlang::caller_arg(x)`, the expression the user
passed to the *calling function*, so `check_data_frame(ed_data)` reports
`ed_data`. `is_scalar_number()` is the non-aborting predicate behind
`check_number()`.
