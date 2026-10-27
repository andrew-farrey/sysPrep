# Changelog

## sysPrep (development version)

- **Behavior change:**
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  now stops with an error when `ed_data` and `inpatient_admission_data`
  carry different `HasBeen_` flag columns (for example `HasBeenAdmitted`
  in one pull and only `HasBeenI` in the other). The other pull’s rows
  would hold `NA` in a flag that ESSENCE never leaves missing, which
  silently corrupted flag counts and the admission-flag choice. Query
  both pulls with the same `HasBeen_` fields. A call that previously ran
  on mismatched pulls now errors; calls whose pulls match are unchanged.
  The documentation gains a “Required fields” section listing what each
  pull must carry.
- **New message:** with `verbose = TRUE`,
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  reports how many episodes hold more than one record from the same pull
  (the same facility and visit more than once in a pull), which are
  merged into one episode; run
  [`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
  on each pull first. It changes no output.
- **Wording:** the package description and the encounter-linkage
  vignette title now say “improved burden estimation” rather than
  “accurate”.
- **Behavior change:**
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  now keeps the most severe `DispositionCategory` in a linked episode,
  whichever record carries it. The default strategy for that field is
  the new `"prefer_severity"` (replacing `"prefer_admission"`):
  `DECEASED` ranks above `TRANSFERRED`, which ranks above `DISCHARGED`
  and `ADMIT` (equal), which rank above `UNKNOWN` and a missing value.
  Previously the first admission-class row’s value won, so an ED record
  that also carried `HasBeenAdmitted = 1` and read `DISCHARGED` could
  hide a death or transfer on the linked inpatient record. When the
  merged value is `DECEASED`, `C_Death` is also set to affirmative for
  that linked episode (`"Yes"` for ESSENCE’s own `Yes`/`No`; `"1"` or
  `1` when the column is already 0/1, read from the whole column so a
  text `"0"`/`"1"` column stays 0/1). This derives `C_Death` from the
  category, so it can change a `"No"` that both records carried, and a
  record that is not linked is never changed. Equally severe values
  (`ADMIT` and `DISCHARGED`) resolve to the inpatient pull’s record,
  which reflects the whole encounter of care: an ED `ADMIT` gives way to
  the inpatient record’s `DISCHARGED`, and the result does not depend on
  whether the ED record also carries `HasBeenAdmitted`.
  `Discharge_Disposition` now uses the new `"follow_severity"` strategy:
  it takes the value from the same record that supplied
  `DispositionCategory`, so the two fields agree whenever that record
  has a value (when it has none, the `"prefer_admission"` value is used
  and the two can differ). Episodes whose records agree are unchanged.
  To keep the old behavior, pass `merge_fields` with
  `"prefer_admission"` for these fields.
- **Bug fix:**
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  split a record with a missing `facility_col` or `visit_col` value into
  one visit per patient class (an `"ED"` row and an `"Admitted"` row
  from one `HasBeenE = 1`, `HasBeenAdmitted = 1` record became two
  collapsed rows, counted twice). The record now stays one episode, and
  the missing-key message counts records. Records with a single patient
  class, and every record with a key, are unchanged; only the numeric
  suffix of `.episode_id` after such a record can shift.
- **Bug fix:** numeric identifiers of 16 or more digits were written in
  scientific notation and rounded when held as text, so two different
  `Visit_ID` values could link as one visit in
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md).
  Whole numbers are now written in full.
  [`filter_care_setting()`](https://andrew-farrey.github.io/sysPrep/reference/filter_care_setting.md)
  uses the same conversion, so a numeric `fix_facility_id_vector`
  containing round numbers such as `100000` (which
  [`as.character()`](https://rdrr.io/r/base/character.html) writes as
  `"1e+05"`) now matches a text `Hospital` column instead of silently
  matching nothing.
- **Improvement:** when `ed_data` and `inpatient_admission_data` hold
  the same column in incompatible types,
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  now stops with a message that names the function and the two pulls
  instead of a `bind_rows()` error.
- **Documentation:**
  [`review_facility_ed_visits()`](https://andrew-farrey.github.io/sysPrep/reference/review_facility_ed_visits.md)
  now states that `visits_per_day` is the count divided by one number of
  days for every facility, so it flags the same facilities as raw counts
  and adds the unit (it makes pulls of different durations comparable);
  it does not by itself improve dropout detection.
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  states that every row of `inpatient_admission_data` is labeled
  `"Direct Admit"` whatever its own `C_Patient_Class_List` says, and
  recommends reading key columns as text.
  [`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md)’s
  `@return` says when `region_col` is overwritten. `.episode_n_rows` is
  documented as the number of patient-class rows (a record carrying
  several classes counts once per class), not the number of records, so
  it should not be used on its own to count linked episodes.

