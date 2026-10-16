# Articles

### Getting Started

Core concepts and the recommended preprocessing pipeline

- [Getting Started with
  sysPrep](https://andrew-farrey.github.io/sysPrep/articles/getting-started.md):

  The four ESSENCE data quality problems that `sysPrep` addresses, and
  the recommended pipeline from a raw pull to analysis-ready data.

### Deep Dives

Detailed methodology for each preprocessing stage, including the
underlying data quality mechanisms, when each step is worth applying,
and the operational consequences of omitting it.

- [Understanding and Resolving Duplicate Records in ESSENCE
  Data](https://andrew-farrey.github.io/sysPrep/articles/deduplication-and-classification.md):

  Why ESSENCE `dataDetails` pulls contain more than one row for a single
  visit, how to quantify and classify those rows, and how to choose a
  [`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
  strategy.

- [Linking ED and Inpatient Records for Accurate Burden
  Estimation](https://andrew-farrey.github.io/sysPrep/articles/encounter-linkage.md):

  How one care episode can be split across separately queried ED and
  inpatient pulls, and how
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  links the pieces for unduplicated burden counts.

- [Geographic Attribution for Out-of-State and Unknown Residence
  Visits](https://andrew-farrey.github.io/sysPrep/articles/geography-assignment.md):

  Why out-of-state and unknown-residence visits drop out of region-based
  rollups, and how
  [`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md)
  and
  [`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md)
  differ.
