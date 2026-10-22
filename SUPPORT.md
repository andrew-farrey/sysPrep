# Getting help with sysPrep

## Where to start

- **Documentation:** <https://andrew-farrey.github.io/sysPrep/> has a
  reference page for every function and four articles that explain what
  each step does and why. In R,
  [`?dedupe`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md),
  [`?link_encounters`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md),
  and
  [`vignette("getting-started", package = "sysPrep")`](https://andrew-farrey.github.io/sysPrep/articles/getting-started.md)
  open the same material.
- **Something looks wrong:** open an issue with the [bug report
  form](https://github.com/andrew-farrey/sysPrep/issues/new/choose).
- **Your site’s data behaves differently:** use the “Site or data source
  behavior” form in the same place.

## Before you post

`sysPrep` works with surveillance records. **Do not post patient-level
data, identifiable facility information, or anything covered by a data
use agreement.** Reproduce the problem with the built-in synthetic
datasets (`essence_raw`, `essence_clean`, `essence_ed_raw`,
`essence_inp_raw`) or a few invented rows.

A good report is a minimal reproducible example; the
[reprex](https://reprex.tidyverse.org/) package makes one easy.

## What this project does not cover

`sysPrep` preprocesses data that you have already pulled. Questions
about ESSENCE accounts, the ESSENCE API, or retrieving data (including
the `Rnssp` package) are best directed to your NSSP site administrator
or the relevant project.
