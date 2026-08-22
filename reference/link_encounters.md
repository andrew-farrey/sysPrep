# Link ED and inpatient admission records into unified care episodes

Links ED and direct-admit inpatient records sharing the same
`facility_col` x `visit_col` key into a single composite row per true
care episode, and reconciles their field values so information present
on only one of the source rows is not silently discarded. Corrects two
related but distinct duplication mechanisms: the encounter-continuity
data quality issue where a patient's ED discharge and immediate
direct-admit readmission are reported as separate records sharing the
same `Visit_ID` at the same facility, and true direct admissions that
are structurally invisible to a `HasBeenE = 1` query.

## Usage

``` r
link_encounters(
  ed_data,
  inpatient_admission_data = NULL,
  facility_col = HospitalName,
  visit_col = Visit_ID,
  merge_fields = c(CCDD = "union_ccdd", CCDDParsed = "union_ccdd", CCDDCategory_flat =
    "union_delimited", C_Death = "prefer_yes", Discharge_Disposition =
    "prefer_admission", DispositionCategory = "prefer_admission"),
  merge_delimiter = ";",
  return_format = c("collapsed", "long"),
  clean_names = TRUE,
  verbose = TRUE
)
```

## Arguments

- ed_data:

  A deduplicated data frame of ED visits queried with `HasBeenE = 1`.
  Requires `HasBeenE` and at least one of `HasBeenAdmitted`/`HasBeenI`
  (the standard ESSENCE pull fields), or `C_Patient_Class_List` for more
  granular and informative output.

- inpatient_admission_data:

  Optional. A deduplicated data frame of inpatient visits queried with
  `HasBeenAdmitted = 1` or `HasBeenI = 1`. Rows with `HasBeenE = 1` are
  automatically removed to prevent duplicate rows for the same
  underlying record. If `NULL` (default), only visits present in
  `ed_data` are linked.

- facility_col:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Unquoted column name identifying the facility. Defaults to
  `HospitalName`. Accepts both raw ESSENCE names and
  post-[`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)
  equivalents.

- visit_col:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Unquoted column name identifying the visit. Defaults to `Visit_ID`.
  Accepts both raw ESSENCE names and
  post-[`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)
  equivalents.

