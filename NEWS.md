# sysPrep 0.1.0

* **New feature:** `link_encounters()` gains an optional `fallback_visit_col`
  argument. By default (`NULL`), a row missing `visit_col` is never merged
  with another row solely because they share that same missing value (see
  the NA-key bug fix below) -- correct in general, but it means a real
  split episode (an ED row and a direct-admit row for the same visit) with
  `Visit_ID` missing on both sides is left as two unmatched rows instead
  of one linked episode, since `visit_col` alone can't confirm they match.
  `fallback_visit_col` names a secondary identifier (e.g. `C_BioSense_ID`,
  observed in real production data to be assigned identically to both
  rows of such a split episode even when `Visit_ID` is missing on both) to
  use for that specific case: a row missing `visit_col` is matched to
  another row sharing `facility_col` and the same `fallback_visit_col`
  value instead of being left unmatchable. Rows with a real `visit_col`
  value are never affected, and omitting the argument preserves the
  original NA-key behavior exactly. Reported against real production data
  in a downstream ETL pipeline (149 real split episodes sharing a missing
  `Visit_ID` and a matching `C_BioSense_ID`, confirmed via `distinct()`
  after dropping the differing `HasBeen_`-derived field).
* **Bug fix:** `classify_duplicates()` no longer emits a spurious base R
  warning ("replacement element 1 has 1 row to replace 0 rows") on a
  genuinely clean pull with zero duplicates. `janitor::adorn_pct_formatting()`
  errors on a 0-row tabyl; `$overall` is now built directly as an empty
  tibble in that case instead of being routed through it.
* **Bug fix:** `dedupe()`, `summarize_duplicates()`, `classify_duplicates()`,
  and `link_encounters()` no longer collapse rows that share a missing
  `facility_col` or `visit_col` value into a single group.
  `dplyr::group_by()` (and `.by =`) follow SQL's `GROUP BY` convention of
  treating every `NA` as equal to every other `NA` for grouping purposes,
  even though `NA == NA` evaluates to `NA` everywhere else in R. A missing
  identifier means a row's true identity is unknown, not confirmed to
  match every other row with a missing identifier. Previously, several
  rows sharing a missing `Visit_ID` at the same facility were silently
  treated as one duplicated visit: `dedupe()` discarded all but one of
  them, `summarize_duplicates()`/`classify_duplicates()` reported them as
  duplicated when they weren't, and `link_encounters()` ran its
  episode-reconciliation logic (`has_been_` flag `max()`, field merging)
  across genuinely unrelated visits sharing one synthesized
  `.episode_id`. Each of these functions now treats a row with a missing
  key as its own distinct record and emits an informational message
  (`rlang::inform()`, suppressible via `verbose = FALSE` where that
  argument exists) reporting how many rows were affected.
* **Behavior change:** `dedupe()`, `summarize_duplicates()`,
  `classify_duplicates()`, `review_facility_ed_visits()`, and
  `link_encounters()` now prefer `Hospital`/`C_BioSense_Facility_ID` over
  `HospitalName` as the default `facility_col`, whenever `Hospital` is
  present in the data, falling back to `HospitalName` only if it isn't.
  `Hospital` is a stable numeric identifier; `HospitalName` is a display
  string that changes on a facility rename or rebrand, so grouping by name
  can silently split one facility's rows into two across a rename, or
  merge two different facilities that briefly share a display name. An
  explicitly supplied `facility_col` always overrides this preference
  exactly as given. `filter_care_setting()`'s `facility_col` is
  deliberately unchanged, since it matches against `fix_facility_type_vector`'s
  exact facility *name* strings; that function already exposes a separate,
  ID-preferring `facility_id_col`/`fix_facility_id_vector` for the same
  durability benefit. **If you have code that assumes `dedupe()` (or the
  other affected functions) group by `HospitalName`/`hospital_name` by
  default, and your data includes `Hospital`, update it to reference
  `hospital`/`Hospital` instead, or pass `facility_col = HospitalName`
  explicitly to keep the old behavior.** The five affected functions'
  `facility_col` argument now defaults to `NULL` (was a fixed column
  name) so that `args()`/the Usage line accurately reflect that the real
  default is resolved at runtime rather than printing a fixed default
  that's no longer accurate; this matches how `order_by`/`date_col`
  already behave elsewhere in the package.
* **Bug fix** in `link_encounters()`: when deriving `patient_class` from
  `HasBeen_` flags (the fallback path used when `C_Patient_Class_List` is
  absent), the `has_been_e`/`has_been_admitted`/etc. columns were silently
  lost from the output for any row that never came from
  `inpatient_admission_data` directly, showing as `NA` on single-row
  episodes, and, worse, as an incorrectly reconciled value (e.g.
  `has_been_e = 0` on a merged episode that genuinely included an ED
  visit) on multi-row merged episodes. `link_encounters()` now preserves
  each row's true original `HasBeen_` values across the pivot, so every
  episode shows correct `0`/`1` values, never `NA`, and never an
  incorrect reconciled value.
