# Changelog

## sysPrep 0.0.0.9000

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
  informational messages.
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
