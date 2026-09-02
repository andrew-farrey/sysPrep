# Understanding and Resolving Duplicate Records in ESSENCE Data

## Why ESSENCE Contains Duplicate Records

The vast majority of ESSENCE records are updated correctly via HL7
update messages, which are accurately appended to the existing record
without generating additional rows. Duplicate records are the exception,
not the rule. When duplicates do occur, they arise through distinct
mechanisms with different causes and different implications for how
deduplication should be approached. Without deduplication, these
additional rows inflate case counts, distort trend analyses, and produce
inaccurate rates.

**Why duplication happens.** BioSense, the NSSP platform underlying
ESSENCE, computes a record identifier – `C_BioSense_ID` (called
EssenceID in the ESSENCE backend) – by concatenating three calculated
fields: `C_Visit_Date`, `C_BioSense_Facility_ID` (`Hospital` in this
package and in `dataDetails` API pulls), and `C_Unique_Patient_ID`.
`C_Visit_Date` itself takes its date value from `C_Visit_Date_Time`. As
long as those calculated fields are transmitted consistently for a given
encounter, updates to other fields – a discharge disposition, a lab
result, a diagnosis code – are correctly appended to the existing
record, with no additional row created. This is why the vast majority of
ESSENCE updates do not produce duplicates. NSSP is not the source of the
problem: a new `C_BioSense_ID` is computed, and an apparent second
record created, only when one of the three calculated fields disagrees
between transmissions of what should be the same encounter – in
practice, almost always `C_Visit_Date_Time` (via `C_Visit_Date`) or
`C_Unique_Patient_ID`. `C_BioSense_Facility_ID` is formally part of the
same calculation, but a genuine change in it – as from an inter-facility
transfer – would typically also mean a different `Visit_ID`, since
facilities generally do not share `Visit_ID` values with each other.
Reliably detecting a facility-driven `C_BioSense_ID` change is not
something this package currently attempts, and it is not something the
mechanisms documented here have been verified against directly. BioSense
has no way to tell whether a calculated-field change is a genuine
correction or an unwarranted, feed-level error; either way, the visit is
duplicated. When a site transmits fully accurate calculated fields for
every visit, duplication from this mechanism is essentially zero. The
two most common, detectable ways it occurs in ESSENCE data are:

**`visit_date_change`.** As described above, `C_Visit_Date` takes its
date value from `C_Visit_Date_Time`. Some hospitals’ systems update
`C_Visit_Date_Time` as providers interact with the patient over the
course of the visit, rather than fixing it at initial registration. When
one of those updates crosses midnight – changing what was a pre-midnight
value to a post-midnight value – `C_Visit_Date` changes to the next
calendar day, which recomputes `C_BioSense_ID` for the same `Visit_ID`,
producing two rows that appear to represent different BioSense records
but refer to the same encounter. This is the most widespread duplication
type across NSSP sites, though the exact scope varies by site and
facility, and the affected proportion of visits is typically small. Many
hospitals handle midnight-crossing visits correctly by not modifying
`Admit_Date_Time` or `C_Visit_Date_Time` after the patient’s initial
registration; the duplicate arises only at facilities whose systems
continue to update it afterward.

The impact of this duplication is disproportionate in small-count
contexts. A syndrome definition for a relatively rare condition – such
as a specific overdose agent or an emerging chief complaint pattern –
may produce only a handful of true encounters at a given facility on a
given day. If those encounters generate multiple `C_BioSense_ID` values,
the apparent count presented to an analyst or flagged by an anomaly
detection algorithm can be substantially higher than the true count,
potentially triggering alerts that do not reflect genuine changes in
incidence. This is the clinical and surveillance consequence that
motivates deduplication even when the affected proportion of total
visits is low.

**`pid_change`.** `C_Unique_Patient_ID` (which maps to medical record
number in Kentucky) is the third field concatenated into
`C_BioSense_ID`. A patient may be registered under one identifier and
have it corrected mid-visit – for example, when an initial local
(facility- or department-specific) MRN is replaced with a community-wide
or health-system-level MRN, or with a different local MRN – and the
facility submits an update message with the corrected
`C_Unique_Patient_ID` while `Visit_ID` itself stays the same. Because
BioSense recomputes `C_BioSense_ID` from the new `C_Unique_Patient_ID`,
the update produces an additional row rather than correcting the
existing one – the original row, tied to the earlier
`C_Unique_Patient_ID`, is left in place and still reflects the earlier
state of the visit, while the new row carries the corrected identifier
and current information. Each identifier change produces one additional
row for the same `Visit_ID`.

