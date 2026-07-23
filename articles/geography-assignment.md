# Geographic Attribution for Out-of-State and Unknown Residence Visits

## Why Out-of-State Visits Exist

ESSENCE surveillance is facility-based: every patient treated at a
participating facility is included in the data, regardless of where that
patient lives. A facility near a state border or serving a metropolitan
area that spans multiple states will routinely treat patients whose
address of record is in a neighboring state. These patients generate
valid, important clinical encounters – they may have overdosed at a
Kentucky location even if their home is in Indiana or West Virginia.

Two additional sources of non-Kentucky geography appear in ESSENCE data:

**`OTHER_REGION`** records represent patients for whom a residential
address is unavailable to the treating facility. This includes unhoused
patients, patients who cannot communicate their address, and patients
who decline to provide one. The `OTHER_REGION` value is not a geographic
unit – it is a placeholder indicating that no residential geography can
be assigned.

**Missing `Region`** occurs at facilities that do not transmit patient
address fields. These records appear with `NA` in the `Region` column.

## The Cost of Discarding These Visits

The common response to out-of-state and unknown-residence records is to
filter them out before analysis. This is understandable – residential
geography is the expected denominator for incidence-based rates – but it
introduces systematic bias:

**Burden understatement.** Facilities that treat a high volume of
out-of-state or transient patients see their case counts reduced
proportionally. A border facility that treats patients from three states
appears to have a much lower burden than its actual clinical workload
warrants.

**Spatial bias.** The exclusion rate is not uniform across facilities.
Facilities in rural border communities and urban trauma centers serving
mobile populations will have much higher exclusion rates than facilities
in geographically isolated inland areas. When these exclusions are not
accounted for, spatial comparisons across facilities are measuring a mix
of true incidence and differential data completeness.

**Secular trend distortion.** If the composition of a facility’s patient
population shifts over time – more transient patients, more border
traffic, or a policy change affecting unhoused populations – the
exclusion of `OTHER_REGION` records can create apparent trends in what
is actually a stable underlying burden.

`sysPrep` provides two functions for retaining these visits by
attributing them to the geography of the treating facility. The choice
of which function to use depends on the research question.

## What `Region` Actually Represents

> **Is `Region` an authoritative county boundary?** No. `Region` is
> ESSENCE’s standardized construct for enabling consistent sub-state
> reporting across data sources – a maintained, many-to-one
> zip-code-to-region lookup table, not a live geocode computed from each
> record. By default, a zip code is assigned to a region using its
> geographic centroid, but individual assignments can be – and routinely
> are – overridden by site or state administrators to better reflect
> where the bulk of a zip code’s population actually lives. The same
> logic applies to `HospitalRegion`: assigned from the facility’s zip
> centroid by default, but overridable to the facility’s listed county.
> Because of this approximation, results reported by `Region` should not
> be construed as the authoritative count for that county – they are the
> best available standardized proxy, and the mapping in effect today is
> not necessarily the mapping that applied when a record was first
> received.

This matters for `sysPrep` because both geography functions operate
entirely on `Region`/`HospitalRegion` as received – they reassign which
existing value applies to a row, they do not independently geocode or
validate the underlying zip-to-county mapping.

It also explains *why* two different functions exist at all, rather than
one that always attributes to “the” geography. ESSENCE itself
distinguishes between **patient location** and **facility location**
data sources:

- In a **patient location** pull (e.g., `va_er`), the display criterion
  is the patient’s residence – the data show who, from a given
  jurisdiction, presented for care anywhere.
- In a **facility location** pull (e.g., `va_hosp`), the display
  criterion is the treating facility – the data show everyone who
  presented at an in-jurisdiction facility, combining residents and
  visitors alike.

`essence_raw` and `essence_clean` model a patient location pull, so
`Region` reflects patient residence out of the box.
[`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md)
preserves that patient-location semantics for the in-state majority and
only substitutes facility geography as a fallback.
[`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md)
instead converts the dataset to facility-location semantics uniformly –
useful when your source pull, or your research question, is
facility-location in nature to begin with.

## The `Region` Field Format