* **Bug fix** in `link_encounters()`: in the same `HasBeen_`-flag fallback
  path, when `ed_data` contained both `HasBeenAdmitted` and `HasBeenI`,
  `HasBeenI` was dropped from `ed_data` entirely to keep it from
  contributing a redundant "Admitted" row to the patient-class pivot,
  which discarded its real `0`/`1` values for every `ed_data` row. After
  `bind_rows()` with `inpatient_admission_data`, only rows sourced from
  the inpatient pull retained a real `has_been_i` value; every ED-pull row
  showed `NA`. `HasBeenI` is now excluded from the pivot without being
  removed from the data, so its true value is preserved on every row.
* The message issued when `HasBeenO = 1` visits are present is now an
  informational message (suppressible via `verbose = FALSE`) rather than
  a warning, and no longer implies these visits will show `patient_class
  = "Outpatient"` in the default collapsed output; they won't, whenever
  the same episode also includes an ED or inpatient-admission record
  (the norm for `link_encounters()`'s two-pull input), since only the
  primary row's `patient_class` survives collapsing. `HasBeenO = 1` is
  ordinary co-occurring ESSENCE data, not a data quality concern.
* Added `CITATION.cff` (Citation File Format) at the package root for
  GitHub's "Cite this repository" feature and Zenodo DOI metadata, alongside
  the existing `inst/CITATION` used by `citation("sysPrep")`.
* Functions validated against the NSSP ESSENCE `va_er` (Patient Location,
  Full Details) and `va_hosp` (Facility Location, Full Details) data sources.
* `dedupe()`: Remove duplicate ESSENCE records with flexible keep strategy.
* `summarize_duplicates()`: Summarize duplicate counts by facility.
* `classify_duplicates()`: Classify duplication mechanism by type. Supports
  `verbose` to suppress informational messages.
* `filter_care_setting()`: Filter to valid emergency and inpatient care
  settings. Supports `verbose` to suppress informational messages, and
  `fix_facility_id_vector` to correct known facilities by their stable
  `Hospital`/`C_BioSense_Facility_ID` value, more durable across facility
  name changes than `fix_facility_type_vector`.
* `link_encounters()`: Link ED and inpatient encounters into care episodes,
  merging each episode's rows into one composite row by default
  (`return_format = "collapsed"`); `HasBeen_` flags reconciled via max,
  and `CCDD`/`CCDDParsed`/`CCDDCategory_flat`/`C_Death`/
  `Discharge_Disposition`/`DispositionCategory` reconciled via configurable
  `merge_fields` strategies. `return_format = "long"` preserves the prior
  unmerged output. Supports `verbose` to suppress informational messages.
  **Breaking:** `inpatient_admission_data` is now required; the prior
  single-pull mode (`ed_data` alone) could not detect a genuine direct
  admission (structurally absent from a `HasBeenE = 1` pull) and was a
  no-op on an already-deduplicated ED-to-inpatient escalation, so
  `link_encounters()` now aborts with an actionable message instead of
  silently returning `ed_data` unchanged. Query a second ESSENCE pull
  filtered to `HasBeenAdmitted = 1` (or `HasBeenI = 1`), deduplicate it
  separately, and pass it as `inpatient_admission_data`.
* Added `essence_ed_raw` and `essence_inp_raw`: two small synthetic
  datasets representing separately queried `HasBeenE = 1` and
  `HasBeenAdmitted = 1` ESSENCE pulls, used by `vignette("encounter-linkage")`
  and `link_encounters()`'s own examples to demonstrate two-pull linkage.
  `essence_raw`/`essence_clean` are unchanged by this and continue to
  represent a single realistic ED pull.
* `review_facility_ed_visits()`: Flag facility visit count outliers for QA.
  Supports `verbose` to suppress informational messages.
* `assign_treating_geography()`: Assign treating facility geography to
  out-of-state visits. By default writes to new `new_region_col`/
  `new_zip_col` columns (`"region_hybrid"`/`"zip_code_hybrid"`), leaving
  `region_col`/`zip_col` untouched; set `overwrite = TRUE` to overwrite them
  in place instead. Supports `verbose` to suppress informational messages.
* `assign_facility_geography()`: Assign facility geography to all visits.
  Same `new_region_col`/`new_zip_col`/`overwrite` behavior as
  `assign_treating_geography()`, defaulting to `"region_facility"`/
  `"zip_code_facility"`. Supports `verbose` to suppress informational
  messages.