## sysPrep 0.1.0

- **Bug fix:** `clean_names = FALSE` now returns the input’s own column
  names in
  [`filter_care_setting()`](https://andrew-farrey.github.io/sysPrep/reference/filter_care_setting.md),
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md),
  [`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md),
  [`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md),
  and
  [`review_facility_ed_visits()`](https://andrew-farrey.github.io/sysPrep/reference/review_facility_ed_visits.md);
  it previously still returned snake_case names (only
  [`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
  honored it). Columns the function adds keep their own names.
- **Bug fix:**
  [`review_facility_ed_visits()`](https://andrew-farrey.github.io/sysPrep/reference/review_facility_ed_visits.md)
  normalized `visits_per_day` by the days *that facility* sent data, so
  a facility that stopped sending partway through the pull scored the
  same as one that sent every day. It now divides by the number of
  distinct dates in the whole pull (`n_days` still reports the
  facility’s own days). `.outlier_method` now records the criterion that
  fired (`"percentile"`, `"iqr"`, or `"percentile+iqr"`) instead of
  echoing the `method` argument. The documentation now says that
  `method = "percentile"` ranks the tails: with the default thresholds
  it flags the lowest and highest facility in a small pull whether or
  not either is abnormal; `method = "iqr"` flags only values outside the
  spread.
- **Bug fix:** `filter_care_setting(fix_facility_type_regex = )` no
  longer overwrites the facility type with `NA` for a row whose facility
  name is missing (which then dropped the row at the `keep_types` step)
  or lists `NA` as a matched facility.
- **Bug fix:**
  [`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md)
  no longer requires the patient `Region` and `ZipCode` columns, which
  it never reads when every row is reassigned; without them it
  previously skipped that geography type with a misleading “not found”
  message.
- **Bug fix:** `.index_encounter` in
  `link_encounters(return_format = "long")` now marks exactly one row
  per episode: the first `"ED"` row, else the first row (the same row
  the collapsed output is built from). It could previously be absent (a
  multi-row episode with no ED row, or an `NA` class) or repeated (two
  ED rows), so long-format counts disagreed with the collapsed row
  count. Collapsed output is unaffected (the column is `TRUE` there). No
  other column of
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  output changes.
- **Bug fix:**
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  now aborts when the linking columns (`facility_col`, `visit_col`, and
  `fallback_visit_col`) are missing from `inpatient_admission_data`,
  where it previously linked nothing without a message.
- **New argument:**
  [`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
  and
  [`summarize_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/summarize_duplicates.md)
  gain `verbose` (default `TRUE`), so the missing-key message can be
  silenced as in every other function that reports messages.
- **Behavior change:**
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  now holds its linking keys, the facility column (default `Hospital`),
  `visit_col` (default `Visit_ID`) and `fallback_visit_col`, as text in
  the output, whatever type each pull delivered them in. These
  identifiers have no numeric meaning, and a CSV read can return one
  pull’s keys as numbers and the other’s as text, which previously
  failed in `bind_rows()`. Numbers are written in full (`100000`, not
  `1e+05`). Keys that were already text (as the ESSENCE `dataDetails`
  API returns them) are unchanged; a numeric `Hospital` now comes back
  as text, so convert it back after the call if you need numbers.
  `.episode_id` is unchanged.
  [`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md),
  [`summarize_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/summarize_duplicates.md)
  and
  [`classify_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/classify_duplicates.md)
  already compared these keys as text and still return each column in
  the type it arrived in.
- **Bug fix:** the `"concat"` merge strategy in
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  skipped a value whenever it appeared anywhere inside the text already
  collected, even inside a longer word or code, so detail present in
  only one record could be lost (`"fall"` inside `"waterfall"`, the
  diagnosis code `"R10.9"` inside `"R10.90"`). It now treats a value as
  already present only when it appears as whole words or whole codes
  (ignoring case, punctuation and spacing), so complaint text, diagnosis
  codes and SNOMED codes found in one record but not the other are kept.
  `"concat"` is not in the default `merge_fields`.
- **Performance:**
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  builds its episode metadata with whole-column operations rather than a
  per-episode call, several times faster on a 290,000-row pull with
  identical output; `dedupe(keep = "most_complete")` counts each row’s
  non-missing values once instead of once per group.
- **Documentation:**
  [`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)’s
  `visit_col` no longer lists patient-level identifiers
  (`C_Unique_Patient_ID`, MRN) as alternatives, and its example using
  one is removed: they are shared by all of a patient’s visits, so using
  one collapses repeat visits.
  [`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
  also documents that a row with a missing `order_by` value sorts last.
  The documentation also now states that `fallback_visit_col` only links
  two rows that are both missing `visit_col`; that
  `.patient_class_sequence` lists classes with identical or missing
  timestamps alphabetically, which carries no clinical meaning; that
  [`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md)
  takes the site prefix from `site` rather than parsing it from the
  data; that `.out_of_state` is `TRUE` for another state,
  `OTHER_REGION`, `{site}_UNKNOWN`, and a missing `Region`; that the
  `percent` in `classify_duplicates()$overall` is the share of
  duplicated visit groups; and that `n_biosense_ids` is reported but not
  used to classify. Wording that claimed more than the code establishes
  (“approximating both residence-based and incidence-based burden”, “a
  close approximation of hospital-level cluster detection”) was
  softened.
- **Input validation:** every exported function now checks its arguments
  up front and aborts with a message that names the offending argument.
  This covers a non-data-frame `data` (or
  `ed_data`/`inpatient_admission_data`); a `TRUE`/`FALSE` switch
  (`verbose`, `clean_names`, `overwrite`, …) that is `NA` or not length
  1; a `percentile_low`/`percentile_high` outside `[0, 1]` or reversed,
  or a negative `iqr_multiplier`, in
  [`review_facility_ed_visits()`](https://andrew-farrey.github.io/sysPrep/reference/review_facility_ed_visits.md);
  a non-character `keep_types`, `fix_to`, or `fix_facility_type_regex`
  in
  [`filter_care_setting()`](https://andrew-farrey.github.io/sysPrep/reference/filter_care_setting.md);
  and a non-string `site` or output column name in the geography
  functions. A malformed `merge_fields` in
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  (for example an unnamed vector, which was previously ignored without a
  message) now aborts too. Errors are attributed to the exported
  function the user called rather than an internal helper, and choice
  arguments (`keep`, `method`, `return_format`) report their valid
  values through
  [`rlang::arg_match()`](https://rlang.r-lib.org/reference/arg_match.html).
- **Bug fix:**
  [`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md)
  now warns when no `Region` value begins with the `site` prefix (for
  example `site = "ky"`, since matching is case-sensitive, or a pull
  from a different state than `site`). Previously every visit was
  silently flagged as out-of-state.
- **Behavior change:** [`print()`](https://rdrr.io/r/base/print.html)
  for `essence_dup_summary` and `essence_dup_classified` objects now
  writes the whole report to standard output, through new
  [`format()`](https://rdrr.io/r/base/format.html) methods, instead of
  splitting it between the message and output streams.
  [`capture.output()`](https://rdrr.io/r/utils/capture.output.html),
  [`sink()`](https://rdrr.io/r/base/sink.html), and knitr now see the
  complete report.
- **Interface change:**
  [`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)’s
  signature now shows `keep`’s valid values
  (`c("first", "last", "most_complete")`; the default is still
  `"first"`), and
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)’s
  signature no longer shows a misleading
  `inpatient_admission_data = NULL` default. The argument was already
  required: omitting it, or passing `NULL`, aborts with the same message
  as before.
- **Documentation:** parameters shared by several functions (`data`,
  `facility_col`, `visit_col`, `clean_names`, `verbose`, the geography
  column arguments, and others) are now documented once and inherited
  with `@inheritParams`, so their wording can no longer drift between
  help pages. The [`format()`](https://rdrr.io/r/base/format.html) and
  [`print()`](https://rdrr.io/r/base/print.html) methods for
  `essence_dup_summary` and `essence_dup_classified` are documented on
  [`?summarize_duplicates`](https://andrew-farrey.github.io/sysPrep/reference/summarize_duplicates.md)
  and
  [`?classify_duplicates`](https://andrew-farrey.github.io/sysPrep/reference/classify_duplicates.md).
  Internal helpers are documented for maintainers (for example
  [`?resolve_col`](https://andrew-farrey.github.io/sysPrep/reference/resolve_col.md),
  [`?key_has_na_mask`](https://andrew-farrey.github.io/sysPrep/reference/key_has_na_mask.md),
  [`?merge_strategies`](https://andrew-farrey.github.io/sysPrep/reference/merge_strategies.md));
  they are marked `@keywords internal`, so they do not appear in the
  reference index.
- **Internal:** removed `collapse_episode()`, an unused earlier
  implementation of the episode-collapsing step in
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md),
  and reorganized the helpers into thematic `R/utils-*.R` files. The
  long exported functions are now short pipelines over documented stage
  helpers, each group on one help page that lists the stages in order:
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  ([`?check_inpatient_admission_data`](https://andrew-farrey.github.io/sysPrep/reference/check_inpatient_admission_data.md)),
  [`review_facility_ed_visits()`](https://andrew-farrey.github.io/sysPrep/reference/review_facility_ed_visits.md)
  ([`?check_percentile_order`](https://andrew-farrey.github.io/sysPrep/reference/check_percentile_order.md)),
  [`filter_care_setting()`](https://andrew-farrey.github.io/sysPrep/reference/filter_care_setting.md)
  ([`?apply_type_correction`](https://andrew-farrey.github.io/sysPrep/reference/apply_type_correction.md)),
  the two geography functions
  ([`?validate_geography_cols`](https://andrew-farrey.github.io/sysPrep/reference/validate_geography_cols.md)),
  [`classify_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/classify_duplicates.md)
  ([`?resolve_classification_cols`](https://andrew-farrey.github.io/sysPrep/reference/resolve_classification_cols.md)),
  and
  [`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)/[`summarize_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/summarize_duplicates.md)
  ([`?sort_for_dedupe`](https://andrew-farrey.github.io/sysPrep/reference/sort_for_dedupe.md)).
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  went from 580 lines at cyclomatic complexity 49 to 97 lines at
  complexity 6. The restructuring itself changes no function’s output,
  messages, or warnings; the behavior changes are the separate items
  listed above.
- **Dependencies:** the minimum `dplyr` version is now 1.2.0, the
  release that added
  [`dplyr::recode_values()`](https://dplyr.tidyverse.org/reference/recode-and-replace-values.html),
  which
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  already used. `stats` and `utils` are now declared in `Imports`.
- **New feature:**
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  gains an optional `fallback_visit_col` argument. By default (`NULL`),
  a row missing `visit_col` is never merged with another row solely
  because they share that same missing value (see the NA-key bug fix
  below); correct in general, but it means a real split episode (an ED
  row and a direct-admit row for the same visit) with `Visit_ID` missing
  on both sides is left as two unmatched rows instead of one linked
  episode, since `visit_col` alone can’t confirm they match.
  `fallback_visit_col` names a secondary identifier
  (e.g. `C_BioSense_ID`, observed in real production data to be assigned
  identically to both rows of such a split episode even when `Visit_ID`
  is missing on both) to use for that specific case: a row missing
  `visit_col` is matched to another row sharing `facility_col` and the
  same `fallback_visit_col` value instead of being left unmatchable.
  Rows with a real `visit_col` value are never affected, and omitting
  the argument preserves the original NA-key behavior exactly. Reported
  against real production data in a downstream ETL pipeline (149 real
  split episodes sharing a missing `Visit_ID` and a matching
  `C_BioSense_ID`, confirmed via `distinct()` after dropping the
  differing `HasBeen_`-derived field).
- **Bug fix:**
  [`classify_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/classify_duplicates.md)
  no longer emits a spurious base R warning (“replacement element 1 has
  1 row to replace 0 rows”) on a genuinely clean pull with zero
  duplicates.
  [`janitor::adorn_pct_formatting()`](https://sfirke.github.io/janitor/reference/adorn_pct_formatting.html)
  errors on a 0-row tabyl; `$overall` is now built directly as an empty
  tibble in that case instead of being routed through it.
- **Bug fix:**
  [`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md),
  [`summarize_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/summarize_duplicates.md),
  [`classify_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/classify_duplicates.md),
  and
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  no longer collapse rows that share a missing `facility_col` or
  `visit_col` value into a single group.
  [`dplyr::group_by()`](https://dplyr.tidyverse.org/reference/group_by.html)
  (and `.by =`) follow SQL’s `GROUP BY` convention of treating every
  `NA` as equal to every other `NA` for grouping purposes, even though
  `NA == NA` evaluates to `NA` everywhere else in R. A missing
  identifier means a row’s true identity is unknown, not confirmed to
  match every other row with a missing identifier. Previously, several
  rows sharing a missing `Visit_ID` at the same facility were silently
  treated as one duplicated visit:
  [`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
  discarded all but one of them,
  [`summarize_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/summarize_duplicates.md)/[`classify_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/classify_duplicates.md)
  reported them as duplicated when they weren’t, and
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  ran its episode-reconciliation logic (`has_been_` flag
  [`max()`](https://rdrr.io/r/base/Extremes.html), field merging) across
  genuinely unrelated visits sharing one synthesized `.episode_id`. Each
  of these functions now treats a row with a missing key as its own
  distinct record and emits an informational message
  ([`rlang::inform()`](https://rlang.r-lib.org/reference/abort.html),
  suppressible via `verbose = FALSE` where that argument exists)
  reporting how many rows were affected.
- **Behavior change:**
  [`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md),
  [`summarize_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/summarize_duplicates.md),
  [`classify_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/classify_duplicates.md),
  [`review_facility_ed_visits()`](https://andrew-farrey.github.io/sysPrep/reference/review_facility_ed_visits.md),
  and
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  now prefer `Hospital`/`C_BioSense_Facility_ID` over `HospitalName` as
  the default `facility_col`, whenever `Hospital` is present in the
  data, falling back to `HospitalName` only if it isn’t. `Hospital` is a
  stable numeric identifier; `HospitalName` is a display string that
  changes on a facility rename or rebrand, so grouping by name can
  silently split one facility’s rows into two across a rename, or merge
  two different facilities that briefly share a display name. An
  explicitly supplied `facility_col` always overrides this preference
  exactly as given.
  [`filter_care_setting()`](https://andrew-farrey.github.io/sysPrep/reference/filter_care_setting.md)‘s
  `facility_col` is deliberately unchanged, since it matches against
  `fix_facility_type_vector`’s exact facility *name* strings; that
  function already exposes a separate, ID-preferring
  `facility_id_col`/`fix_facility_id_vector` for the same durability
  benefit. **If you have code that assumes
  [`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
  (or the other affected functions) group by
  `HospitalName`/`hospital_name` by default, and your data includes
  `Hospital`, update it to reference `hospital`/`Hospital` instead, or
  pass `facility_col = HospitalName` explicitly to keep the old
  behavior.** The five affected functions’ `facility_col` argument now
  defaults to `NULL` (was a fixed column name) so that
  [`args()`](https://rdrr.io/r/base/args.html)/the Usage line accurately
  reflect that the real default is resolved at runtime rather than
  printing a fixed default that’s no longer accurate; this matches how
  `order_by`/`date_col` already behave elsewhere in the package.
- **Bug fix** in
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md):
  when deriving `patient_class` from `HasBeen_` flags (the fallback path
  used when `C_Patient_Class_List` is absent), the
  `has_been_e`/`has_been_admitted`/etc. columns were silently lost from
  the output for any row that never came from `inpatient_admission_data`
  directly, showing as `NA` on single-row episodes, and, worse, as an
  incorrectly reconciled value (e.g. `has_been_e = 0` on a merged
  episode that genuinely included an ED visit) on multi-row merged
  episodes.
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  now preserves each row’s true original `HasBeen_` values across the
  pivot, so every episode shows correct `0`/`1` values, never `NA`, and
  never an incorrect reconciled value.
- **Bug fix** in
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md):
  in the same `HasBeen_`-flag fallback path, when `ed_data` contained
  both `HasBeenAdmitted` and `HasBeenI`, `HasBeenI` was dropped from
  `ed_data` entirely to keep it from contributing a redundant “Admitted”
  row to the patient-class pivot, which discarded its real `0`/`1`
  values for every `ed_data` row. After `bind_rows()` with
  `inpatient_admission_data`, only rows sourced from the inpatient pull
  retained a real `has_been_i` value; every ED-pull row showed `NA`.
  `HasBeenI` is now excluded from the pivot without being removed from
  the data, so its true value is preserved on every row.
- The message issued when `HasBeenO = 1` visits are present is now an
  informational message (suppressible via `verbose = FALSE`) rather than
  a warning, and no longer implies these visits will show
  `patient_class = "Outpatient"` in the default collapsed output; they
  won’t, whenever the same episode also includes an ED or
  inpatient-admission record (the norm for
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)’s
  two-pull input), since only the primary row’s `patient_class` survives
  collapsing. `HasBeenO = 1` is ordinary co-occurring ESSENCE data, not
  a data quality concern.
- Added `CITATION.cff` (Citation File Format) at the package root for
  GitHub’s “Cite this repository” feature and Zenodo DOI metadata,
  alongside the existing `inst/CITATION` used by `citation("sysPrep")`.
- Designed for ESSENCE `dataDetails` pulls from the NSSP ESSENCE `va_er`
  (Patient Location, Full Details) and `va_hosp` (Facility Location,
  Full Details) data sources, which the package was developed and tested
  against.
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
  `Hospital`/`C_BioSense_Facility_ID` value, more durable across
  facility name changes than `fix_facility_type_vector`.
- [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md):
  Link ED and inpatient encounters into care episodes, merging each
  episode’s rows into one composite row by default
  (`return_format = "collapsed"`); `HasBeen_` flags reconciled via max,
  and `CCDD`/`CCDDParsed`/`CCDDCategory_flat`/`C_Death`/
  `Discharge_Disposition`/`DispositionCategory` reconciled via
  configurable `merge_fields` strategies. `return_format = "long"`
  preserves the prior unmerged output. Supports `verbose` to suppress
  informational messages. **Breaking:** `inpatient_admission_data` is
  now required; the prior single-pull mode (`ed_data` alone) could not
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
