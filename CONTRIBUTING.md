# Contributing to sysPrep

Thank you for considering a contribution to `sysPrep`. This package
formalizes preprocessing methods for NSSP ESSENCE syndromic surveillance
data, so changes are held to a high bar for correctness and for
stability: people run these functions inside production surveillance
pipelines, and a change that quietly alters output is costly even when
it is well meant.

This guide is short on purpose. If something here is unclear, open an
issue and ask.

## Never post real data

`sysPrep` handles surveillance records. **Do not post patient-level
data, identifiable facility information, or anything covered by a data
use agreement in an issue, pull request, or discussion.** That includes
screenshots and copied console output.

Reproduce problems with the built-in synthetic datasets (`essence_raw`,
`essence_clean`, `essence_ed_raw`, `essence_inp_raw`) or with a few
invented rows. If you accidentally post sensitive data, contact the
maintainer right away (see
[SECURITY.md](https://andrew-farrey.github.io/sysPrep/SECURITY.md)) so
it can be removed.

## Reporting a bug or suggesting a feature

Please use the issue forms. The most useful reports include:

- a minimal reproducible example built from synthetic data (the
  [reprex](https://reprex.tidyverse.org/) package helps),
- the ESSENCE data source the pull came from (`va_er`, `va_hosp`, or
  other),
- the output of
  [`sessionInfo()`](https://rdrr.io/r/utils/sessionInfo.html), including
  the `sysPrep` version.

If a function behaves differently at your site (a different duplication
mechanism, different facility types, different `Region` formats), use
the “Site or data source behavior” form. Those reports are especially
valuable because the package was developed against a limited set of
sites.

For a non-trivial change, **open an issue before writing code** so we
can agree on the approach. It saves you from doing work that conflicts
with the design contract below.

## Design contract

These are the rules the package follows. A pull request that breaks one
is likely to be asked to change.

1.  **Existing output must not change silently.** Changing what a
    function returns for valid input is a behavior change. It needs an
    issue, an entry in `NEWS.md`, and a stated reason. Prefer adding an
    optional argument whose default keeps the current behavior.
2.  **Inform, warn, abort, in that order of severity.** Use
    [`rlang::inform()`](https://rlang.r-lib.org/reference/abort.html)
    for expected, actionable messages,
    [`rlang::warn()`](https://rlang.r-lib.org/reference/abort.html) for
    unexpected but non-fatal conditions, and
    [`rlang::abort()`](https://rlang.r-lib.org/reference/abort.html)
    only when continuing would produce silently wrong results. Every
    function that has a `verbose` argument must silence all of its
    messages with `verbose = FALSE` (warnings still show).
3.  **`clean_names` is optional.** Functions normalize names internally
    so that column arguments accept raw ESSENCE names (`HospitalName`)
    or snake_case (`hospital_name`). With `clean_names = FALSE` they
    must return the caller’s own column names.
4.  **Identifiers are text.** Linking keys such as `Hospital`,
    `Visit_ID`, and `C_BioSense_ID` have no numeric meaning and are
    compared as text.
5.  **A missing key is an unknown identity, not a match.** Rows with a
    missing `facility_col` or `visit_col` are never merged with each
    other.
6.  **`HasBeen_` flags are always 0 or 1.** Never `NA`. A flag that is 1
    on either side of a linked encounter stays 1.
7.  **No real data anywhere in the package.** Example data and tests use
    synthetic records only.

## Development setup

``` r

# install.packages(c("devtools", "testthat", "roxygen2", "lintr", "covr"))
devtools::load_all()     # load the package from source
devtools::test()         # run the test suite
devtools::document()     # regenerate man/ and NAMESPACE after editing roxygen
devtools::check()        # R CMD check; aim for 0 errors, 0 warnings, 0 notes
```

The package requires `dplyr >= 1.2.0`.

## Pull request checklist

The change is described in `NEWS.md` (user-facing changes only).

New behavior has tests in `tests/testthat/`, and a bug fix has a test
that fails without the fix. Coverage is kept at 100%; check with
`covr::package_coverage()`.

Roxygen documentation is updated and `devtools::document()` has been
run. Internal helpers are documented with `@keywords internal`, not
`@noRd`, so `?helper_name` works. Documentation explains what a function
does, why, where it applies, and how to read the result; please keep
that level of detail.

`devtools::check()` passes, and `lintr::lint_package()` reports nothing.

`spelling::spell_check_package()` is clean; add genuine domain terms to
`inst/WORDLIST`.

No real patient, facility, or geographic data was added anywhere.

## Code style

- Follow the [tidyverse style guide](https://style.tidyverse.org/).
  Lines are at most 80 characters (enforced by `.lintr`).
- Use the native pipe `|>`,
  [`rlang::abort()`](https://rlang.r-lib.org/reference/abort.html)/`warn()`/`inform()`
  with `call = rlang::caller_env()` so errors name the function the user
  called, and
  [`rlang::arg_match()`](https://rlang.r-lib.org/reference/arg_match.html)
  for choice arguments.
- Keep exported functions short: put each stage in a documented internal
  helper.
- Write prose without em dashes; use commas, colons, or semicolons.
- Wrap code, argument, and field names in backticks in documentation.

## Code of conduct

Please note that this project is released with a [Contributor Code of
Conduct](https://andrew-farrey.github.io/sysPrep/CODE_OF_CONDUCT.md). By
contributing, you agree to abide by its terms.