- merge_fields:

  Named character vector mapping column names (raw ESSENCE names or
  post-[`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)
  equivalents) to a merge strategy: one of `"concat"`,
  `"union_delimited"`, `"union_ccdd"`, `"prefer_yes"`, or
  `"prefer_admission"`. Only used when `return_format = "collapsed"`.
  Defaults to a curated set of ESSENCE fields known to carry information
  only visible in the direct-admit record – see Details. Extend or
  override for other fields as needed.

- merge_delimiter:

  Character string. Delimiter used by the `"union_delimited"` and
  `"union_ccdd"` strategies. Defaults to `";"`, matching ESSENCE's
  convention for `CCDDCategory_flat` and the within-half structure of
  `CCDD`/`CCDDParsed`.

- return_format:

  Character string. One of `"collapsed"` (default) or `"long"`. See
  Details.

- clean_names:

  Logical. If `TRUE` (default), applies
  [`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)
  to standardize column names to snake_case on output.

- verbose:

  Logical. If `FALSE`, suppresses informational messages
  ([`rlang::inform()`](https://rlang.r-lib.org/reference/abort.html));
  warnings and errors are always shown regardless.

## Value

When `return_format = "collapsed"` (default), a data frame with one row
per true care episode, `HasBeen_` flags reconciled via max, and
`merge_fields` columns reconciled per their assigned strategy. When
`return_format = "long"`, a data frame in long format with one row per
visit per patient class, unmerged. Both include episode metadata columns
`.episode_id`, `.patient_class_sequence`, `.episode_n_rows`, and
`.index_encounter`.

## Details

### The care pathway artifact problem

A row showing `HasBeenAdmitted = 1` and `HasBeenE = 0`
(`C_Patient_Class = "I"` or `"D"`) can mean either of two very different
things, and nothing in that single row tells you which:

**The continuity-break artifact.** The patient *was* triaged and treated
in the ED first, but the facility's system closed that encounter as a
discharge instead of tracking the ED-to-inpatient transition as one
continuous record. The result is two records sharing the same
`facility_col` x `visit_col` key – one correctly showing `HasBeenE = 1`,
one showing `HasBeenAdmitted = 1` and `HasBeenE = 0` – that otherwise
look unrelated. The ED record's fields (e.g. `Discharge_Disposition`,
`CCDD`, `C_Death`) reflect only what was known at ED discharge, not the
outcome of the encounter that actually continued. Counting both records
separately double-counts a single real-world event. This is a data
quality artifact, not a distinct clinical pathway.

**The invisibility gap.** A patient admitted directly to an inpatient
unit without ED triage – via physician referral, a pre-arranged
admission, or similar – genuinely has `HasBeenAdmitted = 1` and
`HasBeenE = 0` with no preceding ED record to find. This visit never
appears in a `HasBeenE = 1` query regardless of which syndrome
definition or date range is used. This is a real clinical pathway, not a
data quality problem – but a `HasBeenE = 1`-only pull will always miss
it.

The only way to tell these two cases apart is to check whether a
matching ED record exists under the same `facility_col` x `visit_col`
key. `link_encounters()` does exactly this: it links records sharing
that key (the continuity-break artifact's records already share it – no
cross-`Visit_ID` matching is needed), and, by default, merges each
episode's rows into one composite row so information from the
direct-admit record is reconciled onto the surviving row rather than
discarded.

### Merge behavior (`return_format = "collapsed"`, the default)

Every column matching `has_been_*` is reconciled by taking the max
across the episode's rows – e.g., if the ED row has
`HasBeenAdmitted = 0` and the direct-admit row has
`HasBeenAdmitted = 1`, the merged row correctly shows
`HasBeenAdmitted = 1`.

Columns named in `merge_fields` are reconciled using the strategy
assigned to them:

- `"concat"`:

  Starting from the primary row's value, appends each other row's
  non-empty value if it is not already a substring of the accumulated
  text (`"; "`-separated). Generic free text.

- `"union_delimited"`:

  Splits each row's value on `merge_delimiter`, takes the union of
  unique parts (preserving order of first appearance), rejoins with the
  same delimiter.

- `"union_ccdd"`:

  Specific to ESSENCE's `CC-values|DD-values` structure
  (`CCDD`/`CCDDParsed`). Splits on `|` into CC/DD halves (fixed by the
  ESSENCE convention, not configurable), splits each half on
  `merge_delimiter`, unions unique values within each half separately,
  rejoins.

- `"prefer_yes"`:

  If any row's value is affirmative – case-insensitive `"Yes"`, or
  `1`/`"1"` for 0/1-coded flag columns – the merged value is that row's
  affirmative value. Otherwise falls back to the primary row's value.

- `"prefer_admission"`:

  Uses the value from whichever row's `patient_class` is `"Inpatient"`,
  `"Direct Admit"`, or `"Admitted"`, if such a row has a non-missing
  value for the field. Otherwise falls back to the primary row's value.

Any column not a `HasBeen_` flag and not listed in `merge_fields` takes
its value from the **primary row**: the `"ED"`-class row if one exists
in the episode, else the first row in original order.

Set `return_format = "long"` to get the diagnostic long-format output
instead – one row per patient-class per episode, with no merge applied.
Useful for inspecting the raw linkage mechanism directly.

### Single-pull vs. two-pull approach

**Single-pull** (`inpatient_admission_data = NULL`, the default): Uses
`C_Patient_Class_List` or `HasBeen_` flags within the ED pull to detect
visits that transitioned to inpatient care.

**Two-pull** (`inpatient_admission_data` supplied): Supplements the ED
pull with a separately queried inpatient pull (`HasBeenAdmitted = 1`).
Rows with `HasBeenE = 1` are automatically removed from the inpatient
pull to prevent duplicate rows for the same underlying record. This is
the recommended approach when direct admission volume is material to the
surveillance question, and is required to detect the continuity-break
artifact when the direct-admit record is entirely absent from the ED
pull (i.e. `HasBeenE = 0` on that record, so it would never appear in a
`HasBeenE = 1` query).

**Do not row-bind `ed_data` and `inpatient_admission_data` into one data
frame and call
[`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
on the combined result instead of using the two-pull approach above.**
[`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)'s
`keep` strategies are not aware of the distinction between an ED record
and its corresponding direct-admit record – both just look like two rows
sharing a `facility_col` x `visit_col` key – and will discard one of
them based on `order_by` rather than merging them, silently and
unpredictably reducing either the ED or the direct-admit count depending
on which record's `Arrived_Date_Time` happens to win. Always deduplicate
each pull separately, then pass both to `link_encounters()`.

### Linking key and its limitation

Records are linked by `facility_col` \\\times\\ `visit_col`
(`HospitalName` \\\times\\ `Visit_ID` by default).

**Limitation:** if a facility's HL7 feed assigns a genuinely different
`Visit_ID` to the inpatient leg of a care episode, `link_encounters()`
cannot detect the relationship – the two records will appear as separate
episodes. This is a distinct scenario from the continuity-break artifact
above (which assumes the `Visit_ID` is shared) and is not addressed by
this function. If your data includes `C_Unique_Patient_ID` (MRN),
cross-referencing collapsed output against a patient-level deduplication
pass is a reasonable additional QA step for this scenario.

### Patient class derivation: HasBeen\_ pivot (standard)

`HasBeen_` flag columns (`HasBeenE`, `HasBeenAdmitted`/`HasBeenI`,
`HasBeenO`) are convenience columns that ESSENCE derives from
`C_Patient_Class_List` – they are easier to interpret and are the fields
most existing pulls and case definitions already include, so
`link_encounters()` uses them by default. They are pivoted to long
format, with each flag with value `1` contributing one row.
`HasBeenAdmitted` is preferred over `HasBeenI` when both are present.

### Patient class derivation: C_Patient_Class_List (optional, more granular)

`C_Patient_Class_List` is the underlying ESSENCE-computed field the
`HasBeen_` flags are themselves derived from: an alphabetic,
deduplicated list of all `C_Patient_Class` values present across
messages sharing the same ESSENCE ID (e.g., `"E"`, `"EI"`, `"EIO"`).
When present, it is used in place of the `HasBeen_` pivot, since it
distinguishes patient classes (e.g. Direct Admit vs. Inpatient, or
Observation/Outpatient/Obstetrics/ Pre-admit/Recurring) that the
`HasBeen_` flags do not represent. For more granular and informative
output, add `C_Patient_Class_List` to your ESSENCE API pull fields.
Splitting each character maps to the PHIN VADS "Patient Class (Syndromic
Surveillance)" value set (concept codes and preferred names, verified
against
<https://phinvads.cdc.gov/vads/ViewValueSet.action?id=564F8F8B-E1DE-E411-8970-0017A477041A>).
`link_encounters()`'s own derived `patient_class` output values (`"ED"`,
`"Inpatient"`, `"Direct Admit"`, etc.) are shortened working labels, not
required to match these preferred names verbatim:

|      |                          |
|------|--------------------------|
| Code | PHIN VADS preferred name |
| `D`  | Direct admit             |
| `E`  | Emergency                |
| `I`  | Inpatient                |
| `V`  | Observation patient      |
| `B`  | Obstetrics               |
| `O`  | Outpatient               |
| `P`  | Preadmit                 |
| `R`  | Recurring patient        |

### Chronological ordering of `.patient_class_sequence`

`.patient_class_sequence` reflects the actual order encounters occurred
in, not alphabetical order – e.g. `"Direct Admit->ED"` when the
direct-admit record's timestamp precedes the ED record's, which is the
reverse of what typically indicates the continuity-break artifact (an ED
visit that transitions into a direct-admit readmission, not a direct
admit that precedes an ED visit). Ordering uses the first available
field, per row, in this priority:

1.  **`C_Patient_Class_MDT_Updates`** (requires `C_Patient_Class_List`).
    A concatenated list of timestamps positionally aligned with
    `C_Patient_Class_List`, giving the exact moment each class was
    assigned – the only field that can order two classes assigned within
    a single record (e.g. `"EI"`). Rows where the two lists' lengths
    disagree fall back to the next tier.

2.  **`C_Visit_Date_Time`**. Applied per record – all classes derived
    from one record share that record's timestamp, so this only
    differentiates classes across separate records sharing the same
    `facility_col` x `visit_col` key (i.e. the ED record vs. the
    direct-admit record in the continuity-break artifact, or in the
    two-pull approach).

