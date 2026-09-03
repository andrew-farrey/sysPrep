## R CMD check results

0 errors | 0 warnings | 0 notes

## Test environments

* local Windows 11, R 4.5.2 (2025-10-31 ucrt), x86_64-w64-mingw32: 0 errors,
  0 warnings, 0 notes (checked 2026-09-01)
* GitHub Actions (`.github/workflows/R-CMD-check.yaml`, runs on every push):
  ubuntu-latest (release, devel), ubuntu-latest (oldrel-1), macOS-latest
  (release), windows-latest (release); all passing as of the latest push
  (2026-09-01); see the Actions tab for current status
* win-builder (R-devel, R Under development (unstable) (2026-08-31 r90457
  ucrt), x86_64-w64-mingw32): checked 2026-09-01, re-checked same day
  after fixes below: 1 NOTE, only the two expected/false-positive
  sub-items remain (see below).
  win-builder (R-release): TODO, run via `devtools::check_win_release()`
  and replace this line with actual results
* R-hub: TODO, run `rhub::rhub_setup()` (writes
  `.github/workflows/rhub.yaml`, not yet added), commit + push, then
  `rhub::rhub_check()`, and replace this line with actual results

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

This is a new submission. The win-builder (R-devel) check reported one
NOTE, expected for a first submission:

* "Possibly misspelled words in DESCRIPTION: NSSP, Syndromic, syndromic":
  these are correct. NSSP is the National Syndromic Surveillance
  Program (a real, proper-noun program name), and "syndromic" is a
  standard epidemiological term, not a typo.
* The URL/file-URI items flagged in that same check (a redirecting
  pkgdown URL and a `CITATION.cff` link in README.md not present in the
  built tarball) were fixed 2026-09-01 and should not reappear on the
  next win-builder run.
