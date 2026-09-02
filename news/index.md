# Changelog

## sysPrep 0.0.0.9000

- **Bug fix** in
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md):
  when deriving `patient_class` from `HasBeen_` flags (the fallback path
  used when `C_Patient_Class_List` is absent), the
  `has_been_e`/`has_been_admitted`/etc. columns were silently lost from
  the output for any row that never came from `inpatient_admission_data`
  directly – showing as `NA` on single-row episodes, and, worse, as an
  incorrectly reconciled value (e.g. `has_been_e = 0` on a merged
  episode that genuinely included an ED visit) on multi-row merged
  episodes.
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  now preserves each row’s true original `HasBeen_` values across the
  pivot, so every episode shows correct `0`/`1` values – never `NA`, and
  never an incorrect reconciled value.
- Added `CITATION.cff` (Citation File Format) at the package root for
  GitHub’s “Cite this repository” feature and Zenodo DOI metadata,
  alongside the existing `inst/CITATION` used by `citation("sysPrep")`.
- Functions validated against the NSSP ESSENCE `va_er` (Patient
  Location, Full Details) and `va_hosp` (Facility Location, Full
  Details) data sources.
- [`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md):
  Remove duplicate ESSENCE records with flexible keep strategy.
- [`summarize_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/summarize_duplicates.md):
  Summarize duplicate counts by facility.
- [`classify_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/classify_duplicates.md):
  Classify duplication mechanism by type. Supports `verbose` to suppress
  informational messages.
- [`filter_care_setting()`](https://andrew-farrey.github.io/sysPrep/reference/filter_care_setting.md):
  Filter to valid emergency and inpatient care settings. Supports
  `verbose` to suppress informational messages, and
  `fix_facility_id_vector` to correct known facilities by their stable
  `Hospital`/`C_BioSense_Facility_ID` value – more durable across
  facility name changes than `fix_facility_type_vector`.
- [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md):
  Link ED and inpatient encounters into care episodes, merging each
  episode’s rows into one composite row by default
  (`return_format = "collapsed"`) – `HasBeen_` flags reconciled via max,
  and `CCDD`/`CCDDParsed`/`CCDDCategory_flat`/`C_Death`/
  `Discharge_Disposition`/`DispositionCategory` reconciled via
  configurable `merge_fields` strategies. `return_format = "long"`
  preserves the prior unmerged output. Supports `verbose` to suppress
  informational messages. **Breaking:** `inpatient_admission_data` is
  now required – the prior single-pull mode (`ed_data` alone) could not
  detect a genuine direct admission (structurally absent from a
  `HasBeenE = 1` pull) and was a no-op on an already-deduplicated
  ED-to-inpatient escalation, so
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  now aborts with an actionable message instead of silently returning
  `ed_data` unchanged. Query a second ESSENCE pull filtered to
  `HasBeenAdmitted = 1` (or `HasBeenI = 1`), deduplicate it separately,
  and pass it as `inpatient_admission_data`.
- Added `essence_ed_raw` and `essence_inp_raw`: two small synthetic
  datasets representing separately queried `HasBeenE = 1` and
  `HasBeenAdmitted = 1` ESSENCE pulls, used by
  [`vignette("encounter-linkage")`](https://andrew-farrey.github.io/sysPrep/articles/encounter-linkage.md)
  and
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)’s
  own examples to demonstrate two-pull linkage.
  `essence_raw`/`essence_clean` are unchanged by this and continue to
  represent a single realistic ED pull.
- [`review_facility_ed_visits()`](https://andrew-farrey.github.io/sysPrep/reference/review_facility_ed_visits.md):
  Flag facility visit count outliers for QA. Supports `verbose` to
  suppress informational messages.
- [`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md):
  Assign treating facility geography to out-of-state visits. By default
  writes to new `new_region_col`/ `new_zip_col` columns
  (`"region_hybrid"`/`"zip_code_hybrid"`), leaving
  `region_col`/`zip_col` untouched; set `overwrite = TRUE` to overwrite
  them in place instead. Supports `verbose` to suppress informational
  messages.
- [`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md):
  Assign facility geography to all visits. Same
  `new_region_col`/`new_zip_col`/`overwrite` behavior as
  [`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md),
  defaulting to `"region_facility"`/ `"zip_code_facility"`. Supports
  `verbose` to suppress informational messages.
