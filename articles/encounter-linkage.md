# Linking ED and Inpatient Records for Accurate Burden Estimation

## The Care Pathway Artifact Problem

ESSENCE has no mechanism to detect when a record with `HasBeenE = 0` and
`HasBeenAdmitted = 1` is actually the continuation of a `HasBeenE = 1`
record submitted moments earlier at the same facility for the same
visit, rather than a genuinely independent admission. A single row
showing `HasBeenAdmitted = 1` and `HasBeenE = 0`
(`C_Patient_Class = "I"`) can mean either of two very different things:

- **A true direct admission.** The patient was referred from primary
  care, outpatient care, or urgent care – or admitted based on a
  pre-arranged plan – and genuinely never went through the ED at this
  facility. This is a real clinical pathway, not a data quality problem.
- **A mis-submitted continuity break.** The patient *was* triaged and
  treated in the ED first, but the facility’s system closed that
  encounter as a discharge instead of tracking the ED-to-inpatient
  transition as one continuous record. The result is two records – one
  correctly showing `HasBeenE = 1`, one showing `HasBeenAdmitted = 1`
  and `HasBeenE = 0` – that share the same `facility_col x visit_col`
  key but otherwise look, to ESSENCE, like two unrelated encounters.
  This is a data quality artifact, not a distinct clinical pathway.

Nothing in a single row distinguishes these two cases. The only way to
tell them apart is to check whether a matching ED record exists under
the same `facility_col x visit_col` key – which is exactly what
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
does.

This has a direct, structural consequence for burden estimation. ESSENCE
has no built-in capacity to deduplicate a mis-submitted direct-admit
record against its originating ED visit. Running a `HasBeenE = 1` query
and combining it with an otherwise-identical `HasBeenE = 0` /
`HasBeenAdmitted = 1` query – expecting the sum to be an accurate
“severe healthcare visit” census – does not produce one: some proportion
of the records in the second query already exist as a separate ED visit
in the first, and combining them without deduplication double-counts
that encounter. At the same time, genuinely new direct admissions in the
second query are exactly what you’re trying to capture.
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
resolves both problems at once: records sharing a
`facility_col x visit_col` key are merged into one true encounter, while
direct-admit records with no matching ED record are retained as their
own distinct encounters.

In Kentucky’s overdose surveillance data, some of the decline in the
`HasBeenE = 1` trend over time is genuinely explained by growth in the
`HasBeenE = 0` / `HasBeenAdmitted = 1` trend – but not as much as
naively binning the two would suggest, since some proportion of that
apparent direct-admit growth is the same double-counting artifact
described above, not a new encounter. Reimbursement or clinical-protocol
changes, improving HL7/EHR data quality over time, or both together are
plausible contributors to a genuine pathway shift, but this can’t be
attributed to either cause specifically. Practitioners unaware of this
risk face it in two directions: naively summing separately-queried
`HasBeenE = 1` and direct-admit counts overstates the true combined
severe-visit census, while naively comparing the two trends to explain a
decline in one against growth in the other overstates how much of that
decline reflects a genuine pathway shift.

> **How common is this, and would I know if it were happening in my
> data?** This isn’t a widely documented ESSENCE data quality issue.
> Using `HasBeenE = 1` and direct-admit data together for burden
> estimation isn’t itself a widely formalized practice in ESSENCE – in
> print or elsewhere – so the risk rarely surfaces. It came out of
> record-level review of Kentucky’s data, not published guidance. Most
> users working from pre-aggregated `HasBeenE = 1` and
> `HasBeenAdmitted = 1` counts through timeSeries or tableBuilder have
> no way to detect it, since the double-counted encounters are
> indistinguishable from genuine direct admits at the aggregate level.