**`patient_class_change`.** Under normal HL7 processing, patient class
transitions during a visit – for example, from emergency department to
inpatient admission – are handled without generating duplicate rows: the
transition is appended to `C_Patient_Class_List`, and the `HasBeenE`,
`HasBeenI`, `HasBeenAdmitted` flags (ED-visit and inpatient-admission
indicator columns) are revised in place. A `patient_class_change`
duplicate appears only when something additional causes a new row to be
submitted for the same `Visit_ID` coincident with a class transition –
such as a feed configuration issue or a concurrent `visit_date_change`.
This mechanism requires `c_patient_class` to be present in the data
pull. See also
[`vignette("encounter-linkage")`](https://andrew-farrey.github.io/sysPrep/articles/encounter-linkage.md),
which addresses multi-class visits through encounter linkage rather than
deduplication.

**Cross-pull double-counting when combining ED and direct-admit data.**
The mechanisms above all produce duplicate rows *within* a single pull,
which
[`summarize_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/summarize_duplicates.md),
[`classify_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/classify_duplicates.md),
and
[`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
are built to detect and resolve. A related but distinct risk arises when
combining a `HasBeenE = 1` pull with a separately queried
`HasBeenAdmitted = 1` pull to build a combined “severe visit” count:
pre-aggregated ESSENCE data (timeSeries, tableBuilder) cannot
distinguish a true direct admission from a mis-submitted one whose
corresponding ED record incorrectly shows `HasBeenAdmitted = 0`.
Combining the two pulls without linking them double-counts the
mis-submitted cases.
[`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
is not the right tool for this: even though the ED and mis-submitted
admission records share a `facility_col x visit_col` key, they carry
complementary, not redundant, information – the admission record’s
discharge disposition and outcome are not present on the ED record – so
discarding one (as
[`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
does) silently loses information that merging (as
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
does) preserves. See
[`vignette("encounter-linkage")`](https://andrew-farrey.github.io/sysPrep/articles/encounter-linkage.md)
and
[`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
for the dedicated fix.

## Quantifying Duplicates: `summarize_duplicates()`

Before deduplicating, call
[`summarize_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/summarize_duplicates.md)
to understand the scope and distribution of duplicates in your data.
This step is diagnostic and does not alter the data.

``` r

dups <- summarize_duplicates(essence_raw)
dups
#> 
#> ── ESSENCE Duplicate Summary ───────────────────────────────────────────────────
#> 
#> ── Overall ──
#> 
#> • Total rows in pull: 193
#> • Unique visits (facility x ID): 180
#> • Duplicated Visit IDs: 13 (7.2%)
#> • Excess rows to remove: 13
#> 
#> ── By Facility (most duplicated first) ──
#> 
#> # A tibble: 5 × 5
#>   hospital_name     n_visits n_duplicated_visit_ids n_excess_rows pct_duplicated
#>   <chr>                <int>                  <int>         <int>          <dbl>
#> 1 Central Medical …       38                      6             6           15.8
#> 2 Metro Health Sys…       28                      3             3           10.7
#> 3 North County Hos…       19                      2             2           10.5
#> 4 Lakeside Communi…       21                      1             1            4.8
#> 5 River Valley Med…       15                      1             1            6.7
#> ── Duplicated Visit IDs ──
#> 13 facility × Visit_ID pair(s) with >1 row. Access via $duplicate_ids.
```

The printed output shows dataset-wide duplicate counts and a
per-facility breakdown. Accessing the list components directly provides
the underlying data:

``` r

# Dataset-level counts
dups$overall
#> # A tibble: 1 × 5
#>   n_total_rows n_unique_visits n_duplicated_visit_ids n_excess_rows
#>          <int>           <int>                  <int>         <int>
#> 1          193             180                     13            13
#> # ℹ 1 more variable: pct_duplicated <dbl>

# Per-facility counts (facilities with duplicates only)
dups$by_facility
#> # A tibble: 5 × 5
#>   hospital_name     n_visits n_duplicated_visit_ids n_excess_rows pct_duplicated
#>   <chr>                <int>                  <int>         <int>          <dbl>
#> 1 Central Medical …       38                      6             6           15.8
#> 2 Metro Health Sys…       28                      3             3           10.7
#> 3 North County Hos…       19                      2             2           10.5
#> 4 Lakeside Communi…       21                      1             1            4.8
#> 5 River Valley Med…       15                      1             1            6.7
```

`$overall` gives the total number of duplicated `facility × Visit_ID`
pairs and the proportion of unique visits affected. `$by_facility` gives
per-facility counts of duplicated visit identifiers, sorted by total
duplicated visits descending. A facility with a disproportionately high
duplicate rate may indicate a feed configuration issue – for example, a
registration system that routinely updates `C_Visit_Date_Time` as
providers interact with the patient (producing `visit_date_change`
duplicates whenever an update crosses midnight), or a workflow that
changes `C_Unique_Patient_ID` between update messages for the same visit
(producing `pid_change` duplicates).

> **Why is the deduplication key `HospitalName × Visit_ID`, not
> `Visit_ID` alone?** The same `Visit_ID` may appear at two facilities
> if a patient is transferred mid-visit and both facilities transmit
> records with their own internal visit identifiers that happen to be
> numerically identical. Deduplicating by `Visit_ID` alone would
> incorrectly collapse these into a single encounter. `sysPrep` always
> deduplicates within facility.

## Understanding the Mechanism: `classify_duplicates()`

After quantifying duplicates, classify their mechanism to inform your
deduplication strategy and identify potential feed-level issues.

``` r

classified <- classify_duplicates(essence_raw)
classified
#> 
#> ── ESSENCE Duplicate Classification ────────────────────────────────────────────
#> 
#> ── Overall ──
#> 
#>                      dup_type n percent
#>                  type_unknown 5   38.5%
#>             visit_date_change 3   23.1%
#>          patient_class_change 2   15.4%
#>                    pid_change 2   15.4%
#>  visit_date_change+pid_change 1    7.7%
#> ── By Facility ──
#> # A tibble: 5 × 7
#>   hospital_name   patient_class_change pid_change type_unknown visit_date_change
#>   <chr>                          <int>      <int>        <int>             <int>
#> 1 Central Medica…                    1          2            2                 1
#> 2 Metro Health S…                    0          0            3                 0
#> 3 North County H…                    0          0            0                 1
#> 4 Lakeside Commu…                    1          0            0                 0
#> 5 River Valley M…                    0          0            0                 1
#> # ℹ 2 more variables: `visit_date_change+pid_change` <int>,
#> #   n_duplicated_total <dbl>
#> ── Duplicated Visit IDs ──
#> 13 facility × Visit_ID pair(s) with >1 row. Access via $duplicate_ids.
#> 
#> ── Visit Groups ──
#> 
#> 180 facility × Visit_ID groups total. Access full detail via $visit_groups.
```

``` r

# Type distribution across the full dataset
classified$overall
#>                      dup_type n percent
#>                  type_unknown 5   38.5%
#>             visit_date_change 3   23.1%
#>          patient_class_change 2   15.4%
#>                    pid_change 2   15.4%
#>  visit_date_change+pid_change 1    7.7%
```

``` r

# Per-facility breakdown by type (wide format)
classified$by_facility
#> # A tibble: 5 × 7
#>   hospital_name   patient_class_change pid_change type_unknown visit_date_change
#>   <chr>                          <int>      <int>        <int>             <int>
#> 1 Central Medica…                    1          2            2                 1
#> 2 Metro Health S…                    0          0            3                 0
#> 3 North County H…                    0          0            0                 1
#> 4 Lakeside Commu…                    1          0            0                 0
#> 5 River Valley M…                    0          0            0                 1
#> # ℹ 2 more variables: `visit_date_change+pid_change` <int>,
#> #   n_duplicated_total <dbl>
```

The `$overall` component shows how many duplicate groups belong to each
mechanism type. The `$by_facility` component shows the distribution of
mechanisms per facility in wide format – useful for identifying
facilities whose duplicates are concentrated in a particular mechanism.

When `c_patient_class` is not included in your ESSENCE pull, the
function issues an informational message and skips
`patient_class_change` detection. All other mechanism types remain fully
functional.

> **Why classify before removing duplicates?** Classification reveals
> whether your duplicates are dominated by retransmissions (suggesting
> `keep = "last"` is appropriate) or by `visit_date_change` events
> (which may warrant examining whether the date change affects your
> analysis window). It also identifies whether a specific facility is
> generating an unusual volume of a particular duplication type – which
> can point to a feed-level configuration problem worth reporting to the
> facility or NSSP.

For row-level analysis, use `return_format = "tibble"` to join
classifications back to the original data:

``` r

# Join mechanism type back to raw data for row-level inspection.
# classify_duplicates() returns cleaned (snake_case) column names,
# so clean essence_raw first to align join keys.
typed <- essence_raw |>
  janitor::clean_names() |>
  dplyr::left_join(
    classify_duplicates(essence_raw, return_format = "tibble"),
    by = c("hospital_name", "visit_id")
  )

dplyr::count(typed, dup_type)
#> # A tibble: 6 × 2
#>   dup_type                         n
#>   <chr>                        <int>
#> 1 no_duplication                 167
#> 2 patient_class_change             4
#> 3 pid_change                       4
#> 4 type_unknown                    10
#> 5 visit_date_change                6
#> 6 visit_date_change+pid_change     2
```

## Removing Duplicates: `dedupe()`

With duplicates characterized, remove them using
[`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md).
The function retains exactly one row per `facility × visit_col` group.

``` r

deduped <- dedupe(essence_raw, order_by = Arrived_Date_Time, keep = "last")

cat("Rows before: ", nrow(essence_raw), "\n")
#> Rows before:  193
cat("Rows after:  ", nrow(deduped), "\n")
#> Rows after:   180
cat("Rows removed:", nrow(essence_raw) - nrow(deduped), "\n")
#> Rows removed: 13
```

``` r

# Confirm zero duplicate groups remain
summarize_duplicates(deduped)$overall
#> # A tibble: 1 × 5
#>   n_total_rows n_unique_visits n_duplicated_visit_ids n_excess_rows
#>          <int>           <int>                  <int>         <int>
#> 1          180             180                      0             0
#> # ℹ 1 more variable: pct_duplicated <dbl>
```

The `order_by` argument specifies which column to use for ranking rows
within each duplicate group. `Arrived_Date_Time` – the timestamp when
NSSP received the record – is the recommended ordering column for
production surveillance because the most recently received row is most
likely to reflect updated clinical information.

## Choosing a Deduplication Strategy

The appropriate strategy depends on your surveillance context:

| Scenario | Recommended strategy |
|----|----|
| Rolling surveillance (production monitoring) | `order_by = Arrived_Date_Time, keep = "last"` |
| Fixed-window retrospective analysis | `order_by = Arrived_Date_Time, keep = "first"` |
| Field completeness matters (e.g., maximizing diagnosis code coverage) | `keep = "most_complete"` |
| Unsure – inspect before deciding | Call [`classify_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/classify_duplicates.md) first |

**`keep = "last"`** retains the row with the highest value of `order_by`
– the most recently transmitted record. Appropriate when the latest
transmission is most current and complete, which is true for most
retransmission scenarios.

**`keep = "first"`** retains the row with the lowest value of `order_by`
– the original transmission. Appropriate for fixed-window analyses where
you want to capture the visit as it was first reported, without post-hoc
field updates.

**`keep = "most_complete"`** retains the row with the fewest `NA` values
across all columns. Appropriate when no single transmission is reliably
more current than another and field completeness is the primary concern
– for example, when discharge diagnosis codes are populated
inconsistently across retransmissions.

When the `order_by` column itself contains ties (multiple rows with the
same `Arrived_Date_Time`),
[`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
retains the first occurrence among tied rows and issues an informational
message. To avoid tie-breaking ambiguity, use `C_BioSense_ID` as a
secondary sort or combine `keep = "most_complete"` with an explicit
`order_by`.

## Next Steps

- [`vignette("encounter-linkage")`](https://andrew-farrey.github.io/sysPrep/articles/encounter-linkage.md):
  After deduplication, understand how
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  handles the structural exclusion of direct admissions from
  `HasBeenE = 1` filtered queries.

- [`vignette("getting-started")`](https://andrew-farrey.github.io/sysPrep/articles/getting-started.md):
  The full recommended pipeline, combining deduplication with care
  setting filtering and geographic attribution.

- [`?dedupe`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md),
  [`?summarize_duplicates`](https://andrew-farrey.github.io/sysPrep/reference/summarize_duplicates.md),
  [`?classify_duplicates`](https://andrew-farrey.github.io/sysPrep/reference/classify_duplicates.md):
  Full parameter documentation and additional examples.
