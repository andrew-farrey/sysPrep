## R CMD check results

Local and GitHub Actions: 0 errors | 0 warnings | 0 notes. The win-builder
(R-devel) run reported 1 NOTE, explained below.

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
  win-builder (R-release, R 4.6.1, Windows Server 2022): checked
  2026-10-27 on version 0.1.0.9000: 1 NOTE (new submission; the development
  version number, which goes away when submitting a release version; the
  same two expected spelling false positives as above). Examples, tests,
  vignettes and the manual all built and passed
  (<https://win-builder.r-project.org/Nn3MCfWMyEHG/>)
* R-hub (`rhub::rhub_check()`, workflow in `.github/workflows/rhub.yaml`),
  run 2026-10-27 on version 0.1.0.9000: linux (R-devel), windows (R-devel),
  macos-arm64 (R-devel), ubuntu-release, ubuntu-next, gcc16 and vnu all
  passed; ubuntu-clang, atlas, nold, macos (R-devel) and m1-san also passed.
  The `nosuggests` platform (a container with none of the `Suggests`
  packages installed) reported one ERROR, and only that one: examples and
  tests ran, but re-building the vignettes failed with "there is no package
  called 'rmarkdown'", because `rmarkdown` (the vignette builder) is in
  `Suggests` and the container does not have it

## Downstream dependencies

None (new package).

## Notes for CRAN reviewers

This package formalizes preprocessing methods developed through applied 
syndromic surveillance research using the NSSP ESSENCE API. All example 
data are fully synthetic with no real patient, facility, or geographic 
identifiers. The package does not connect to any external API directly; 
it operates on data frames returned by the ESSENCE API (accessible via 
the separate `Rnssp` package). The package is designed for ESSENCE
`dataDetails` pulls from the `va_er` (Patient Location, Full Details) and
`va_hosp` (Facility Location, Full Details) data sources, which it was
developed and tested against.

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