[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
addresses this by combining an ED pull with a separately queried
inpatient pull, then constructing unified care episodes that count each
patient interaction once regardless of which pathway they followed.

> **Could you address this by filtering to `HasBeenAdmitted = 1`
> instead?** A query filtered to `HasBeenAdmitted = 1` returns all
> admitted visits – including those with `HasBeenE = 1`, which are
> already present in the ED pull. Using only the inpatient pull would
> miss all ED visits that did not result in admission, which represent
> the majority of emergency encounters.
> [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
> resolves this by binding both pulls and marking the ED row as the
> index encounter for visits that appear in both.

## Patient Class Derivation

[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
supports two methods for determining patient class from ESSENCE data.
The preferred method uses `C_Patient_Class_List`; the fallback uses
`HasBeen_` indicator flags.

### Preferred: `C_Patient_Class_List`

`C_Patient_Class_List` is an ESSENCE-computed field that contains an
alphabetic, deduplicated list of all `C_Patient_Class` values present
across all messages sharing the same ESSENCE ID. For a patient who was
registered in the ED (`E`) and subsequently admitted (`I`), the field
contains `"EI"`.

The patient class codes follow the HL7 Patient Class standard as adopted
by the Public Health Information Network (PHIN). The full value set is
maintained by the [CDC PHIN Vocabulary Access and Distribution System
(PHIN
VADS)](https://phinvads.cdc.gov/vads/ViewValueSet.action?id=564F8F8B-E1DE-E411-8970-0017A477041A),
whose preferred concept names are shown below.
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)’s
own derived `patient_class` output values (`"ED"`, `"Inpatient"`,
`"Direct Admit"`, etc.) are shortened working labels, not required to
match these preferred names verbatim:

| Code | PHIN VADS preferred name |
|------|--------------------------|
| `D`  | Direct admit             |
| `E`  | Emergency                |
| `I`  | Inpatient                |
| `V`  | Observation patient      |
| `B`  | Obstetrics               |
| `O`  | Outpatient               |
| `P`  | Preadmit                 |
| `R`  | Recurring patient        |

`C_Patient_Class_List` is strictly more informative than `HasBeen_`
pivoting for one important reason: it is computed across all messages
for the visit before deduplication, meaning the full care pathway
history is preserved regardless of which row
[`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
retained. A `HasBeen_` flag on a deduplicated record reflects only the
flags present on the retained row; if `keep = "first"` was used and the
first row happened to predate an inpatient admission update, the
admission flag may be absent even though the patient was eventually
admitted. `C_Patient_Class_List` does not have this limitation.

When `C_Patient_Class_List` is present in `ed_data`,
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
uses it automatically and informs the user. No `HasBeen_` fields are
required.

### Fallback: `HasBeen_` flag pivot

When `C_Patient_Class_List` is not present,
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
falls back to pivoting the binary `HasBeen_` flag columns. The two most
relevant flags for encounter linkage are:

| `HasBeenE` | `HasBeenAdmitted` | Clinical interpretation |
|----|----|----|
| `1` | `0` | ED visit, discharged or left without being admitted |
| `1` | `1` | ED visit that escalated to inpatient admission |
| `0` | `1` | Direct admission – no ED visit in this encounter |
| `0` | `0` | Not applicable (neither ED nor inpatient) |

A `HasBeenE = 1` filtered query returns rows in the first two patterns
only. The third pattern – direct admissions – requires a separate
`HasBeenAdmitted = 1` query to capture.

`HasBeenI` is an alternative inpatient flag available in some ESSENCE
installations. When both `HasBeenAdmitted` and `HasBeenI` are present,
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
uses `HasBeenAdmitted` preferentially because it is
discharge-disposition aware: it captures ED visits that resulted in
inpatient admission via discharge disposition codes, which `HasBeenI`
may not flag in all ESSENCE configurations.

## Single-Pull Linkage

By default (`return_format = "collapsed"`),
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
merges each episode’s rows into a single composite row rather than
returning long-format duplicates that must be filtered afterward. A
visit with `HasBeenE = 1` and `HasBeenAdmitted = 1` is still detected
internally as two rows – one representing the ED contact, one
representing the inpatient escalation – but those rows are reconciled
into one merged row: `HasBeen_` flags are taken as the max across the
episode’s rows, and fields named in `merge_fields` (`CCDD`,
`CCDDParsed`, `CCDDCategory_flat`, `C_Death`, `Discharge_Disposition`,
and `DispositionCategory` by default) are reconciled using a strategy
suited to that field, so information recorded only on the inpatient row
is not silently discarded when the ED row is kept as the surviving
primary row.

``` r

# Deduplicate and filter before linking
ed_clean <- essence_raw |>
  dedupe(order_by = Arrived_Date_Time, keep = "last") |>
  filter_care_setting(
    fix_facility_type_vector = c("Hillside FSED", "Downtown Emergency Services")
  )
#> The following `FacilityType` values are not in `keep_types` and will be excluded:
#>   - Medical Specialty
#>   - Primary Care
```

``` r

episodes <- link_encounters(ed_clean)
#> Using `HasBeen_` flags to derive complete encounters of care since
#> `C_Patient_Class_List` is not present in `ed_data`.

dplyr::glimpse(episodes)
#> Rows: 160
#> Columns: 21
#> $ hospital_name           <chr> "Central Medical Center", "Central Medical Cen…
#> $ hospital                <int> 1001, 1001, 1001, 1001, 1001, 1001, 1001, 1001…
#> $ facility_type           <chr> "Emergency Care", "Emergency Care", "Emergency…
#> $ hospital_region         <chr> "KY_Jefferson", "KY_Jefferson", "KY_Jefferson"…
#> $ hospital_zip            <chr> "40201", "40201", "40201", "40201", "40201", "…
#> $ visit_id                <chr> "V10085501", "V12198106", "V13846187", "V14709…
#> $ c_bio_sense_id          <chr> "202301121001P74942483", "202309291001P7771715…
#> $ c_unique_patient_id     <chr> "P74942483", "P77717150", "P16845892", "P98662…
#> $ date                    <date> 2023-01-12, 2023-09-29, 2023-07-15, 2023-06-1…
#> $ c_visit_date_time       <dttm> 2023-01-12 17:47:39, 2023-09-29 20:06:22, 202…
#> $ arrived_date_time       <dttm> 2023-01-12 17:57:47, 2023-09-29 20:29:47, 202…
#> $ c_patient_class         <chr> "E", "E", "E", "E", "E", "E", "E", "E", "E", "…
#> $ region                  <chr> "TN_Davidson", "KY_Kenton", "KY_Campbell", "OH…
#> $ zip_code                <chr> "37040", "41011", "41011", "45001", "43215", "…
#> $ sex                     <chr> "F", "F", "F", "F", "M", "F", "M", "M", "U", "…
#> $ c_patient_age           <int> 40, 83, 41, 33, 26, 82, 51, 27, 66, 50, 69, 18…
#> $ patient_class           <chr> "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED"…
#> $ .episode_id             <chr> "Central Medical Center_V10085501", "Central M…
#> $ .patient_class_sequence <chr> "ED", "ED", "Admitted->ED", "ED", "ED", "ED", …
#> $ .episode_n_rows         <int> 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1…
#> $ .index_encounter        <lgl> TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE…
```

`nrow(episodes)` is already the unduplicated encounter count – no
additional filtering step is required with the default collapsed output:

``` r

nrow(episodes)
#> [1] 160
```

Four episode metadata columns are added to every row, regardless of
`return_format`:

**`.episode_id`** – A character key combining facility and visit
identifier, shared across all rows belonging to the same encounter. Used
internally to group rows into episodes and available for joining or
filtering downstream.

**`.patient_class_sequence`** – A collapsed string of the patient
classes present in the episode, in the order they actually occurred
(using `C_Visit_Date_Time`, `Date`+`Time`, or
`C_Patient_Class_MDT_Updates` when available – see
[`?link_encounters`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)).
A single-pull ED record with both `HasBeenE = 1` and
`HasBeenAdmitted = 1` set has no way to distinguish when each flag was
assigned, so its two classes tie and fall back to alphabetical order:
`.patient_class_sequence = "Admitted->ED"`. Two-pull linkage, where the
ED and direct-admit records are genuinely separate rows with their own
timestamps, can instead reflect a true reversal – e.g.
`"Direct Admit->ED"` when the direct-admit record’s timestamp precedes
the ED record’s. An episode built from a single ED row has
`.patient_class_sequence = "ED"`. This column enables filtering to
specific episode types (e.g.,
`filter(.patient_class_sequence == "Admitted->ED")` to isolate
escalating visits) even though the underlying rows have already been
merged.

**`.episode_n_rows`** – The number of original rows the episode was
built from before merging. Episodes with no escalation have
`.episode_n_rows = 1`; ED + Admitted episodes collapsed from two
original rows have `.episode_n_rows = 2`.

**`.index_encounter`** – In collapsed output (the default), always
`TRUE`, since every row already represents exactly one merged encounter;
the column is retained for schema consistency with the diagnostic
long-format output described below, not because a filtering step is
required.

``` r

# Distribution of care pathways -- already one row per encounter
episodes |>
  dplyr::count(.patient_class_sequence, sort = TRUE)
#> # A tibble: 3 × 2
#>   .patient_class_sequence     n
#>   <chr>                   <int>
#> 1 ED                        122
#> 2 Admitted->ED               36
#> 3 Admitted                    2
```

### Inspecting the Raw Linkage Mechanism: `return_format = "long"`

Set `return_format = "long"` to see the pre-merge rows directly – for
example, to audit which fields differed between the ED and inpatient
records before they were reconciled, or to understand the linkage
mechanism itself. No merge is applied in this mode.

``` r

episodes_long <- link_encounters(ed_clean, return_format = "long")
#> Using `HasBeen_` flags to derive complete encounters of care since
#> `C_Patient_Class_List` is not present in `ed_data`.

dplyr::count(episodes_long, patient_class)
#> # A tibble: 2 × 2
#>   patient_class     n
#>   <chr>         <int>
#> 1 Admitted         38
#> 2 ED              158
```

In long format, `.index_encounter` marks the row that survives a “one
row per episode” filter – `TRUE` on the ED row when both ED and Admitted
rows are present, or on the single row for ED-only or Direct Admit-only
episodes:

``` r

episodes_long |>
  dplyr::filter(.index_encounter) |>
  dplyr::count(.patient_class_sequence, sort = TRUE)
#> # A tibble: 3 × 2
#>   .patient_class_sequence     n
#>   <chr>                   <int>
#> 1 ED                        122
#> 2 Admitted->ED               36
#> 3 Admitted                    2
```

This matches the collapsed-format encounter count above, since the same
rows are merged into (or, in long format, selected as) the encounter of
record.

## Two-Pull Linkage

To capture direct admissions, run a second ESSENCE query filtered to
`HasBeenAdmitted = 1` (or `HasBeenI = 1`), deduplicate it separately,
and supply it as `inpatient_admission_data`. Rows with `HasBeenE = 1` in
the inpatient pull are automatically removed to prevent double-counting
– these visits are already present in the ED pull.

``` r

# Query ESSENCE for HasBeenAdmitted = 1 separately, then:
inpatient_clean <- essence_inpatient |>
  dedupe(order_by = Arrived_Date_Time, keep = "last")

episodes_full <- link_encounters(ed_clean, inpatient_clean)

# Direct admissions are now visible
dplyr::filter(episodes_full, patient_class == "Direct Admit")
```

When `inpatient_admission_data` is supplied,
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
removes rows with `HasBeenE = 1` from that pull (informing you of how
many were dropped) and labels the remaining rows
`patient_class = "Direct Admit"` before merging. A direct-admit visit
that shares no facility x visit_id with an ED row has no rows to merge
with, so it survives collapsing as its own single-row episode with
`.patient_class_sequence = "Direct Admit"`.

> **Can I just row-bind the ED and direct-admit pulls and run
> [`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
> on the result, instead of passing them separately?** No – this risks
> silently losing visits.
> [`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)’s
> `facility_col x visit_col` grouping does not distinguish an ED record
> from its corresponding direct-admit record; from
> [`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)’s
> perspective they are simply two rows sharing a key. `keep = "last"` or
> `keep = "first"` will pick whichever row has the later or earlier
> `Arrived_Date_Time` and discard the other – unpredictably decreasing
> either the ED visit count or the direct-admit count, depending on that
> ordering, rather than merging the two into one complete encounter.
> Always deduplicate each pull separately (as shown above) and pass both
> to
> [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
> as separate arguments; let
> [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md),
> not
> [`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md),
> perform the combination.

## Burden Estimation from Linked Data

With the default collapsed output, unduplicated burden estimation is
just a count – no `.index_encounter` filter is needed, since every row
already represents one merged encounter:

``` r

burden <- episodes |>
  dplyr::count(.patient_class_sequence, sort = TRUE)

burden
#> # A tibble: 3 × 2
#>   .patient_class_sequence     n
#>   <chr>                   <int>
#> 1 ED                        122
#> 2 Admitted->ED               36
#> 3 Admitted                    2
```

This yields one count per clinical encounter. Visits that generated both
an ED signal and an Admitted signal are merged into a single row (using
the ED row as primary) and counted once. Visits that generated only an
ED signal are counted once. With two-pull linkage, direct admissions add
their own counts without inflating the ED rows.

The `.patient_class_sequence` breakdown is informative for understanding
the severity composition of the case count:

- `"ED"` – Emergency department visit without inpatient admission
- `"Admitted->ED"` – Emergency department visit that escalated to
  inpatient admission (merged into a single row, primary values from the
  ED row)
- `"Direct Admit"` – Inpatient admission without ED encounter (only
  visible with two-pull linkage)

For most ESSENCE-based incidence analyses, the sum across all
`.patient_class_sequence` categories in the (already unduplicated)
collapsed output is the appropriate unduplicated encounter count.

## Connection to Cluster Detection

If using linked encounter data as input to spatial cluster detection
algorithms (e.g., SaTScan, the `gsClusterDetect` package, or custom
Kulldorff scan implementations), the default collapsed output is already
one row per encounter, so no additional deduplication filter is needed
before aggregating counts to geographic units:

``` r

# Prepare for spatial analysis: already one row per encounter
episodes |>
  assign_treating_geography() |>
  dplyr::count(region_hybrid)
```

If you instead requested `return_format = "long"` for diagnostic
purposes, filter to `.index_encounter == TRUE` first – otherwise
multi-class episodes would be counted twice, once per pre-merge row,
inflating cluster statistics.
