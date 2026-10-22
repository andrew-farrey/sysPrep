## What this changes and why

<!-- Link the issue this addresses (e.g. "Fixes #12"). For a non-trivial change,
please open an issue first; see CONTRIBUTING.md. -->

## Does it change existing output?

<!-- For valid input, does any function now return something different from
before (values, column names, column types, row order, messages)? If yes,
describe exactly what changes and why, and say how a user keeps the old
behavior. If no, say "No change to existing output". -->

## Checklist

- [ ] Described in `NEWS.md` (user-facing changes only)
- [ ] Tests added in `tests/testthat/`; a bug fix has a test that fails without it
- [ ] Roxygen updated and `devtools::document()` run
- [ ] `devtools::check()` passes with 0 errors, 0 warnings, 0 notes
- [ ] `lintr::lint_package()` and `spelling::spell_check_package()` are clean
- [ ] Coverage is still 100% (`covr::package_coverage()`)
- [ ] No real patient, facility, or geographic data added anywhere