ESSENCE encodes geography in the format `{SITE}_{REGION}`, where `SITE`
is the NSSP Site Short Name (e.g., `"KY"`) and `REGION` is the ESSENCE
Region – a county name derived from a zip-code-to-county lookup table
maintained by ESSENCE (e.g., `"Jefferson"`). Some site names contain
additional underscores (e.g., multi-word state abbreviations used in
certain NSSP configurations), so the site prefix is defined as all
characters before the **last** underscore in the string.

Both geography functions use the same detection logic: - A visit is
classified as **in-state** when `Region` begins with `paste0(site, "_")`
(e.g., `"KY_"` for `site = "KY"`). - A visit is classified as
**out-of-state or unknown** when `Region` begins with a different
prefix, is exactly `"OTHER_REGION"`, or is `NA`.

``` r

# Illustrate the detection logic on a few example values
region_examples <- c("KY_Jefferson", "TN_Davidson", "OH_Hamilton",
                     "OTHER_REGION", NA_character_)

data.frame(
  region   = region_examples,
  in_state = startsWith(
    tidyr::replace_na(region_examples, ""),
    "KY_"
  ) & !is.na(region_examples)
)
#>         region in_state
#> 1 KY_Jefferson     TRUE
#> 2  TN_Davidson    FALSE
#> 3  OH_Hamilton    FALSE
#> 4 OTHER_REGION    FALSE
#> 5         <NA>    FALSE
```

## Two Functions, Two Philosophies

`sysPrep` provides two geographic attribution functions that differ
fundamentally in **which rows are modified**:

|  | [`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md) | [`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md) |
|----|----|----|
| **Rows modified** | Out-of-state + `OTHER_REGION` + `NA` only | **All rows** |
| **In-state patient geography** | Preserved unchanged | Overwritten |
| **Research question** | Where did this care take place? (for non-residents only) | Where did all care take place? |
| **Resulting `Region` meaning** | Mixed: residential for in-state, treating for out-of-state | Treating facility county for everyone |

This distinction matters for how the resulting data should be
interpreted and which analyses it supports.

## `assign_treating_geography()`: Selective Hybrid Reassignment

[`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md)
is a **targeted intervention** on problem rows. It identifies visits
where the patient geography is unavailable or out-of-area and replaces
their `Region` with the treating facility’s county. In-state patient
geography is left exactly as received from ESSENCE.

The resulting dataset is a **hybrid**: `Region` contains residential
geography for patients who provided an in-state address, and treating
facility geography for patients who could not or did not. This hybrid is
appropriate for area-based incidence analyses where you want to count as
many visits as possible within your surveillance area, and where the
distinction between resident and non-resident burden is not the primary
analytical question.

``` r

# Start from deduplicated, filtered data
ed_clean <- essence_raw |>
  dedupe(order_by = Arrived_Date_Time, keep = "last") |>
  filter_care_setting(
    fix_facility_type_vector = c("Hillside FSED", "Downtown Emergency Services")
  )
#> The following `FacilityType` values are not in `keep_types` and will be excluded:
#>   - Medical Specialty
#>   - Primary Care

# Selective reassignment: only out-of-state and OTHER_REGION rows change
treating_geo <- ed_clean |>
  assign_treating_geography(
    site                        = "KY",
    preserve_original_geographies = TRUE
  )
#> 27 of 160 visits (16.9%) identified as out-of-state or OTHER_REGION and
#> assigned treating facility geography.
```

``` r

# How many visits were reassigned?
dplyr::count(treating_geo, .out_of_state)
#> # A tibble: 2 × 2
#>   .out_of_state     n
#>   <lgl>         <int>
#> 1 FALSE           133
#> 2 TRUE             27
```

``` r

# Compare region before and after for reassigned rows
treating_geo |>
  dplyr::filter(.out_of_state) |>
  dplyr::select(hospital_name, original_region, region) |>
  head(10)
#> # A tibble: 10 × 3
#>    hospital_name               original_region region      
#>    <chr>                       <chr>           <chr>       
#>  1 Central Medical Center      TN_Davidson     KY_Jefferson
#>  2 Central Medical Center      OH_Hamilton     KY_Jefferson
#>  3 Central Medical Center      OH_Franklin     KY_Jefferson
#>  4 Central Medical Center      NA              KY_Jefferson
#>  5 Central Medical Center      OTHER_REGION    KY_Jefferson
#>  6 Central Medical Center      TN_Shelby       KY_Jefferson
#>  7 Central Medical Center      OH_Hamilton     KY_Jefferson
#>  8 Downtown Emergency Services NA              KY_Fayette  
#>  9 Hillside FSED               NA              KY_Jefferson
#> 10 Hillside FSED               OTHER_REGION    KY_Jefferson
```

The `.out_of_state` column (logical) marks every row where geography was
modified. Rows where `.out_of_state = FALSE` are unchanged – `region`
still reflects the patient’s residential county as ESSENCE recorded it.

When `preserve_original_geographies = TRUE`, `original_region` and
`original_zip_code` are added before overwriting, retaining
pre-reassignment values for audit trails or downstream QA. For in-state
visits, `original_region` is `NA` because no change was made.

**When to use
[`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md):**

