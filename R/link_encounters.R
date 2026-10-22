
# link_encounters() ----
#' Link ED and inpatient admission records into unified care episodes
#'
#' Prevents overcounting distinct patients and visits when one real-world
#' episode of care is split across two separately queried ESSENCE pulls,
#' a duplication ESSENCE itself never flags. Links ED and direct-admit
#' inpatient records sharing the same `facility_col` x `visit_col` key
#' into one composite row per true care episode, reconciling field values
#' so information present on only one source row isn't discarded.
#'
#' @details
#' ## Why this matters for case counts
#'
#' Adding `HasBeenE = 0` to the inpatient query does not stop an ED visit
#' from being counted twice when you add inpatient admissions to ED counts.
#' It looks like a safe exclusion, and by the API's own field semantics it
#' should be: `HasBeenE = 0` means no ED encounter appears anywhere in that
#' record's history. But some records that correctly show `HasBeenE = 0`
#' were, clinically, discharged from the ED and immediately readmitted. The
#' ED encounter lives entirely on a separate record already captured in the
#' `HasBeenE = 1` pull, so the exclusion filter never catches it, and
#' summing the two pulls counts that share of ED visits a second time. This
#' is the same problem [dedupe()] solves for retransmitted or split ESSENCE
#' rows, except that the duplicate here doesn't share a flag value that would
#' mark it as related. `link_encounters()` finds the relationship directly,
#' by checking for a matching ED record under the same `facility_col` x
#' `visit_col` key, instead of trusting `HasBeenE` alone.
#'
#' ## The care pathway artifact problem
#'
#' A row showing `HasBeenAdmitted = 1` and `HasBeenE = 0`
#' (`C_Patient_Class = "I"` or `"D"`) can mean either of two very different
#' things, and nothing in that single row tells you which:
#'
#' **The continuity-break artifact.** The patient *was* triaged and treated
#' in the ED first, but the facility's system closed that encounter as a
#' discharge instead of tracking the ED-to-inpatient transition as one
#' continuous record. The result is two records sharing the same
#' `facility_col` x `visit_col` key: one correctly showing `HasBeenE = 1`,
#' one showing `HasBeenAdmitted = 1` and `HasBeenE = 0`, that otherwise
#' look unrelated. The ED record's fields (e.g. `Discharge_Disposition`,
#' `CCDD`, `C_Death`) reflect only what was known at ED discharge, not the
#' outcome of the encounter that actually continued. Counting both records
#' separately double-counts a single real-world event. This is a data
#' quality artifact, not a distinct clinical pathway.
#'
#' **The invisibility gap.** A patient admitted directly to an inpatient
#' unit without ED triage, via physician referral, a pre-arranged
#' admission, or similar, genuinely has `HasBeenAdmitted = 1` and
#' `HasBeenE = 0` with no preceding ED record to find. This visit never
#' appears in a `HasBeenE = 1` query regardless of which syndrome
#' definition or date range is used. This is a real clinical pathway, not
#' a data quality problem, but a `HasBeenE = 1`-only pull will always
#' miss it.
#'
#' The only way to tell these two cases apart is to check whether a
#' matching ED record exists under the same `facility_col` x `visit_col`
#' key. `link_encounters()` does exactly this: it links records sharing
#' that key (the continuity-break artifact's records already share it --
#' no cross-`Visit_ID` matching is needed), and, by default, merges each
#' episode's rows into one composite row so information from the
#' direct-admit record is reconciled onto the surviving row rather than
#' discarded.
#'
#' ## Merge behavior (`return_format = "collapsed"`, the default)
#'
#' Every column matching `has_been_*` is reconciled by taking the max across
#' the episode's rows: e.g., if the ED row has `HasBeenAdmitted = 0` and the
#' direct-admit row has `HasBeenAdmitted = 1`, the merged row correctly shows
#' `HasBeenAdmitted = 1`.
#'
#' Columns named in `merge_fields` are reconciled using the strategy assigned
#' to them:
#' \describe{
#'   \item{`"concat"`}{Starting from the primary row's value, appends each
#'     other row's non-empty value unless the accumulated text (`"; "`-
#'     separated) already contains it as whole words or whole codes, so
#'     complaint text or a diagnosis or SNOMED code present in one record but
#'     not the other is kept (`"fall"` is not found in `"waterfall"`, nor
#'     `"R10.9"` in `"R10.90"`). Generic free text.}
#'   \item{`"union_delimited"`}{Splits each row's value on `merge_delimiter`,
#'     takes the union of unique parts (preserving order of first
#'     appearance), rejoins with the same delimiter.}
#'   \item{`"union_ccdd"`}{Specific to ESSENCE's `CC-values|DD-values`
#'     structure (`CCDD`/`CCDDParsed`). Splits on `|` into CC/DD halves
#'     (fixed by the ESSENCE convention, not configurable), splits each half
#'     on `merge_delimiter`, unions unique values within each half
#'     separately, rejoins.}
#'   \item{`"prefer_yes"`}{If any row's value is affirmative (case-insensitive
#'     `"Yes"`, or `1`/`"1"` for 0/1-coded flag columns), the merged value is
#'     that row's affirmative value. Otherwise falls back to the primary
#'     row's value.}
#'   \item{`"prefer_admission"`}{Uses the value from whichever row's
#'     `patient_class` is `"Inpatient"`, `"Direct Admit"`, or `"Admitted"`,
#'     if such a row has a non-missing value for the field. Otherwise falls
#'     back to the primary row's value.}
#' }
#'
#' Any column not a `HasBeen_` flag and not listed in `merge_fields` takes
#' its value from the **primary row**: the `"ED"`-class row if one exists in
#' the episode, else the first row in original order.
#'
#' Set `return_format = "long"` to get the diagnostic long-format output
#' instead: one row per patient-class per episode, with no merge applied.
#' Useful for inspecting the raw linkage mechanism directly.
#'
#' ## Why `inpatient_admission_data` is required
#'
#' `link_encounters()` supplements the ED pull with a separately queried
#' inpatient pull (`HasBeenAdmitted = 1` or `HasBeenI = 1`). Rows with
#' `HasBeenE = 1` are automatically removed from the inpatient pull to
#' prevent duplicate rows for the same underlying record.
#'
#' A `HasBeenE = 1` pull cannot resolve the care pathway artifact problem on
#' its own, in either direction: a genuine direct admission (`HasBeenE = 0`)
#' is structurally absent from it by construction, and an ED-to-inpatient
#' escalation that *is* visible within it already lives on one
#' already-deduplicated record (both `HasBeenE` and `HasBeenAdmitted` set),
#' which needs no linking; there was never a second record to link
#' against. Supplying `inpatient_admission_data` is what makes linking
#' possible at all; `link_encounters()` aborts without it rather than
#' silently returning `ed_data` unchanged with cosmetic metadata columns
#' appended.
#'
#' **Do not row-bind `ed_data` and `inpatient_admission_data` into one data
#' frame and call [dedupe()] on the combined result instead of using the
#' two-pull approach above.** `dedupe()`'s `keep` strategies are not aware
#' of the distinction between an ED record and its corresponding
#' direct-admit record: both just look like two rows sharing a
#' `facility_col` x `visit_col` key, and will discard one of them based
#' on `order_by` rather than merging them, silently and unpredictably
#' reducing either the ED or the direct-admit count depending on which
#' record's `Arrived_Date_Time` happens to win. Always deduplicate each
#' pull separately, then pass both to `link_encounters()`.
#'
#' ## Linking key and its limitation
#'
#' Records are linked by `facility_col` \eqn{\times} `visit_col`
#' (`Hospital`/`C_BioSense_Facility_ID` \eqn{\times} `Visit_ID` by
#' default when `Hospital` is present, else `HospitalName` \eqn{\times}
#' `Visit_ID`; see `?dedupe`'s "Facility identifier preference" section).
#'
#' **Limitation:** if a facility's HL7 feed assigns a genuinely different
#' `Visit_ID` to the inpatient leg of a care episode, `link_encounters()`
#' cannot detect the relationship: the two records will appear as separate
#' episodes. This is a distinct scenario from the continuity-break artifact
#' above (which assumes the `Visit_ID` is shared) and is not addressed by
#' this function. If your data
#' includes `C_Unique_Patient_ID` (MRN), cross-referencing collapsed output
#' against a patient-level deduplication pass is a reasonable additional QA
#' step for this scenario.
#'
#' ## Patient class derivation: HasBeen_ pivot (standard)
#' `HasBeen_` flag columns (`HasBeenE`, `HasBeenAdmitted`/`HasBeenI`,
#' `HasBeenO`) are convenience columns that ESSENCE derives from
#' `C_Patient_Class_List`; they are easier to interpret and are the
#' fields most existing pulls and case definitions already include, so
#' `link_encounters()` uses them by default. They are pivoted to long
#' format, with each flag with value `1` contributing one row.
#' `HasBeenAdmitted` is preferred over `HasBeenI` when both are present.
#'
#' ## Patient class derivation: C_Patient_Class_List (optional, more granular)
#' `C_Patient_Class_List` is the underlying ESSENCE-computed field the
#' `HasBeen_` flags are themselves derived from: an alphabetic, deduplicated
#' list of all `C_Patient_Class` values present across messages sharing the
#' same ESSENCE ID (e.g., `"E"`, `"EI"`, `"EIO"`). When present, it is used
#' in place of the `HasBeen_` pivot, since it distinguishes patient classes
#' (e.g. Direct Admit vs. Inpatient, or Observation/Outpatient/Obstetrics/
#' Pre-admit/Recurring) that the `HasBeen_` flags do not represent. For more
#' granular and informative output, add `C_Patient_Class_List` to your
#' ESSENCE API pull fields. Splitting each character maps to the PHIN VADS
#' "Patient Class (Syndromic Surveillance)" value set (concept codes and
#' preferred names, verified against
#' <https://phinvads.cdc.gov/vads/ViewValueSet.action?id=564F8F8B-E1DE-E411-8970-0017A477041A>).
#' `link_encounters()`'s own derived `patient_class` output values (`"ED"`,
#' `"Inpatient"`, `"Direct Admit"`, etc.) are shortened working labels, not
#' required to match these preferred names verbatim:
#'
#' | Code | PHIN VADS preferred name |
#' |------|--------------------------|
#' | `D`  | Direct admit |
#' | `E`  | Emergency |
#' | `I`  | Inpatient |
#' | `V`  | Observation patient |
#' | `B`  | Obstetrics |
#' | `O`  | Outpatient |
#' | `P`  | Preadmit |
#' | `R`  | Recurring patient |
#'
#' ## Chronological ordering of `.patient_class_sequence`
#' `.patient_class_sequence` reflects the actual order encounters occurred
#' in, not alphabetical order: e.g. `"Direct Admit->ED"` when the
#' direct-admit record's timestamp precedes the ED record's, which is the
#' reverse of what typically indicates the continuity-break artifact
#' (an ED visit that transitions into a direct-admit readmission, not a
#' direct admit that precedes an ED visit). Ordering uses the first
#' available field, per row, in this priority:
#' \enumerate{
#'   \item **`C_Patient_Class_MDT_Updates`** (requires `C_Patient_Class_List`).
#'     A concatenated list of timestamps positionally aligned with
#'     `C_Patient_Class_List`, giving the exact moment each class was
#'     assigned; the only field that can order two classes assigned
#'     within a single record (e.g. `"EI"`). Rows where the two lists'
#'     lengths disagree fall back to the next tier.
#'   \item **`C_Visit_Date_Time`**. Applied per record: all classes
#'     derived from one record share that record's timestamp, so this only
#'     differentiates classes across separate records sharing the same
#'     `facility_col` x `visit_col` key (i.e. the ED record vs. the
#'     direct-admit record in the continuity-break artifact, or in the
#'     two-pull approach).
#'   \item **`Date` + `Time`** (both required). Combined into a timestamp
#'     when neither field above is present.
#' }
#' If none of these fields are present (or none can be parsed) anywhere in
#' the data, `link_encounters()` warns once and `.patient_class_sequence`
#' falls back to alphabetical order for every episode. Classes whose
#' timestamps are identical (every class derived from one record shares that
#' record's timestamp) are likewise listed alphabetically: the data cannot
#' say which came first, so that order carries no clinical meaning. Within a
#' single episode, if only some classes have a usable timestamp, timed classes
#' are ordered first and untimed classes are appended last.
#'
#' ## Split episodes with a missing visit_col on both sides
#' A missing `visit_col` value means that row's true identity is unknown,
#' not confirmed to match every other row with a missing value (see
#' [dedupe()]'s "Missing key values" section), so by default,
#' `link_encounters()` never merges two rows into one episode solely
#' because they share the same missing `visit_col`. This is the right
#' default when nothing else ties the rows together. But an ED row and a
#' direct-admit row that are genuinely the same real-world episode can
#' both have a missing `visit_col`, and ESSENCE may still give them a
#' matching secondary identifier: `C_BioSense_ID` is one field observed
#' (in real production data) to be assigned identically to a real
#' episode's ED and direct-admit rows even when `Visit_ID` is missing on
#' both, which is exactly the case `visit_col` alone cannot resolve.
#' `fallback_visit_col` lets you name that secondary identifier: whenever
#' a row is missing `visit_col`, `link_encounters()` matches it to
#' another row that is also missing `visit_col` and shares the same
#' `facility_col` and `fallback_visit_col` value, instead of treating it as
#' unmatchable. It does not link a row missing `visit_col` to a row that has
#' one: a secondary identifier such as `C_BioSense_ID` can change over a
#' visit's life (it is recomputed when the visit date changes), so it is only
#' trusted to pair two rows that both lack the primary key.
#' Rows with a non-missing `visit_col` are never affected, and a row
#' missing both `visit_col` and `fallback_visit_col` (or missing
#' `facility_col`) still gets its own unique episode, exactly as when
#' `fallback_visit_col` isn't supplied at all, which is the default
#' (`NULL`).
#'
#' ## Episode metadata columns
#' Present regardless of `return_format`. In collapsed output, these
#' describe the episode the collapsed row was built from (e.g.
#' `.episode_n_rows = 2` on a collapsed row means two original records were
#' merged into it).
#' \describe{
#'   \item{`.episode_id`}{A character key combining `facility_col` and
#'     `visit_col`, shared across all rows belonging to the same care
#'     episode. A row with a missing `facility_col` or `visit_col` value
#'     has an unknown identity, not one confirmed to match every other row
#'     with a missing value, so its `.episode_id` gets a unique numeric
#'     suffix instead of being shared with any other row, unless
#'     `fallback_visit_col` recovers the match; see Details.}
#'   \item{`.patient_class_sequence`}{All patient classes for the episode
#'     in chronological order and collapsed, e.g., `"Direct Admit->ED"`
#'     when the direct admit occurred first; see Details.}
#'   \item{`.episode_n_rows`}{Number of original rows the episode was built
#'     from before merging.}
#'   \item{`.index_encounter`}{In long format, `TRUE` on exactly one row per
#'     episode: the row the collapsed output is built from, which is the
#'     episode's first `"ED"` row if it has one, else its first row. Summing
#'     it therefore equals the number of rows in the collapsed output. In
#'     collapsed format, always `TRUE` (retained for schema consistency with
#'     long format).}
#' }
#'
#' @inheritParams dedupe
#' @inheritParams classify_duplicates
#' @param ed_data A deduplicated data frame of ED visits queried with
#'   `HasBeenE = 1`. Requires `HasBeenE` and at least one of
#'   `HasBeenAdmitted`/`HasBeenI` (the standard ESSENCE pull fields), or
#'   `C_Patient_Class_List` for more granular and informative output.
#' @param inpatient_admission_data Required. A deduplicated data frame of
#'   inpatient visits queried with `HasBeenAdmitted = 1` or `HasBeenI = 1`.
#'   Rows with `HasBeenE = 1` are automatically removed to prevent duplicate
#'   rows for the same underlying record. It must contain the same linking
#'   columns as `ed_data` (`facility_col`, `visit_col`, and
#'   `fallback_visit_col` if used), or `link_encounters()` aborts.
#'   `link_encounters()` also aborts if this is `NULL`; see Details.
#' @param facility_col Unquoted
#'   column name identifying the facility. When not supplied, prefers
#'   `Hospital`/`C_BioSense_Facility_ID` over `HospitalName` if present in
#'   `ed_data`; see `?dedupe`'s "Facility identifier preference" section
#'   for the full rationale. Accepts both raw ESSENCE names and
#'   post-[janitor::clean_names()] equivalents.
#' @param visit_col Unquoted
#'   column name identifying the visit. Defaults to `Visit_ID`. Accepts
#'   both raw ESSENCE names and post-[janitor::clean_names()] equivalents.
#'   Linking keys are identifiers with no numeric meaning, so `facility_col`
#'   (e.g. `Hospital`), this column, and `fallback_visit_col` are all held as
#'   text in the output, whatever type each pull delivered them in (the
#'   ESSENCE `dataDetails` API returns them as text; a CSV read may not).
#'   Numbers are written in full, without scientific notation, so `100000`
#'   becomes `"100000"`. Convert back after the call if you need numbers.
#' @param fallback_visit_col
#'   Optional. Unquoted column name of a secondary identifier (e.g.
#'   `C_BioSense_ID`) that matches two rows into one episode when
#'   `visit_col` is missing on both rows. Defaults to `NULL`,
#'   which preserves the default behavior of never merging rows solely
#'   because they share a missing `visit_col`; see Details.
#' @param merge_fields Named character vector mapping column names (raw
#'   ESSENCE names or post-[janitor::clean_names()] equivalents) to a merge
#'   strategy: one of `"concat"`, `"union_delimited"`, `"union_ccdd"`,
#'   `"prefer_yes"`, or `"prefer_admission"`. Only used when
#'   `return_format = "collapsed"`. Defaults to a curated set of ESSENCE
#'   fields known to carry information only visible in the direct-admit
#'   record; see Details. Extend or override for other fields as needed.
#' @param merge_delimiter Character string. Delimiter used by the
#'   `"union_delimited"` and `"union_ccdd"` strategies. Defaults to `";"`,
#'   matching ESSENCE's convention for `CCDDCategory_flat` and the
#'   within-half structure of `CCDD`/`CCDDParsed`.
#' @param return_format Character string. One of `"collapsed"` (default) or
#'   `"long"`. See Details.
#' @return When `return_format = "collapsed"` (default), a data frame with
#'   one row per true care episode, `HasBeen_` flags reconciled via max, and
#'   `merge_fields` columns reconciled per their assigned strategy. When
#'   `return_format = "long"`, a data frame in long format with one row per
#'   visit per patient class, unmerged. Both include episode metadata
#'   columns `.episode_id`, `.patient_class_sequence`, `.episode_n_rows`,
#'   and `.index_encounter`.
#'
#' @examples
#' # essence_ed_raw and essence_inp_raw are two small synthetic datasets
#' # representing the two separately queried ESSENCE pulls link_encounters()
#' # expects; see `?essence_ed_raw`/`?essence_inp_raw`
#' ed_clean <- essence_ed_raw |>
#'   dedupe(order_by = Arrived_Date_Time, keep = "last") |>
#'   filter_care_setting(
#'     fix_facility_type_vector = c(
#'       "Hillside FSED", "Downtown Emergency Services"
#'     )
#'   )
#' inpatient_clean <- dedupe(
#'   essence_inp_raw, order_by = Arrived_Date_Time, keep = "last"
#' )
#'
#' # One row per true encounter, merged
#' episodes <- link_encounters(ed_clean, inpatient_clean)
#' nrow(episodes)
#'
#' # Inspect the distribution of care pathways
#' episodes |>
#'   dplyr::count(.patient_class_sequence, sort = TRUE)
#'
#' # Long format: inspect the raw linkage mechanism directly
#' episodes_long <- link_encounters(
#'   ed_clean, inpatient_clean, return_format = "long"
#' )
#'
#' \dontrun{
#' # Real usage: two separate ESSENCE queries, each deduplicated on its own
#' ed_clean        <- essence_ed        |> dedupe(order_by = Arrived_Date_Time)
#' inpatient_clean <- essence_inpatient |> dedupe(order_by = Arrived_Date_Time)
#'
#' episodes_full <- link_encounters(
#'   ed_clean, inpatient_clean,
#'   merge_fields = c(TriageNotes = "concat")
#' )
#' }
#'
#' @seealso [dedupe()] for deduplication prior to linking;
#'   [filter_care_setting()] for care setting filtering;
#'   [assign_treating_geography()] for geography attribution.
#' @export
link_encounters <- function(ed_data,
                            inpatient_admission_data,
                            facility_col = NULL,
                            visit_col = Visit_ID,
                            fallback_visit_col = NULL,
                            merge_fields = c(
                              CCDD = "union_ccdd",
                              CCDDParsed = "union_ccdd",
                              CCDDCategory_flat = "union_delimited",
                              C_Death = "prefer_yes",
                              Discharge_Disposition = "prefer_admission",
                              DispositionCategory = "prefer_admission"
                            ),
                            merge_delimiter = ";",
                            return_format = c("collapsed", "long"),
                            clean_names = TRUE,
                            verbose = TRUE) {

  check_data_frame(ed_data)
  check_flag(clean_names)
  check_flag(verbose)
  check_string(merge_delimiter)

  # facility_col defaults to NULL (rather than a fixed column) so the
  # printed signature/Usage line doesn't misrepresent the smart default
  # below as a plain HospitalName default ----
  facility_col_sym     <- capture_col_sym(rlang::enquo(facility_col))
  facility_col_missing <- is.null(facility_col_sym)

  check_inpatient_admission_data(
    inpatient_admission_data,
    is_missing = missing(inpatient_admission_data)
  )

  return_format <- rlang::arg_match(return_format)

  check_merge_fields(merge_fields)

  names(merge_fields) <- janitor::make_clean_names(names(merge_fields))

  # Normalize ed_data and resolve the key columns ----
  original_names <- names(ed_data)
  ed_data        <- clean_names_safe(ed_data)
  name_map       <- c(
    input_name_map(original_names, names(ed_data)),
    input_name_map(
      names(inpatient_admission_data),
      names(clean_names_safe(inpatient_admission_data))
    )
  )
  facility_col <- resolve_facility_col(
    ed_data, facility_col_sym, facility_col_missing
  )
  visit_col    <- resolve_col(ed_data, rlang::ensym(visit_col))

  fac_col_str   <- rlang::as_string(facility_col)
  visit_col_str <- rlang::as_string(visit_col)

  # fallback_visit_col defaults to NULL: a row missing visit_col is only
  # ever matched via a secondary identifier when the caller explicitly
  # names one; see Details' "Split episodes with a missing visit_col on
  # both sides" section ----
  fallback_col_sym <- capture_col_sym(
    rlang::enquo(fallback_visit_col), "fallback_visit_col"
  )
  has_fallback     <- !is.null(fallback_col_sym)
  fallback_col_str <- if (has_fallback) {
    resolve_col_str(ed_data, fallback_col_sym)
  } else {
    NULL
  }

  # The linking keys (facility, visit, and fallback identifiers) have no
  # numeric meaning; hold them as text in both pulls so a number in one and
  # text in the other still link ----
  text_cols <- c(fac_col_str, visit_col_str, fallback_col_str)
  ed_data   <- as_text_cols(ed_data, text_cols)

  # One row per patient class: from C_Patient_Class_List when present,
  # otherwise from the HasBeen_ flags ----
  class_source <- detect_patient_class_source(ed_data)

  if (class_source$use_pc_list) {
    ed_long <- long_from_patient_class_list(
      ed_data, class_source$pc_list_str, class_source$use_mdt,
      class_source$mdt_col_str, verbose
    )
  } else {
    exclude_from_pivot <- validate_has_been_flags(ed_data, verbose)
    ed_long <- long_from_has_been_flags(ed_data, exclude_from_pivot, verbose)
  }

  # Supplement with direct admits, then order and group into episodes ----
  ed_long <- bind_direct_admits(
    ed_long, inpatient_admission_data, verbose,
    key_cols = c(fac_col_str, visit_col_str, fallback_col_str),
    text_cols = text_cols
  )
  ed_long <- add_class_time(ed_long)

  episode_id_vec <- build_episode_ids(
    ed_long, fac_col_str, visit_col_str, has_fallback, fallback_col_str,
    verbose
  )
  result <- add_episode_metadata(ed_long, episode_id_vec)

  if (return_format == "collapsed") {
    result <- collapse_episodes(result, merge_fields, merge_delimiter)
  }

  finish_names(result, clean_names, name_map)
}
