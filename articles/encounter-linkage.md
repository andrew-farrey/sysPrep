# Linking ED and Inpatient Records for Accurate Burden Estimation

`sysPrep`’s other core functions –
[`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md),
[`summarize_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/summarize_duplicates.md),
[`classify_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/classify_duplicates.md)
– remove duplicate ESSENCE rows for one visit within a single pull.
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
solves the same overcounting problem in a harder form: a visit split
across two separately queried pulls, where the duplicate doesn’t look
like one. Neither ESSENCE nor the BioSense Platform surfaces, flags, or
resolves this on their own – finding it takes looking at the underlying
records directly.

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

This has a direct, structural consequence for burden estimation.
Querying the inpatient pull with `HasBeenE = 0` added on purpose –
specifically to exclude anything already captured by the `HasBeenE = 1`
pull – looks like a safe way to avoid double-counting, and by the API’s
own field semantics it should be: `HasBeenE = 0` is supposed to mean no
ED encounter appears anywhere in that record’s history. It isn’t safe.
Some records that correctly show `HasBeenE = 0` were, clinically,
discharged from the ED and immediately readmitted – the ED encounter
lives entirely on the separate record already captured in the first
pull, so the exclusion filter never catches it. If you don’t know this
and want to include inpatient admissions in your burden counts, running
a `HasBeenE = 1` query and combining it with an otherwise-identical
`HasBeenE = 0` / `HasBeenAdmitted = 1` query – expecting the sum to be
an accurate “severe healthcare visit” census – does not produce one:
that proportion of ED visits gets counted a second time, once under each
query. At the same time, genuinely new direct admissions in the second
query are exactly what you’re trying to capture.
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
may not flag in all ESSENCE configurations. `essence_ed_raw` (introduced
below) includes both columns for its escalation visits, so this
preference is visible as an informational message the first time
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
runs on it.

## Linking ED and Inpatient Pulls

[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
always requires two separately queried ESSENCE pulls: an ED pull
(`HasBeenE = 1`) and an inpatient pull (`HasBeenAdmitted = 1` or
`HasBeenI = 1`). There is no single-pull mode. A `HasBeenE = 1` pull
cannot resolve the care pathway artifact problem on its own in either
direction: a genuine direct admission (`HasBeenE = 0`) is structurally
absent from it by construction, so there is nothing to link against; and
an ED-to-inpatient escalation that *is* visible within it already lives
on one already-deduplicated record (both `HasBeenE` and
`HasBeenAdmitted` set), which needs no linking, since there was never a
second record to link against.
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
aborts if `inpatient_admission_data` is omitted, rather than silently
returning `ed_data` unchanged with cosmetic metadata columns appended.

`sysPrep` ships two small synthetic datasets purpose-built for this
demonstration: `essence_ed_raw` (a `HasBeenE = 1` pull) and
`essence_inp_raw` (a separately queried `HasBeenAdmitted = 1` pull) –
distinct from the larger, general-purpose `essence_raw` used elsewhere
in this documentation, since `essence_raw` represents a single realistic
ED pull and was never meant to be split into two:

``` r

nrow(essence_ed_raw)
#> [1] 15
nrow(essence_inp_raw)
#> [1] 6
```

Deduplicate each pull separately before linking:

``` r

ed_clean <- essence_ed_raw |>
  dedupe(order_by = Arrived_Date_Time, keep = "last") |>
  filter_care_setting(
    fix_facility_type_vector = c("Hillside FSED", "Downtown Emergency Services")
  )

inpatient_clean <- essence_inp_raw |>
  dedupe(order_by = Arrived_Date_Time, keep = "last")
```

> **Can I just row-bind the ED and admission pulls and run
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

By default (`return_format = "collapsed"`),
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
merges each episode’s rows into a single composite row rather than
returning long-format duplicates that must be filtered afterward. Rows
with `HasBeenE = 1` in the admission pull are automatically removed
first (they are already present in the ED pull); the remainder are
labeled `patient_class = "Direct Admit"` and combined with the ED pull’s
own rows. Within a merged episode, `HasBeen_` flags are taken as the max
across the episode’s rows, and fields named in `merge_fields` (`CCDD`,
`CCDDParsed`, `CCDDCategory_flat`, `C_Death`, `Discharge_Disposition`,
and `DispositionCategory` by default) are reconciled using a strategy
suited to that field, so information recorded only on the admission row
is not silently discarded when the ED row is kept as the surviving
primary row.

``` r

episodes <- link_encounters(ed_clean, inpatient_clean)
#> Both `HasBeenAdmitted` and `HasBeenI` found in `ed_data`. `HasBeenAdmitted` will be used preferentially as it is discharge-disposition aware and inclusive of ED-to-inpatient escalations.
#> Using `HasBeen_` flags to derive complete encounters of care since `C_Patient_Class_List` is not present in `ed_data`.

dplyr::glimpse(episodes)
#> Rows: 18
#> Columns: 23
#> $ hospital_name           <chr> "Central Medical Center", "Central Medical Cen…
#> $ hospital                <int> 1001, 1001, 1001, 1001, 1001, 1001, 1008, 1008…
#> $ facility_type           <chr> "Emergency Care", "Emergency Care", "Emergency…
#> $ hospital_region         <chr> "KY_Jefferson", "KY_Jefferson", "KY_Jefferson"…
#> $ hospital_zip            <chr> "40201", "40201", "40201", "40201", "40201", "…
#> $ visit_id                <chr> "V42101634", "V42590427", "V54313817", "V65288…
#> $ c_bio_sense_id          <chr> "202310181001P26506928", "202312061001P5104253…
#> $ c_unique_patient_id     <chr> "P26506928", "P51042534", "P71287071", "P17371…
#> $ date                    <date> 2023-10-18, 2023-12-06, 2023-09-07, 2023-09-1…
#> $ c_visit_date_time       <dttm> 2023-10-18 04:35:33, 2023-12-06 19:49:26, 202…
#> $ arrived_date_time       <dttm> 2023-10-18 05:03:18, 2023-12-06 19:57:46, 202…
#> $ c_patient_class         <chr> "I", "I", "E", "E", "E", "I", "I", "E", "E", "…
#> $ region                  <chr> "KY_Hardin", "KY_Madison", "KY_Madison", "KY_J…
#> $ zip_code                <chr> "41011", "42001", "42001", "41042", "42701", "…
#> $ sex                     <chr> "M", "M", "M", "F", "F", "M", "F", "M", "F", "…
#> $ c_patient_age           <int> 34, 24, 70, 43, 66, 60, 56, 37, 69, 50, 82, 81…
#> $ has_been_e              <int> 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0…
#> $ has_been_admitted       <int> 1, 1, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 0, 1…
#> $ patient_class           <chr> "Direct Admit", "Direct Admit", "ED", "ED", "E…
#> $ .episode_id             <chr> "Central Medical Center_V42101634", "Central M…
#> $ .patient_class_sequence <chr> "Direct Admit", "Direct Admit", "ED", "ED", "E…
#> $ .episode_n_rows         <int> 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 2, 1, 1, 1…
#> $ .index_encounter        <lgl> TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE…
```

Every row above shows real `0`/`1` values for
`has_been_e`/`has_been_admitted` – never `NA` – regardless of whether it
came from a single pre-merge row or a merged pair: deriving
`patient_class` from `HasBeen_` flags (the fallback used here, since
this synthetic data has no `C_Patient_Class_List`) pivots those flag
columns to build `patient_class`, but
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
retains the true original values underneath so they survive into the
output unchanged.

`nrow(episodes)` is already the true unduplicated encounter count –
smaller than the naive combined denominator, since some admission-pull
rows merged into an existing ED episode instead of adding a new one:

``` r

nrow(ed_clean) + nrow(inpatient_clean) # naive combined denominator
#> [1] 20
nrow(episodes)                         # true unduplicated encounter count
#> [1] 18
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
The ED and admission records are genuinely separate rows with their own
timestamps, so this can reflect a true reversal –
e.g. `"Direct Admit->ED"` if an admission record’s timestamp somehow
precedes the ED record’s, versus the expected `"ED->Direct Admit"` for a
normal continuity-break artifact (ED visit, then mis-submitted admission
continuation). An episode built from a single row has
`.patient_class_sequence` equal to that row’s own class (e.g. `"ED"`, or
`"Direct Admit"` for a genuine direct admission with no ED counterpart).
This column enables filtering to specific episode types (e.g.,
`filter(.patient_class_sequence == "ED->Direct Admit")` to isolate the
continuity-break cases) even though the underlying rows have already
been merged.

**`.episode_n_rows`** – The number of original rows the episode was
built from before merging. Episodes with no linkage have
`.episode_n_rows = 1`; episodes merged from an ED row and an admission
row have `.episode_n_rows = 2`.

**`.index_encounter`** – In collapsed output (the default), always
`TRUE`, since every row already represents exactly one merged encounter;
the column is retained for schema consistency with the diagnostic
long-format output described below, not because a filtering step is
required.

``` r

# Distribution of care pathways -- already one row per encounter
episodes |>
  dplyr::count(.patient_class_sequence, sort = TRUE)
#> # A tibble: 4 × 2
#>   .patient_class_sequence     n
#>   <chr>                   <int>
#> 1 ED                         10
#> 2 Direct Admit                4
#> 3 Admitted->ED                2
#> 4 ED->Direct Admit            2
```

`"ED"` visits never touched the admission pull at all. `"Admitted->ED"`
visits escalated to inpatient care within the ED pull itself
(`HasBeenE = 1` and `HasBeenAdmitted = 1` on one already-deduplicated
record) – these need no cross-pull linking, since there was only ever
one record. `"Direct Admit"` visits are genuine admissions with no
preceding ED encounter at all, structurally invisible to a
`HasBeenE = 1` query and only captured because a second pull was
queried. `"ED->Direct Admit"` visits are the continuity-break artifact
itself: an ED visit and its mis-submitted direct-admit continuation,
reported under two different `C_BioSense_ID` values sharing one
`HospitalName x Visit_ID`, correctly merged into a single encounter
instead of being counted twice.

``` r

dplyr::filter(episodes, patient_class == "Direct Admit") |>
  dplyr::select(hospital_name, visit_id, .patient_class_sequence)
#> # A tibble: 4 × 3
#>   hospital_name               visit_id  .patient_class_sequence
#>   <chr>                       <chr>     <chr>                  
#> 1 Central Medical Center      V42101634 Direct Admit           
#> 2 Central Medical Center      V42590427 Direct Admit           
#> 3 Lakeside Community Hospital V86489009 Direct Admit           
#> 4 North County Hospital       V64550501 Direct Admit
```

### Inspecting the Raw Linkage Mechanism: `return_format = "long"`

Set `return_format = "long"` to see the pre-merge rows directly – for
example, to audit which fields differed between the ED and admission
records before they were reconciled, or to understand the linkage
mechanism itself. No merge is applied in this mode.

``` r

episodes_long <- link_encounters(
  ed_clean, inpatient_clean, return_format = "long"
)
#> Both `HasBeenAdmitted` and `HasBeenI` found in `ed_data`. `HasBeenAdmitted` will be used preferentially as it is discharge-disposition aware and inclusive of ED-to-inpatient escalations.
#> Using `HasBeen_` flags to derive complete encounters of care since `C_Patient_Class_List` is not present in `ed_data`.

dplyr::count(episodes_long, patient_class)
#> # A tibble: 3 × 2
#>   patient_class     n
#>   <chr>         <int>
#> 1 Admitted          2
#> 2 Direct Admit      6
#> 3 ED               14
```

In long format, `.index_encounter` marks the row that survives a “one
row per episode” filter – `TRUE` on the ED row when both ED and
admission rows are present, or on the single row for ED-only or Direct
Admit-only episodes:

``` r

episodes_long |>
  dplyr::filter(.index_encounter) |>
  dplyr::count(.patient_class_sequence, sort = TRUE)
#> # A tibble: 4 × 2
#>   .patient_class_sequence     n
#>   <chr>                   <int>
#> 1 ED                         10
#> 2 Direct Admit                4
#> 3 Admitted->ED                2
#> 4 ED->Direct Admit            2
```

This matches the collapsed-format encounter count above, since the same
rows are merged into (or, in long format, selected as) the encounter of
record.

## Burden Estimation from Linked Data

With the default collapsed output, unduplicated burden estimation is
just a count – no `.index_encounter` filter is needed, since every row
already represents one merged encounter:

``` r

burden <- episodes |>
  dplyr::count(.patient_class_sequence, sort = TRUE)

burden
#> # A tibble: 4 × 2
#>   .patient_class_sequence     n
#>   <chr>                   <int>
#> 1 ED                         10
#> 2 Direct Admit                4
#> 3 Admitted->ED                2
#> 4 ED->Direct Admit            2
```

This yields one count per clinical encounter. Visits that generated both
an ED signal and an admission signal are merged into a single row (using
the ED row as primary) and counted once. Visits that generated only an
ED signal are counted once. Direct admissions add their own counts
without inflating the ED rows.

The `.patient_class_sequence` breakdown is informative for understanding
the severity composition of the case count:

- `"ED"` – Emergency department visit without inpatient admission
- `"Admitted->ED"` – Emergency department visit that escalated to
  inpatient admission within the ED pull alone (merged into a single
  row, primary values from the ED row)
- `"Direct Admit"` – Genuine inpatient admission with no preceding ED
  encounter at all, only visible because a second pull was queried
- `"ED->Direct Admit"` – The continuity-break artifact: an ED visit and
  its mis-submitted direct-admit continuation, reported as two records
  and correctly merged into one encounter

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