3.  **`Date` + `Time`** (both required). Combined into a timestamp when
    neither field above is present.

If none of these fields are present (or none can be parsed) anywhere in
the data, `link_encounters()` warns once and `.patient_class_sequence`
falls back to alphabetical order for every episode. Within a single
episode, if only some classes have a usable timestamp, timed classes are
ordered first and untimed classes are appended last.

### Episode metadata columns

Present regardless of `return_format`. In collapsed output, these
describe the episode the collapsed row was built from (e.g.
`.episode_n_rows = 2` on a collapsed row means two original records were
merged into it).

- `.episode_id`:

  A character key combining `facility_col` and `visit_col`, shared
  across all rows belonging to the same care episode.

- `.patient_class_sequence`:

  All patient classes for the episode in chronological order and
  collapsed, e.g., `"Direct Admit->ED"` when the direct admit occurred
  first – see Details.

- `.episode_n_rows`:

  Number of original rows the episode was built from before merging.

- `.index_encounter`:

  In long format, `TRUE` on the row that survives filtering to one row
  per episode. In collapsed format, always `TRUE` (retained for schema
  consistency with long format).

## See also

[`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
for deduplication prior to linking;
[`filter_care_setting()`](https://andrew-farrey.github.io/sysPrep/reference/filter_care_setting.md)
for care setting filtering;
[`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md)
for geography attribution.

## Examples

``` r
ed_clean <- essence_raw |>
  dedupe(order_by = Arrived_Date_Time, keep = "last") |>
  filter_care_setting(
    fix_facility_type_vector = c("Hillside FSED", "Downtown Emergency Services")
  )
#> The following `FacilityType` values are not in `keep_types` and will be excluded:
#>   - Medical Specialty
#>   - Primary Care

# Default: one row per true encounter, merged
episodes <- link_encounters(ed_clean)
#> Using `HasBeen_` flags to derive complete encounters of care since `C_Patient_Class_List` is not present in `ed_data`.
nrow(episodes)
#> [1] 160

# Inspect the distribution of care pathways
episodes |>
  dplyr::count(.patient_class_sequence, sort = TRUE)
#> # A tibble: 3 × 2
#>   .patient_class_sequence     n
#>   <chr>                   <int>
#> 1 ED                        122
#> 2 Admitted->ED               36
#> 3 Admitted                    2

# Long format: inspect the raw linkage mechanism directly
episodes_long <- link_encounters(ed_clean, return_format = "long")
#> Using `HasBeen_` flags to derive complete encounters of care since `C_Patient_Class_List` is not present in `ed_data`.

if (FALSE) { # \dontrun{
# Two-pull linkage with a custom merge strategy for a site-specific field
ed_clean        <- essence_ed        |> dedupe(order_by = Arrived_Date_Time)
inpatient_clean <- essence_inpatient |> dedupe(order_by = Arrived_Date_Time)

episodes_full <- link_encounters(
  ed_clean, inpatient_clean,
  merge_fields = c(TriageNotes = "concat")
)
} # }
```
