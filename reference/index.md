# Package index

## Deduplication

ESSENCE data frequently contains multiple rows for the same visit due to
data feed retransmissions, midnight-crossing date changes, patient
identifier corrections, and patient class transitions. These functions
identify, characterize, and remove duplicate records that would
otherwise inflate case counts or create false-positive clusters.

- [`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md)
  : Remove duplicate records from an ESSENCE data pull
- [`summarize_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/summarize_duplicates.md)
  : Summarize duplicate records in an ESSENCE data pull
- [`classify_duplicates()`](https://andrew-farrey.github.io/sysPrep/reference/classify_duplicates.md)
  : Classify the mechanism of duplication in an ESSENCE data pull

## Care Setting Quality Assurance

The ESSENCE API returns all facilities that submitted matching records,
including non-emergency providers (primary care clinics, specialty
practices). Free-standing emergency departments (FSEDs) may be onboarded
with a FacilityType of “Urgent Care” – one of two valid ESSENCE facility
type assignments for FSEDs – which prevents front-end API filtering by
facility type from correctly identifying them as emergency providers.
These functions filter to valid care settings, correct known facility
type assignments before filtering, and flag facilities with anomalous
visit volumes.

- [`filter_care_setting()`](https://andrew-farrey.github.io/sysPrep/reference/filter_care_setting.md)
  : Filter ESSENCE data to valid emergency and inpatient care settings
- [`review_facility_ed_visits()`](https://andrew-farrey.github.io/sysPrep/reference/review_facility_ed_visits.md)
  : Review facility ED visit counts for data quality assessment

## Encounter Linkage

A row showing HasBeenAdmitted = 1 and HasBeenE = 0 can mean either a
genuine direct admission or a mis-submitted ED-to-inpatient continuity
break reported as two unrelated records – nothing in a single row tells
you which. The former is invisible to HasBeenE = 1 queries; the latter
double-counts a single encounter if left unlinked. link_encounters()
links ED and inpatient records into unified care episodes, correcting
both problems at once.

- [`link_encounters()`](https://andrew-farrey.github.io/sysPrep/reference/link_encounters.md)
  : Link ED and inpatient admission records into unified care episodes

## Geographic Attribution

ESSENCE records include out-of-state residents and visits with unknown
residential geography (OTHER_REGION). Discarding these visits
systematically understates burden at facilities serving cross-border
populations and can exclude real visits from cluster/anomaly detection
scoped to the treating facility’s county. assign_treating_geography()
implements a hybrid approach – preserving residential geography for
in-state patients while reassigning only out-of-state and OTHER_REGION
visits to the treating facility’s county. assign_facility_geography()
applies full incidence-at-location reassignment, attributing all visits
to the treating facility’s geography regardless of patient origin. Both
write to new columns by default (region_hybrid/region_facility), leaving
the original Region/ZipCode untouched, so calling either – or both,
chained – is always safe to try and safe to re-run.

- [`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md)
  : Assign treating facility geography to out-of-state and OTHER_REGION
  visits
- [`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md)
  : Assign facility geography to all visits for incidence-at-location
  analysis

## Data

Synthetic example datasets demonstrating common ESSENCE data quality
issues. All data are fully fabricated with no real patient, facility, or
geographic identifiers.

- [`essence_raw`](https://andrew-farrey.github.io/sysPrep/reference/essence_raw.md)
  : Synthetic raw ESSENCE-like ED visit data
- [`essence_clean`](https://andrew-farrey.github.io/sysPrep/reference/essence_clean.md)
  : Synthetic cleaned ESSENCE-like ED visit data
- [`essence_ed_raw`](https://andrew-farrey.github.io/sysPrep/reference/essence_ed_raw.md)
  : Synthetic raw ESSENCE-like ED pull for encounter linkage
- [`essence_inp_raw`](https://andrew-farrey.github.io/sysPrep/reference/essence_inp_raw.md)
  : Synthetic raw ESSENCE-like inpatient admission pull for encounter
  linkage
