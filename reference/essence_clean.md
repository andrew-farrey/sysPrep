# Synthetic cleaned ESSENCE-like ED visit data

The result of running `essence_raw` through the full `sysPrep`
preprocessing pipeline: deduplication, care setting filtering with FSED
correction, and both geography attribution functions chained on their
default (additive) behavior: `region`/`zip_code` are the untouched
originals throughout;
[`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md)
and
[`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md)
each add their own new columns alongside them rather than overwriting.
Intended to demonstrate the expected output of the package workflow and
to serve as a reference for function output structure.

## Usage

``` r
essence_clean
```

## Format

A data frame with approximately 160 rows and 24 columns. All column
names are in snake_case (post
[`janitor::clean_names()`](https://sfirke.github.io/janitor/reference/clean_names.html)).

- hospital_name:

  Character. Synthetic facility name.

- hospital:

  Integer. Synthetic numeric facility identifier.

- facility_type:

  Character. ESSENCE facility type. Non-ED providers have been removed;
  FSED corrections applied.

- hospital_region:

  Character. Facility ESSENCE Region in `{SITE}_{REGION}` format.

- hospital_zip:

  Character. Facility zip code.

- visit_id:

  Character. Synthetic visit identifier, unique within a facility.

- c_bio_sense_id:

  Character. Synthetic BioSense record identifier. One unique value per
  visit after deduplication.

- c_unique_patient_id:

  Character. Synthetic patient identifier.

- date:

  Date. Visit date.

- c_visit_date_time:

  POSIXct. Timestamp of the actual clinical encounter.

- arrived_date_time:

  POSIXct. NSSP record receipt timestamp.

- has_been_e:

  Integer. `1` for an ED pull; `0` on the two visits where a
  `patient_class_change` direct-admit row outranked the ED row under
  `dedupe(keep = "last")`; see `c_patient_class` and
  [`?essence_raw`](https://andrew-farrey.github.io/sysPrep/reference/essence_raw.md).

- has_been_admitted:

  Integer. `1` if the visit resulted in inpatient admission.

- c_patient_class:

  Character. ESSENCE-derived single-letter patient class. `"I"` on the
  two visits where deduplication kept the direct-admit continuation row
  over the original ED row (see
  [`?essence_raw`](https://andrew-farrey.github.io/sysPrep/reference/essence_raw.md));
  `"E"` otherwise. Unchanged by the preprocessing pipeline.

- region:

  Character. Patient ESSENCE Region of residence in `{SITE}_{REGION}`
  format, exactly as received; never modified by either geography
  function.

- zip_code:

  Character. Patient zip code, exactly as received.

- sex:

  Character. `"M"`, `"F"`, or `"U"`.

- c_patient_age:

  Integer. Patient age in years.

- .out_of_state:

  Logical. `TRUE` for visits where `region` is out-of-state,
  `"OTHER_REGION"`, or unknown residence; these are the visits where
  `region_hybrid` differs from `region`. Added by
  [`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md).

- region_hybrid:

  Character. `region` for in-state visits; `hospital_region` for
  out-of-state/`OTHER_REGION`/unknown-residence visits. Added by
  [`assign_treating_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_treating_geography.md).

- zip_code_hybrid:

  Character. `zip_code` analog of `region_hybrid`.

- region_facility:

  Character. `hospital_region` for every visit, regardless of patient
  residence. Added by
  [`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md).

- zip_code_facility:

  Character. `zip_code` analog of `region_facility`.

- .facility_geography:

  Logical. Always `TRUE`; signals that facility geography has been
  computed for every row. Added by
  [`assign_facility_geography()`](https://andrew-farrey.github.io/sysPrep/reference/assign_facility_geography.md).

## Source

Derived from
[essence_raw](https://andrew-farrey.github.io/sysPrep/reference/essence_raw.md)
via `data-raw/generate_synthetic_data.R`.

## See also

[essence_raw](https://andrew-farrey.github.io/sysPrep/reference/essence_raw.md)
for the raw version; the Getting Started vignette for the full pipeline
demonstration.
