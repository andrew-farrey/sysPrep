# Getting Started with sysPrep

## The ESSENCE Preprocessing Problem

The National Syndromic Surveillance Program (NSSP) Electronic
Surveillance System for the Early Notification of Community-based
Epidemics ([ESSENCE](https://www.cdc.gov/nssp/)) provides near-real-time
access to emergency department visit data from participating facilities
across the United States. Epidemiologists use ESSENCE to monitor disease
trends, detect spatial clusters, and evaluate the impact of public
health interventions.

`sysPrep`’s preprocessing steps are **not required** to run these
analyses – many surveillance questions tolerate the raw data quality
issues below without materially changing conclusions. Applying them is
most worthwhile for **small-count, high-impact case definitions**, where
minimizing false-positive clusters/anomalies and preserving external
validity matter most (for example, before feeding visit-level data into
SaTScan or a similar spatial scan tool for cluster/anomaly detection).
This is the context in which these methods were developed: applied
opioid overdose surveillance and cluster detection using NSSP ESSENCE
data.

Four categories of data quality problems are present in virtually every
ESSENCE pull, and can bias case counts or distort cluster/anomaly
detection if left unaddressed:

**Duplicate records.** A single clinical encounter may appear as
multiple rows in the same pull. Ordinary clinical updates (a lab result,
a discharge disposition) are correctly appended to the existing record
with no additional row. Duplication happens instead when a specific
calculated field disagrees between transmissions of what should be the
same encounter – most often `C_Visit_Date_Time` (e.g., when a hospital
updates it as care progresses and an update crosses midnight) or
`C_Unique_Patient_ID` (e.g., when a temporary identifier is corrected to
a permanent one). Without deduplication, case counts are inflated and
trends are distorted.

**Non-emergency providers.** ESSENCE returns visits from any facility
that submitted a matching syndromic record, including primary care
clinics and medical specialty practices that are not equipped to treat
emergency presentations. Free-standing emergency departments (FSEDs),
which are functionally identical to hospital-based EDs, are sometimes
onboarded to ESSENCE with incorrect facility type codes. Both categories
require explicit handling before ED-based incidence can be estimated.

**Mis-submitted and invisible direct admissions.** A row showing
`HasBeenAdmitted = 1` and `HasBeenE = 0` can mean two different things,
and nothing in that row alone tells you which: a genuine direct
admission with no preceding ED visit, or an ED visit whose transition to
inpatient care wasn’t recorded as one continuous encounter – producing
what looks, to ESSENCE, like two unrelated visits for a single event.
The former is structurally invisible to standard `HasBeenE = 1` queries;
the latter double-counts a real encounter if the two records are
combined without linking them. Encounter linkage resolves both by
combining ED and inpatient pulls into unified care episodes.

**Out-of-state and unknown-residence visits.** ESSENCE records include
all patients treated at in-state facilities regardless of where they
live. Patients who cannot or do not provide an address are coded as
`OTHER_REGION`. Discarding these visits produces systematic
underestimates of facility burden, particularly at facilities near state
borders or serving mobile populations.

`sysPrep` formalizes the preprocessing steps practitioners apply to
address each of these problems into a reproducible, documented R
pipeline.

`sysPrep`’s functions have been validated against records pulled from
the NSSP ESSENCE `va_er` (Patient Location, Full Details) and `va_hosp`
(Facility Location, Full Details) data sources. Both sources return ED
visit and inpatient admission records, so all exported functions apply
to either. Column names and value formats referenced throughout this
package (e.g., `{SITE}_{REGION}` region strings,
`HasBeenE`/`HasBeenAdmitted` flags) reflect these two data sources.

## Installation

``` r

remotes::install_github("andrew-farrey/sysPrep")
```

## The Synthetic Dataset

`sysPrep` ships with `essence_raw`, a fully synthetic dataset that
reproduces all four categories of ESSENCE data quality problems.

``` r

dplyr::glimpse(essence_raw)
#> Rows: 197
#> Columns: 19
#> $ HospitalName        <chr> "Lakeside Community Hospital", "Metro Health Syste…
#> $ Hospital            <int> 1004, 1005, 1010, 1007, 1001, 1007, 1004, 1003, 10…
#> $ FacilityType        <chr> "Emergency Care", "Emergency Care", "Medical Speci…
#> $ HospitalRegion      <chr> "KY_Boone", "KY_Fayette", "KY_Fayette", "KY_Jeffer…
#> $ HospitalZip         <chr> "41042", "40507", "40508", "40202", "40201", "4020…
#> $ Visit_ID            <chr> "V19653107", "V65845208", "V77502144", "V78782496"…
#> $ C_BioSense_ID       <chr> "202303291004P34604690", "202311011005P34188228", …
#> $ C_Unique_Patient_ID <chr> "P34604690", "P34188228", "P31690339", "P82183105"…
#> $ Date                <date> 2023-03-29, 2023-11-01, 2023-09-14, 2023-08-12, 2…
#> $ C_Visit_Date_Time   <dttm> 2023-03-29 20:42:54, 2023-11-01 08:20:28, 2023-09…
#> $ Arrived_Date_Time   <dttm> 2023-03-29 21:14:53, 2023-11-01 09:29:13, 2023-11…
#> $ HasBeenE            <int> 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,…
#> $ HasBeenAdmitted     <int> 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, 1, 0, 0,…
#> $ C_Patient_Class     <chr> "E", "E", "E", "E", "E", "E", "E", "E", "E", "E", …
#> $ Region              <chr> "WV_Cabell", "KY_McCracken", "KY_McCracken", "KY_M…
#> $ ZipCode             <chr> "25701", "42001", "40201", "40390", "42701", "4020…
#> $ Sex                 <chr> "F", "F", "F", "M", "F", "M", "M", "F", "U", "F", …
#> $ C_Patient_Age       <int> 35, 30, 22, 42, 29, 35, 39, 24, 79, 56, 26, 54, 83…
#> $ PullSource          <chr> "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "E…
```

The dataset contains approximately 197 rows and 19 columns. Key features
embedded in `essence_raw`:

- **13 duplicate rows** across four mechanisms: standard
  retransmissions, midnight-crossing date changes, patient identifier
  corrections, and one compound case combining two mechanisms
  simultaneously.
- **20 non-ED provider records** from a `"Primary Care"` and a
  `"Medical Specialty"` facility that should be excluded.
- **Two FSEDs** (`"Hillside FSED"` and `"Downtown Emergency Services"`)
  misclassified as `"Urgent Care"` – they are valid ED providers but
  require facility type correction.
- **Out-of-state and `OTHER_REGION` records** in the `Region` column.
- **A `PullSource` column** marking which of two separately-run ESSENCE
  queries (`HasBeenE = 1` vs. `HasBeenAdmitted = 1`) each row would have
  come back in – used in
  [`vignette("encounter-linkage")`](https://andrew-farrey.github.io/sysPrep/articles/encounter-linkage.md)
  to demonstrate
  [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  without a second real ESSENCE pull.

For full column documentation, see
[`?essence_raw`](https://andrew-farrey.github.io/sysPrep/reference/essence_raw.md).

## The Recommended Pipeline

The preprocessing steps should be applied in the order shown below. Each
step depends on the output of the previous: deduplication first (to
ensure accurate row counts for downstream steps), care setting filtering
second (to remove non-ED providers before geographic attribution), and
geography assignment last (applied only to the valid ED population).

``` r

clean <- essence_raw |>
  # Step 1: Remove duplicate records, retaining the most recently transmitted
  dedupe(order_by = Arrived_Date_Time, keep = "last") |>
  # Step 2: Filter to valid ED and inpatient providers; correct FSED types
  filter_care_setting(
    fix_facility_type_vector = c("Hillside FSED", "Downtown Emergency Services")
  ) |>
  # Step 3: Assign treating facility geography to out-of-state and OTHER_REGION visits
  assign_treating_geography()
#> The following `FacilityType` values are not in `keep_types` and will be excluded:
#>   - Medical Specialty
#>   - Primary Care
#> 27 of 164 visits (16.5%) identified as out-of-state or OTHER_REGION and assigned treating facility geography in `region_hybrid`/`zip_code_hybrid`.
```

**Step 1 – Deduplication**
([`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)):
Groups records by facility × visit identifier. Within each group,
retains the single row with the latest `Arrived_Date_Time` – the most
recently transmitted version of the record, which is most likely to
contain updated clinical information. The `order_by` and `keep`
arguments control this behavior and can be adjusted for different
surveillance contexts (see
[`?dedupe`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
and the deduplication vignette).

**Step 2 – Care setting filtering**
([`filter_care_setting()`](https://andrew-farrey.github.io/sysPrep/reference/filter_care_setting.md)):
Retains only facilities with `FacilityType` values consistent with
emergency care. The `fix_facility_type_vector` argument names facilities
that should be treated as emergency providers despite incorrect facility
type codes – in this case, two FSEDs. Without this correction, those
facilities’ visits would be excluded along with genuine non-ED
providers.

**Step 3 – Geographic attribution**
([`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md)):
For visits where `Region` is out-of-state or `OTHER_REGION`, writes the
treating facility’s corresponding geographic fields to new
`region_hybrid`/ `zip_code_hybrid` columns. `Region`/`ZipCode`
themselves are never modified – for in-state visits,
`region_hybrid`/`zip_code_hybrid` simply carry through the original
value unchanged.

Each of these functions reports what it did via informational console
messages – useful during interactive exploration, but often unwanted
when the pipeline runs inside a rendered R Markdown report or other
non-interactive context. Pass `verbose = FALSE` to suppress these
messages; warnings and errors are always shown regardless, so real data
quality issues are never silently hidden:

``` r

clean_quiet <- essence_raw |>
  dedupe(order_by = Arrived_Date_Time, keep = "last") |>
  filter_care_setting(
    fix_facility_type_vector = c("Hillside FSED", "Downtown Emergency Services"),
    verbose = FALSE
  ) |>
  assign_treating_geography(verbose = FALSE)
```

## What Changed?

``` r

cat("Raw rows:   ", nrow(essence_raw), "\n")
#> Raw rows:    197
cat("Clean rows: ", nrow(clean), "\n")
#> Clean rows:  164
cat("\nRows removed at each step:\n")
#> 
#> Rows removed at each step:
cat("  Duplicates removed:         ",
    nrow(essence_raw) - nrow(dedupe(essence_raw, order_by = Arrived_Date_Time)), "\n")
#>   Duplicates removed:          13

after_dedup <- essence_raw |>
  dedupe(order_by = Arrived_Date_Time, keep = "last")
after_filter <- after_dedup |>
  filter_care_setting(
    fix_facility_type_vector = c("Hillside FSED", "Downtown Emergency Services")
  )
#> The following `FacilityType` values are not in `keep_types` and will be excluded:
#>   - Medical Specialty
#>   - Primary Care
cat("  Non-ED providers excluded:  ",
    nrow(after_dedup) - nrow(after_filter), "\n")
#>   Non-ED providers excluded:   20
cat("\nNew columns added by assign_treating_geography():\n")
#> 
#> New columns added by assign_treating_geography():
cat(" ", paste(setdiff(names(clean), names(essence_raw)), collapse = ", "), "\n")
#>   hospital_name, hospital, facility_type, hospital_region, hospital_zip, visit_id, c_bio_sense_id, c_unique_patient_id, date, c_visit_date_time, arrived_date_time, has_been_e, has_been_admitted, c_patient_class, region, zip_code, sex, c_patient_age, pull_source, .out_of_state, region_hybrid, zip_code_hybrid
```

``` r

# How many visits had geography reassigned?
dplyr::count(clean, .out_of_state)
#> # A tibble: 2 × 2
#>   .out_of_state     n
#>   <lgl>         <int>
#> 1 FALSE           137
#> 2 TRUE             27
```

The `.out_of_state` column marks visits where `region_hybrid` differs
from `Region` – i.e., where the treating facility’s county was
substituted for an out-of-state or `OTHER_REGION` value. For in-state
visits, `region_hybrid` equals `Region` unchanged. Chaining
[`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md)
onto the same pipeline adds a third column, `region_facility`, with
treating geography substituted for *every* visit – useful for comparing
residential, hybrid, and facility-based geography side by side without
touching `Region` at all. See
[`vignette("geography-assignment")`](https://andrew-farrey.github.io/sysPrep/articles/geography-assignment.md)
for the full mechanics, including how to overwrite `Region`/`ZipCode` in
place instead if that’s what your pipeline needs.

## Function Reference

| Function | Purpose |
|----|----|
| [`summarize_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/summarize_duplicates.md) | Count duplicate records per facility and dataset-wide – call before deduplication to understand data quality |
| [`classify_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/classify_duplicates.md) | Classify the mechanism of each duplicate group (`visit_date_change`, `pid_change`, `patient_class_change`, or compound) |
| [`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md) | Remove duplicate records, retaining one row per facility × visit identifier |
| [`filter_care_setting()`](https://andrew-farrey.github.io/sysPrep/reference/filter_care_setting.md) | Filter to valid ED/inpatient providers; correct misclassified FSEDs |
| [`review_facility_ed_visits()`](https://andrew-farrey.github.io/sysPrep/reference/review_facility_ed_visits.md) | Flag facilities with anomalous visit volumes using IQR or SD outlier detection |
| [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md) | Link ED and inpatient pulls into unified care episodes, correcting mis-submitted admissions and capturing genuine direct admissions |
| [`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md) | Reassign geography for out-of-state and `OTHER_REGION` visits only |
| [`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md) | Reassign geography for all visits to treating facility location |

## Next Steps

- [`vignette("deduplication-and-classification")`](https://andrew-farrey.github.io/sysPrep/articles/deduplication-and-classification.md):
  Detailed methodology for each duplication mechanism, how to interpret
  [`summarize_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/summarize_duplicates.md)
  and
  [`classify_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/classify_duplicates.md)
  output, and a decision guide for choosing a deduplication strategy.

- [`vignette("encounter-linkage")`](https://andrew-farrey.github.io/sysPrep/articles/encounter-linkage.md):
  The care pathway artifact problem, `HasBeen_` column structure,
  linking a separately queried ED and admission pull, and burden
  estimation from multi-class episode data.

- [`vignette("geography-assignment")`](https://andrew-farrey.github.io/sysPrep/articles/geography-assignment.md):
  When to use
  [`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md)
  versus
  [`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md),
  the `Region` field format, and consequences of discarding out-of-state
  visits in facility-level analyses.