- Incidence estimation where you want residential geography for most
  patients and facility geography only as a fallback for patients
  without valid residential addresses.
- Trend analyses where you need to retain border-facility visits without
  attributing all visits to facility location.
- Sensitivity analyses: compare results with and without `OTHER_REGION`
  visits using the `.out_of_state` flag to filter.

## `assign_facility_geography()`: Universal Full Reassignment

[`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md)
takes a fundamentally different approach: **every row** has its `Region`
replaced with `HospitalRegion`, regardless of whether the patient was
in-state, out-of-state, or unknown. The resulting `Region` column no
longer reflects where patients live – it reflects where they received
care.

``` r

# Universal reassignment: ALL rows get facility geography
facility_geo <- ed_clean |>
  assign_facility_geography(
    preserve_original_geographies = TRUE
  )
#> Facility geography applied to all 160 visits (region and zip).
```

``` r

# After full reassignment, region = hospital_region for all rows
facility_geo |>
  dplyr::select(hospital_name, hospital_region, region, original_region) |>
  head(10)
#> # A tibble: 10 × 4
#>    hospital_name          hospital_region region       original_region
#>    <chr>                  <chr>           <chr>        <chr>          
#>  1 Central Medical Center KY_Jefferson    KY_Jefferson TN_Davidson    
#>  2 Central Medical Center KY_Jefferson    KY_Jefferson KY_Kenton      
#>  3 Central Medical Center KY_Jefferson    KY_Jefferson KY_Campbell    
#>  4 Central Medical Center KY_Jefferson    KY_Jefferson OH_Hamilton    
#>  5 Central Medical Center KY_Jefferson    KY_Jefferson OH_Franklin    
#>  6 Central Medical Center KY_Jefferson    KY_Jefferson KY_McCracken   
#>  7 Central Medical Center KY_Jefferson    KY_Jefferson KY_Daviess     
#>  8 Central Medical Center KY_Jefferson    KY_Jefferson KY_Daviess     
#>  9 Central Medical Center KY_Jefferson    KY_Jefferson NA             
#> 10 Central Medical Center KY_Jefferson    KY_Jefferson KY_Campbell
```

``` r

# Confirm: region == hospital_region for every row
all(facility_geo$region == facility_geo$hospital_region)
#> [1] TRUE
```

Note that `original_region` now contains a value for every row –
including in-state patients – because all rows were modified. This is
the key difference from
[`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md),
where `original_region` is `NA` for rows that were not changed.

> **Is this only renaming `HospitalRegion` to `Region`?** Mechanically,
> yes –
> [`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md)
> replaces `Region` with `HospitalRegion` and/or `ZipCode` with
> `HospitalZip` for all rows, depending on which columns are present in
> the pull. Not all analysts include both; zip-based geography carries
> its own methodological considerations around spatial resolution and
> boundary alignment that may not be appropriate for every analysis.
> When only `HospitalRegion` is present, only region is reassigned. Some
> practitioners have applied this rename informally as an ad hoc
> pipeline step. `sysPrep` formalizes that practice – documents the
> intent, handles whichever geography types are available, and makes
> retaining the originals via `preserve_original_geographies = TRUE` the
> recommended default so the pre-reassignment values are always
> available for audit or comparison.
> [`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md)
> – the hybrid selective approach – has no simple column-rename
> equivalent, which is what motivated formalizing both methods in the
> same package.

