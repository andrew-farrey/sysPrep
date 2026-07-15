## R CMD check results

0 errors | 0 warnings | 0 notes

## Test environments

* local Windows 11, R 4.5.2 (2025-10-31 ucrt), x86_64-w64-mingw32 -- checked
* GitHub Actions: ubuntu-latest (release, devel), ubuntu-latest (oldrel-1),
  macOS-latest (release), windows-latest (release) -- TODO: run after initial
  GitHub push, then replace this line with actual results
* win-builder (devel, release) -- TODO: run via `devtools::check_win_devel()`
  / `check_win_release()` and replace this line with actual results
* R-hub -- TODO: run via `rhub::rhub_check()` after GitHub Actions are set up
  (rhub v2 requires a GitHub Actions workflow) and replace this line with
  actual results

## Downstream dependencies

None (new package).

## Notes for CRAN reviewers

This package formalizes preprocessing methods developed through applied 
syndromic surveillance research using the NSSP ESSENCE API. All example 
data are fully synthetic with no real patient, facility, or geographic 
identifiers. The package does not connect to any external API directly; 
it operates on data frames returned by the ESSENCE API (accessible via 
the separate `Rnssp` package). Functions have been validated against 
records from the ESSENCE `va_er` (Patient Location, Full Details) and 
`va_hosp` (Facility Location, Full Details) data sources.
