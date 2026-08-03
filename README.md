# sysPrep <img src="man/figures/logo.png" align="right" height="138" alt="sysPrep logo" />

<!-- badges: start -->
[![R-CMD-check](https://github.com/andrew-farrey/sysPrep/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/andrew-farrey/sysPrep/actions/workflows/R-CMD-check.yaml)
[![Codecov test coverage](https://codecov.io/gh/andrew-farrey/sysPrep/branch/master/graph/badge.svg)](https://app.codecov.io/gh/andrew-farrey/sysPrep?branch=master)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

## Overview

`sysPrep` provides formalized preprocessing methods for syndromic surveillance
data from the National Syndromic Surveillance Program (NSSP) Electronic
Surveillance System for the Early Notification of Community-based Epidemics
([ESSENCE](https://www.cdc.gov/nssp/)) API.

These methods are **not required** to perform case counting, cluster
detection, or anomaly detection with ESSENCE data -- many surveillance
questions tolerate the data quality issues below without materially affecting
conclusions. They are most valuable for **small-count, high-impact case
definitions**, where external validity and minimizing false-positive
clusters/anomalies matter most. Raw ESSENCE data pulls can present four
categories of data quality issues that bias case counts or distort
cluster/anomaly detection if left unaddressed:

| Problem | Functions |
|---------|-----------|
| **Duplicate records** -- multiple rows per visit due to visit date changes to the initial record, patient ID corrections, and patient class transitions | `dedupe()`, `summarize_duplicates()`, `classify_duplicates()` |
| **Non-emergency providers** -- facilities without EDs, and free-standing emergency departments (FSEDs) onboarded to ESSENCE with a non-emergency `FacilityType`, included in pulls | `filter_care_setting()`, `review_facility_ed_visits()` |
| **Invisible direct admissions** -- HasBeenE = 1 queries structurally exclude patients admitted without ED triage | `link_encounters()` |
| **Out-of-state and unknown-residence visits** -- discarding these understates facility burden | `assign_treating_geography()`, `assign_facility_geography()` |

These preprocessing steps are applied by practitioners manually and
inconsistently when they choose to apply them at all. `sysPrep` formalizes
them into a reproducible, documented pipeline, developed through their
operational use in production surveillance workflows.

### Validated Data Sources

`sysPrep`'s functions have been validated against records pulled from the
following NSSP ESSENCE data sources. Both sources return ED visit and
inpatient admission records, so all exported functions apply to either:

| ESSENCE `datasource` code | Full name | Used by |
|----------------------------|-----------|---------|
| `va_er`, `va_hosp` | Patient Location (Full Details), Facility Location (Full Details) | `dedupe()`, `summarize_duplicates()`, `classify_duplicates()`, `filter_care_setting()`, `review_facility_ed_visits()`, `link_encounters()`, `assign_treating_geography()`, `assign_facility_geography()` |

Column names and expected value formats (e.g., `{SITE}_{REGION}` region strings,
`HasBeenE`/`HasBeenAdmitted` flags) reflect these two data sources. Pulls
from other ESSENCE data sources may require column renaming before use.

## Installation

```r
# install.packages("remotes")
remotes::install_github("andrew-farrey/sysPrep")
```

## Quick Start

```r
library(sysPrep)

# Inspect raw data quality before preprocessing
summarize_duplicates(essence_raw)
classify_duplicates(essence_raw)

# Full preprocessing pipeline
clean <- essence_raw |>
  # Step 1: Remove duplicate records (retain most recently transmitted)
  dedupe(order_by = Arrived_Date_Time, keep = "last") |>
  # Step 2: Filter to ED and inpatient facilities; correct FSED types
  filter_care_setting(
    fix_facility_type_vector = c("Hillside FSED", "Downtown Emergency Services")
  ) |>
  # Step 3: Assign treating facility geography to out-of-state visits
  assign_treating_geography(preserve_original_geographies = TRUE)

# Check for facility-level anomalies
clean |> review_facility_ed_visits(method = "both", date_col = Date)
```

For encounter linkage with a separate inpatient pull:

```r
# Deduplicate both pulls
ed_clean        <- essence_ed        |> dedupe(order_by = Arrived_Date_Time)
inpatient_clean <- essence_inpatient |> dedupe(order_by = Arrived_Date_Time)

# Link into care episodes (captures direct admissions);
# one merged row per true encounter by default
episodes <- link_encounters(ed_clean, inpatient_clean)

# Distribution of care pathways
episodes |>
  dplyr::count(.patient_class_sequence, sort = TRUE)
```

## Documentation

Full documentation including function reference pages and methodological
vignettes is available at: **https://andrew-farrey.github.io/sysPrep**

Vignettes:
- [Getting Started](https://andrew-farrey.github.io/sysPrep/articles/getting-started.html)
- [Understanding and Resolving Duplicate Records](https://andrew-farrey.github.io/sysPrep/articles/deduplication-and-classification.html)
- [Linking ED and Inpatient Records](https://andrew-farrey.github.io/sysPrep/articles/encounter-linkage.html)
- [Geographic Attribution](https://andrew-farrey.github.io/sysPrep/articles/geography-assignment.html)

## Related Packages

- [`Rnssp`](https://github.com/CDCgov/Rnssp): NSSP ESSENCE API access,
  alerting algorithms, and syndromic surveillance utilities. `sysPrep`
  is designed to operate on data returned by `Rnssp` API calls -- it
  offers an optional preprocessing layer between raw API output and case
  counting or cluster detection, for surveillance programs where that
  layer adds value.

## Acknowledgements

`sysPrep` relies heavily on several packages whose authors deserve
explicit credit:

- **[`janitor`](https://sfirke.github.io/janitor/)** (Sam Firke) --
  `clean_names()` is called on entry and exit of every function in the
  package. The column-name agnosticism that lets `sysPrep` accept both
  raw ESSENCE PascalCase and post-`clean_names()` snake_case is built
  entirely on this foundation.

- **[`dplyr`](https://dplyr.tidyverse.org/),
  [`rlang`](https://rlang.r-lib.org/), and
  [`tidyr`](https://tidyr.tidyverse.org/)** (Hadley Wickham, Lionel Henry,
  and the tidyverse team) -- the data manipulation backbone and the
  `inform()` / `warn()` / `abort()` messaging infrastructure used
  throughout.

- **[`cli`](https://cli.r-lib.org/)** (Gábor Csárdi) -- the rich formatted
  output for the `print.essence_dup_summary()` and
  `print.essence_dup_classified()` S3 methods.

- **[`Rnssp`](https://github.com/CDCgov/Rnssp)** (Gbedegnon Roseric
  Azondekon, Michael Sheppard, and the CDC BioSense team) -- the upstream
  package that handles NSSP ESSENCE API authentication and data retrieval.
  `sysPrep` would have no data to preprocess without it.

The methods formalized in `sysPrep` were developed through applied opioid
overdose surveillance and cluster detection work using NSSP ESSENCE data.

## Citation

If you use `sysPrep` in published work, please cite the package directly:

```r
citation("sysPrep")
```

## License

MIT © Andrew Farrey
