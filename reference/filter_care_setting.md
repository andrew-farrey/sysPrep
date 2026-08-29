# Filter ESSENCE data to valid emergency and inpatient care settings

Retains visits from facilities with emergency department or inpatient
admission capacity. Optionally corrects known `FacilityType`
misclassifications – such as free-standing EDs (FSEDs) onboarded with
non-emergency facility types – before the keep filter is applied,
ensuring valid ED visits are not incorrectly excluded.

## Usage

``` r
filter_care_setting(
  data,
  facility_col = HospitalName,
  facility_type_col = FacilityType,
  facility_id_col = Hospital,
  keep_types = c("Emergency Care", "Inpatient Practice Setting"),
  fix_facility_id_vector = NULL,
  fix_facility_type_vector = NULL,
  fix_facility_type_regex = NULL,
  fix_to = "Emergency Care",
  dry_run = FALSE,
  clean_names = TRUE,
  verbose = TRUE
)
```

## Arguments

- data:

  A data frame of ESSENCE visit-level records, typically the output of
  [`dedupe()`](https://andrew-farrey.github.io/sysPrep/reference/dedupe.md).

- facility_col:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Unquoted column name identifying the facility. Defaults to
  `HospitalName`. Accepts both raw ESSENCE names and
  post-[`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)
  equivalents.

- facility_type_col:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Unquoted column name identifying the facility type. Defaults to
  `FacilityType`. Accepts both raw ESSENCE names and
  post-[`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)
  equivalents.

- facility_id_col:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Unquoted column name identifying the facility's stable numeric ID.
  Defaults to `Hospital` (`C_BioSense_Facility_ID` in the NSSP Master
  Facility Table). Accepts both raw ESSENCE names and
  post-[`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)
  equivalents, and any arbitrarily-named column. Optional – if absent
  and `fix_facility_id_vector` is not supplied, ID-based correction is
  skipped with an informative message.

- keep_types:

  Character vector of `FacilityType` values to retain after corrections
  are applied. Defaults to
  `c("Emergency Care", "Inpatient Practice Setting")` for ED + inpatient
  cohorts. Set to `"Emergency Care"` for ED-only cohorts. Values are
  matched exactly, including capitalization.

- fix_facility_id_vector:

  Optional numeric or character vector of exact facility IDs as they
  appear in `facility_id_col`. Matching facilities have their
  `FacilityType` set to `fix_to` before filtering. Both the supplied
  vector and the data column are coerced to character before matching,
  so numeric and character forms of the same IDs behave identically.
  More durable than `fix_facility_type_vector` for a correction list
  reused across many pulls, since facility IDs do not change when a
  facility is renamed. Unmatched IDs never produce a warning – see
  Details.

- fix_facility_type_vector:

  Optional character vector of exact facility names as they appear in
  `facility_col`. Matching facilities have their `FacilityType` set to
  `fix_to` before filtering. Use for known FSEDs or other facilities
  with confirmed misclassifications. Unmatched names only produce a
  warning when `dry_run = TRUE` – see Details.

- fix_facility_type_regex:

  Optional regular expression matched against `facility_col` values.
  Facilities not already corrected by `fix_facility_id_vector` or
  `fix_facility_type_vector` whose names match the pattern have their
  `FacilityType` set to `fix_to`. Matched names are always surfaced in a
  warning as candidates for `fix_facility_type_vector` or
  `fix_facility_id_vector`.

- fix_to:

  Character string. The `FacilityType` value assigned to facilities
  matched by any correction parameter. Defaults to `"Emergency Care"`.

- dry_run:

  Logical. If `TRUE`, returns a preview tibble showing each facility's
  original facility type, corrected facility type, visit count, and
  whether it would be retained – without modifying or filtering the
  data. Defaults to `FALSE`.

- clean_names:

  Logical. If `TRUE` (default), applies
  [`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)
  to standardize column names to snake_case on output.

- verbose:

  Logical. If `FALSE`, suppresses informational messages
  ([`rlang::inform()`](https://rlang.r-lib.org/reference/abort.html));
  warnings and errors are always shown regardless.

## Value

When `dry_run = FALSE` (default), a filtered data frame retaining only
visits from facilities whose `FacilityType` – after any corrections –
appears in `keep_types`. When `dry_run = TRUE`, a tibble with columns
`facility`, `facility_id` (when `facility_id_col` resolves),
`original_facility_type`, `corrected_facility_type`, `n_visits`, and
`.would_keep`, arranged by `n_visits` descending.

## Details

### Why this function exists

The most reliable way to isolate emergency department visits from
non-emergency providers is to filter to a valid `FacilityType` before or
during case counting. Where a site's facilities are consistently
onboarded to ESSENCE, restricting the query itself to
`FacilityType = "Emergency Care"` (a front-end filter, applied before
the pull) avoids returning non-ED provider data at all. This approach
worked reliably for years in Kentucky – until several free-standing
emergency departments (FSEDs) were onboarded to ESSENCE with a
`FacilityType` other than `"Emergency Care"`. A front-end query filtered
to `FacilityType = "Emergency Care"` now silently excludes these FSEDs'
legitimate ED visits, even though each operates a true emergency
department.

Once front-end filtering by `FacilityType` can no longer be trusted for
a site, a raw pull returns every facility type that submitted matching
records – including primary care clinics, specialty practices, and other
genuinely non-ED providers whose visits should not contribute to an
ED-based numerator or denominator. `filter_care_setting()` addresses
this by first correcting the small, known set of misclassified
facilities (by name, ID, or pattern) to a valid ED-consistent
`FacilityType`, then filtering to `keep_types`. This makes it possible
to filter reproducibly and defensibly on `FacilityType` again, without
excluding true ED visits or manually rebuilding the correction list for
every pull. Whether this pre-cleaning step is worthwhile depends on a
site's own onboarding consistency – sites where `FacilityType` reliably
identifies emergency providers may not need it at all.

### FSED facility type assignment

The specific pattern observed in Kentucky's ESSENCE data is that some
FSEDs are onboarded with a `FacilityType` of `"Urgent Care"` rather than
`"Emergency Care"`. This reflects what has been observed and processed
in Kentucky's data specifically – it is not a documented or guaranteed
convention across all NSSP sites, and other sites may see FSEDs (or
other facility types) onboarded under different `FacilityType` values
entirely. Regardless of which value a given site observes, the
`fix_facility_type_vector`, `fix_facility_id_vector`, and
`fix_facility_type_regex` parameters exist to reassign known
misclassified facilities to a specified `fix_to` value before the
`keep_types` filter is applied.

### Kentucky data structure

In Kentucky, inpatient admission data are transmitted through the
corresponding ED hospital feeds and share the same `FacilityType`. The
default `keep_types` of
`c("Emergency Care", "Inpatient Practice Setting")` reflects this
structure. Sites pulling ED visits only should set
`keep_types = "Emergency Care"`.

### Processing order

Corrections are applied before filtering, in this sequence:

1.  Exact ID corrections (`fix_facility_id_vector`)

2.  Exact name corrections (`fix_facility_type_vector`)

3.  Regex name corrections (`fix_facility_type_regex`)

4.  Filter to `keep_types`

ID and name corrections are both exact-match methods and take precedence
over regex – a facility corrected by either `fix_facility_id_vector` or
`fix_facility_type_vector` will not be re-evaluated by
`fix_facility_type_regex`, even if its name also happens to match the
pattern.

### Facility ID vs. facility name corrections

`fix_facility_id_vector` matches on `facility_id_col` (`Hospital` /
`C_BioSense_Facility_ID` by default), which does not change even when a
facility's name is edited or the facility is rebranded. For a correction
list reused across many recurring pulls, ID-based correction is more
durable than name-based correction. `fix_facility_type_vector` remains
available for cases where the ID isn't known or `Hospital` wasn't
included as a pull field. Both accept the same `fix_to` value and can be
used together.

### dry_run preview

When `dry_run = TRUE`, the function returns a preview tibble showing
each facility's original and corrected `FacilityType`, visit count, and
whether it would be retained – without modifying the data. Use this to
verify corrections and `keep_types` before committing to a filter.

### Warnings and dry_run

Facilities matched and corrected via `fix_facility_type_regex` are
always surfaced in a warning, since regex matching is open-ended – a
newly onboarded facility could start matching the pattern at any time,
which is worth knowing about on every run, not just during setup. These
are candidates for promotion to `fix_facility_type_vector` or
`fix_facility_id_vector` for explicitness and long-term reproducibility.

Unmatched entries in `fix_facility_type_vector` (a name with zero
matching rows in this pull) only produce a warning when
`dry_run = TRUE`. A persistent correction list reused across many pulls
will routinely include facilities with zero visits in a given pull –
this is expected, not an error, so it isn't surfaced on ordinary
(non-`dry_run`) runs. `dry_run` is the intended point to verify a
correction list is behaving as expected. Unmatched entries in
`fix_facility_id_vector` never produce a warning, at any setting, for
the same reason.

## See also

[`review_facility_ed_visits()`](https://andrew-farrey.github.io/sysPrep/reference/review_facility_ed_visits.md)
for flagging facility-level visit count outliers after filtering.

## Examples

``` r
# Default: keep Emergency Care and Inpatient Practice Setting
essence_raw |> filter_care_setting()
#> The following `FacilityType` values are not in `keep_types` and will be excluded:
#>   - Medical Specialty
#>   - Urgent Care
#>   - Primary Care
#> # A tibble: 144 × 19
#>    hospital_name    hospital facility_type hospital_region hospital_zip visit_id
#>    <chr>               <int> <chr>         <chr>           <chr>        <chr>   
#>  1 Lakeside Commun…     1004 Emergency Ca… KY_Boone        41042        V196531…
#>  2 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V658452…
#>  3 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V569882…
#>  4 Lakeside Commun…     1004 Emergency Ca… KY_Boone        41042        V566810…
#>  5 River Valley Me…     1003 Emergency Ca… KY_Warren       42101        V875653…
#>  6 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V206307…
#>  7 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V154413…
#>  8 River Valley Me…     1003 Emergency Ca… KY_Warren       42101        V134685…
#>  9 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V916885…
#> 10 North County Ho…     1002 Emergency Ca… KY_Kenton       41011        V386525…
#> # ℹ 134 more rows
#> # ℹ 13 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>,
#> #   pull_source <chr>

# ED-only cohort
essence_raw |> filter_care_setting(keep_types = "Emergency Care")
#> The following `FacilityType` values are not in `keep_types` and will be excluded:
#>   - Medical Specialty
#>   - Urgent Care
#>   - Primary Care
#> # A tibble: 144 × 19
#>    hospital_name    hospital facility_type hospital_region hospital_zip visit_id
#>    <chr>               <int> <chr>         <chr>           <chr>        <chr>   
#>  1 Lakeside Commun…     1004 Emergency Ca… KY_Boone        41042        V196531…
#>  2 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V658452…
#>  3 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V569882…
#>  4 Lakeside Commun…     1004 Emergency Ca… KY_Boone        41042        V566810…
#>  5 River Valley Me…     1003 Emergency Ca… KY_Warren       42101        V875653…
#>  6 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V206307…
#>  7 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V154413…
#>  8 River Valley Me…     1003 Emergency Ca… KY_Warren       42101        V134685…
#>  9 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V916885…
#> 10 North County Ho…     1002 Emergency Ca… KY_Kenton       41011        V386525…
#> # ℹ 134 more rows
#> # ℹ 13 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>,
#> #   pull_source <chr>

# Preview what would be filtered before committing
essence_raw |>
  filter_care_setting(
    fix_facility_type_vector = c("Hillside FSED", "Downtown Emergency Services"),
    dry_run = TRUE
  )
#> # A tibble: 10 × 6
#>    facility   facility_id original_facility_type corrected_facility_t…¹ n_visits
#>    <chr>            <int> <chr>                  <chr>                     <int>
#>  1 Central M…        1001 Emergency Care         Emergency Care               44
#>  2 Metro Hea…        1005 Emergency Care         Emergency Care               31
#>  3 Lakeside …        1004 Emergency Care         Emergency Care               22
#>  4 North Cou…        1002 Emergency Care         Emergency Care               22
#>  5 Hillside …        1007 Urgent Care            Emergency Care               20
#>  6 River Val…        1003 Emergency Care         Emergency Care               16
#>  7 Downtown …        1008 Urgent Care            Emergency Care               13
#>  8 Cardiolog…        1010 Medical Specialty      Medical Specialty            11
#>  9 Rural Hea…        1006 Emergency Care         Emergency Care                9
#> 10 Westside …        1009 Primary Care           Primary Care                  9
#> # ℹ abbreviated name: ¹​corrected_facility_type
#> # ℹ 1 more variable: .would_keep <lgl>

# Exact FSED corrections
essence_raw |>
  filter_care_setting(
    fix_facility_type_vector = c(
      "Hillside FSED",
      "Downtown Emergency Services"
    )
  )
#> The following `FacilityType` values are not in `keep_types` and will be excluded:
#>   - Medical Specialty
#>   - Primary Care
#> # A tibble: 177 × 19
#>    hospital_name    hospital facility_type hospital_region hospital_zip visit_id
#>    <chr>               <int> <chr>         <chr>           <chr>        <chr>   
#>  1 Lakeside Commun…     1004 Emergency Ca… KY_Boone        41042        V196531…
#>  2 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V658452…
#>  3 Hillside FSED        1007 Emergency Ca… KY_Jefferson    40202        V787824…
#>  4 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V569882…
#>  5 Hillside FSED        1007 Emergency Ca… KY_Jefferson    40202        V231263…
#>  6 Lakeside Commun…     1004 Emergency Ca… KY_Boone        41042        V566810…
#>  7 River Valley Me…     1003 Emergency Ca… KY_Warren       42101        V875653…
#>  8 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V206307…
#>  9 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V154413…
#> 10 River Valley Me…     1003 Emergency Ca… KY_Warren       42101        V134685…
#> # ℹ 167 more rows
#> # ℹ 13 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>,
#> #   pull_source <chr>

# Regex fallback for catching FSEDs by name pattern
essence_raw |>
  filter_care_setting(
    fix_facility_type_vector = c("Hillside FSED"),
    fix_facility_type_regex  = "FSED|ED - Urgent Care"
  )
#> The following `FacilityType` values are not in `keep_types` and will be excluded:
#>   - Medical Specialty
#>   - Urgent Care
#>   - Primary Care
#> # A tibble: 164 × 19
#>    hospital_name    hospital facility_type hospital_region hospital_zip visit_id
#>    <chr>               <int> <chr>         <chr>           <chr>        <chr>   
#>  1 Lakeside Commun…     1004 Emergency Ca… KY_Boone        41042        V196531…
#>  2 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V658452…
#>  3 Hillside FSED        1007 Emergency Ca… KY_Jefferson    40202        V787824…
#>  4 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V569882…
#>  5 Hillside FSED        1007 Emergency Ca… KY_Jefferson    40202        V231263…
#>  6 Lakeside Commun…     1004 Emergency Ca… KY_Boone        41042        V566810…
#>  7 River Valley Me…     1003 Emergency Ca… KY_Warren       42101        V875653…
#>  8 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V206307…
#>  9 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V154413…
#> 10 River Valley Me…     1003 Emergency Ca… KY_Warren       42101        V134685…
#> # ℹ 154 more rows
#> # ℹ 13 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>,
#> #   pull_source <chr>

# ID-based corrections -- durable across facility name changes/rebranding
essence_raw |>
  filter_care_setting(fix_facility_id_vector = c(1007, 1008))
#> The following `FacilityType` values are not in `keep_types` and will be excluded:
#>   - Medical Specialty
#>   - Primary Care
#> # A tibble: 177 × 19
#>    hospital_name    hospital facility_type hospital_region hospital_zip visit_id
#>    <chr>               <int> <chr>         <chr>           <chr>        <chr>   
#>  1 Lakeside Commun…     1004 Emergency Ca… KY_Boone        41042        V196531…
#>  2 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V658452…
#>  3 Hillside FSED        1007 Emergency Ca… KY_Jefferson    40202        V787824…
#>  4 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V569882…
#>  5 Hillside FSED        1007 Emergency Ca… KY_Jefferson    40202        V231263…
#>  6 Lakeside Commun…     1004 Emergency Ca… KY_Boone        41042        V566810…
#>  7 River Valley Me…     1003 Emergency Ca… KY_Warren       42101        V875653…
#>  8 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V206307…
#>  9 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V154413…
#> 10 River Valley Me…     1003 Emergency Ca… KY_Warren       42101        V134685…
#> # ℹ 167 more rows
#> # ℹ 13 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>,
#> #   pull_source <chr>

# ID and name corrections can be combined
essence_raw |>
  filter_care_setting(
    fix_facility_id_vector   = 1007,
    fix_facility_type_vector = "Downtown Emergency Services"
  )
#> The following `FacilityType` values are not in `keep_types` and will be excluded:
#>   - Medical Specialty
#>   - Primary Care
#> # A tibble: 177 × 19
#>    hospital_name    hospital facility_type hospital_region hospital_zip visit_id
#>    <chr>               <int> <chr>         <chr>           <chr>        <chr>   
#>  1 Lakeside Commun…     1004 Emergency Ca… KY_Boone        41042        V196531…
#>  2 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V658452…
#>  3 Hillside FSED        1007 Emergency Ca… KY_Jefferson    40202        V787824…
#>  4 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V569882…
#>  5 Hillside FSED        1007 Emergency Ca… KY_Jefferson    40202        V231263…
#>  6 Lakeside Commun…     1004 Emergency Ca… KY_Boone        41042        V566810…
#>  7 River Valley Me…     1003 Emergency Ca… KY_Warren       42101        V875653…
#>  8 Metro Health Sy…     1005 Emergency Ca… KY_Fayette      40507        V206307…
#>  9 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V154413…
#> 10 River Valley Me…     1003 Emergency Ca… KY_Warren       42101        V134685…
#> # ℹ 167 more rows
#> # ℹ 13 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>,
#> #   pull_source <chr>

# Full pipeline
essence_raw |>
  dedupe(order_by = Arrived_Date_Time) |>
  filter_care_setting(
    fix_facility_type_vector = c("Hillside FSED", "Downtown Emergency Services")
  )
#> The following `FacilityType` values are not in `keep_types` and will be excluded:
#>   - Medical Specialty
#>   - Primary Care
#> # A tibble: 164 × 19
#>    hospital_name    hospital facility_type hospital_region hospital_zip visit_id
#>    <chr>               <int> <chr>         <chr>           <chr>        <chr>   
#>  1 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V100855…
#>  2 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V121981…
#>  3 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V138461…
#>  4 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V147096…
#>  5 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V154413…
#>  6 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V164608…
#>  7 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V176732…
#>  8 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V179024…
#>  9 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V188198…
#> 10 Central Medical…     1001 Emergency Ca… KY_Jefferson    40201        V198982…
#> # ℹ 154 more rows
#> # ℹ 13 more variables: c_bio_sense_id <chr>, c_unique_patient_id <chr>,
#> #   date <date>, c_visit_date_time <dttm>, arrived_date_time <dttm>,
#> #   has_been_e <int>, has_been_admitted <int>, c_patient_class <chr>,
#> #   region <chr>, zip_code <chr>, sex <chr>, c_patient_age <int>,
#> #   pull_source <chr>
```