Hospital-level spatial clustering (point-based) concentrates
observations at individual facility locations and can identify which
specific facilities are experiencing elevated burden – including spikes
that would be diluted or invisible at the regional level. However,
hospital-level scan statistics generally do not explicitly model
residual spatial autocorrelation or facility-specific reporting patterns
as nuisance structure. In prospective surveillance, scanning windows may
therefore interact with hospital density, catchment patterns, and data
submission variability in ways that can produce apparent clusters
independent of true changes in underlying incidence. This concern is
more pronounced in urban areas, where hospitals are denser and
submission patterns may vary across nearby facilities. Reassigning all
visits to `HospitalRegion` before aggregation reduces facility-level
noise by aggregating across treating facilities within a region –
allowing spacetime permutation methods and other scan statistics to
treat a rural county with one hospital comparably to an urban county
with many. Region-level binning does not eliminate spatial
autocorrelation concerns, but it reduces the influence of
facility-specific variability that is more common in high-density areas.

A second advantage is logistical: hospital-level spatial clustering
requires latitude/longitude coordinates from the NSSP Master Facility
Table, an additional lookup outside the standard ESSENCE data pull.
Region-level attribution achieves a close approximation of
hospital-level cluster detection using `HospitalRegion` – a field
already present in every ESSENCE pull.

The two approaches are complementary: hospital-based clustering offers
facility-level resolution; region-based clustering offers geographic
equity across areas of differing hospital density. The choice depends on
whether the surveillance question is “which facility?” or “which area?”.

**When to use
[`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md):**

- Analyses framed around treating facility location rather than patient
  residence: “How many cases were treated in Jefferson County?” rather
  than “How many residents of Jefferson County were treated?”
- Facility service area analyses where you want all visits attributed to
  the county where the facility is located.
- Spatial cluster detection scoped to treating location (e.g.,
  identifying counties with high overdose treatment burden regardless of
  patient origin).
- Cross-state facility comparisons where residential geography is an
  inappropriate common denominator.

## The Core Distinction: What Does `Region` Mean After Reassignment?

The choice between the two functions is a choice about what the `Region`
column should represent in your analytic dataset:

**After
[`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md):**
`Region` = residential geography for in-state patients + treating
facility geography for out-of-state and unknown-residence patients.

This is a **hybrid** with mixed semantics. It is most useful when you
want to maximize the number of visits attributed to your surveillance
area while preserving the residential geography of the majority.

**After
[`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md):**
`Region` = treating facility geography for all patients.

This is semantically **uniform** – `Region` means the same thing for
every row. It is most useful when the analytical unit is where care was
delivered, not where patients live.

Neither function is universally correct. The choice should be documented
in your analysis methods and driven by the research question.

## Decision Guide

| Research question | Function | Rationale |
|----|----|----|
| County-level incidence rate (retain most OOS visits) | [`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md) | Preserves residential geography for in-state majority; uses facility geography as fallback |
| Which counties have highest treatment burden? | [`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md) | All visits attributed to treating county uniformly |
| Where do patients live who are treated at this facility? | Neither – use `Region` directly | Residential geography is the question; don’t reassign |
| Spatial cluster detection by facility county | [`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md) | Uniform attribution aligns with facility-based cluster geometry |
| Sensitivity analysis: effect of OOS exclusion | [`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md) | Use `.out_of_state` flag to toggle OOS visits in/out |
| Trend analysis, mixed state border facility | [`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md) | Avoids flattening in-state residential variation |

## `preserve_original_geographies = TRUE`

Both functions accept `preserve_original_geographies = TRUE`, which adds
`original_region` and `original_zip_code` columns before overwriting.

For
[`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md),
these columns contain pre-reassignment values only for rows where
geography changed (`.out_of_state = TRUE`). For in-state visits, they
are `NA`.

For
[`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md),
these columns contain pre-reassignment values for **every row**, because
every row is modified.

This parameter is recommended in production pipelines as an audit trail.
It adds two columns but enables downstream verification that
reassignments are occurring as expected and facilitates comparison of
results computed under residential versus treating geography.
