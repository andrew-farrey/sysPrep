## Submission

This is a new submission of sysPrep 0.2.0 (the package is not yet on CRAN).
Version 0.1.0 was released only on GitHub and archived on Zenodo
(<https://doi.org/10.5281/zenodo.23603551>); 0.2.0 follows a substantial
refactoring and independent review of that release (see `NEWS.md`).

## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new submission (the only NOTE, from "checking CRAN incoming
  feasibility").
* win-builder also lists "Possibly misspelled words in DESCRIPTION: NSSP,
  Syndromic, syndromic". These are correct: NSSP is the National Syndromic
  Surveillance Program (a proper-noun program name) and "syndromic" is a
  standard epidemiological term, not a typo.

## Test environments

* local Windows 11, R 4.6.1 (ucrt), x86_64-w64-mingw32:
  `R CMD check --as-cran` on the built 0.2.0 tarball, 0 errors, 0 warnings,
  1 NOTE (new submission); 354 test blocks, 100% line coverage
* GitHub Actions (`.github/workflows/R-CMD-check.yaml`, every push):
  ubuntu-latest (release, devel, oldrel-1), macOS-latest (release),
  windows-latest (release)
* win-builder (R-release, R 4.6.2 (2026-10-29 ucrt), Windows Server 2022):
  checked 2026-11-05 on 0.2.0, 1 NOTE (new submission; the spelling
  false positives described above); examples, tests, vignettes and both
  manuals OK (<https://win-builder.r-project.org/6oaB661MfgJV/>)
* R-hub (`rhub::rhub_check()`, `.github/workflows/rhub.yaml`), 12 platforms
  (linux, windows, macos, macos-arm64, ubuntu-release, ubuntu-next,
  ubuntu-clang, gcc16, atlas, nold, m1-san, vnu): all 12 passed
  (run of 2026-11-05 on the commit that became 0.2.0)
  The R-hub `nosuggests` platform (a container with none of the `Suggests`
  packages installed) is deliberately not run: it fails every time at
  "re-building of vignette outputs" ("there is no package called
  'rmarkdown'"), because the vignette builder (`knitr`, `rmarkdown`) is in
  `Suggests` as usual for a package with vignettes. In earlier runs on
  0.1.0.9000 (2026-10-27, 2026-10-30, 2026-11-05) that was its only failure;
  examples and tests passed with no `Suggests` installed.

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

`Authors@R` lists the U.S. Centers for Disease Control and Prevention as
funder (`role = "fnd"`); the funding statement is also in the README and in
`?sysPrep`.
