
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
#' Querying the inpatient pull with `HasBeenE = 0` added on purpose,
#' specifically to exclude anything already captured by the
#' `HasBeenE = 1` pull, looks like a safe way to avoid double-counting.
#' By the API's own field semantics it should be: `HasBeenE = 0` means no
#' ED encounter appears anywhere in that record's history. It isn't. Some
#' records that correctly show `HasBeenE = 0` were, clinically, discharged
#' from the ED and immediately readmitted; the ED encounter lives
#' entirely on a separate record already captured in the first pull, so
#' the exclusion filter never catches it. If you don't know this and want
#' to include inpatient admissions in your burden counts, summing the two
#' pulls double-counts that proportion of ED visits a second time. This is
#' the same problem [dedupe()] solves for retransmitted or split ESSENCE
#' rows: the duplicate here doesn't share a flag value that would mark
#' it as related. `link_encounters()` finds the relationship directly, by
#' checking for a matching ED record under the same `facility_col` x
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
#'     other row's non-empty value if it is not already a substring of the
#'     accumulated text (`"; "`-separated). Generic free text.}
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
#' falls back to alphabetical order for every episode. Within a single
#' episode, if only some classes have a usable timestamp, timed classes are
#' ordered first and untimed classes are appended last.
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
#' another row sharing the same `facility_col` and the same
#' `fallback_visit_col` value instead of treating it as unmatchable.
#' Rows with a non-missing `visit_col` are never affected, and a row
#' missing both `visit_col` and `fallback_visit_col` (or missing
#' `facility_col`) still gets its own unique episode, exactly as when
#' `fallback_visit_col` isn't supplied at all: the default `NULL`
#' preserves that original behavior precisely.
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
#'   \item{`.index_encounter`}{In long format, `TRUE` on the row that
#'     survives filtering to one row per episode. In collapsed format, always
#'     `TRUE` (retained for schema consistency with long format).}
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
#'   rows for the same underlying record. `link_encounters()` aborts if this
#'   is `NULL`; see Details.
#' @param facility_col Unquoted
#'   column name identifying the facility. When not supplied, prefers
#'   `Hospital`/`C_BioSense_Facility_ID` over `HospitalName` if present in
#'   `ed_data`; see `?dedupe`'s "Facility identifier preference" section
#'   for the full rationale. Accepts both raw ESSENCE names and
#'   post-[janitor::clean_names()] equivalents.
#' @param visit_col Unquoted
#'   column name identifying the visit. Defaults to `Visit_ID`. Accepts
#'   both raw ESSENCE names and post-[janitor::clean_names()] equivalents.
#' @param fallback_visit_col
#'   Optional. Unquoted column name of a secondary identifier (e.g.
#'   `C_BioSense_ID`) used to match two rows into one episode when
#'   `visit_col` is missing on the row being matched. Defaults to `NULL`,
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
  facility_col_quo     <- rlang::enquo(facility_col)
  facility_col_missing <- rlang::quo_is_null(facility_col_quo)
  facility_col_sym     <- if (facility_col_missing) {
    NULL
  } else {
    rlang::sym(rlang::as_name(facility_col_quo))
  }

  if (missing(inpatient_admission_data) ||
        is.null(inpatient_admission_data)) {
    rlang::abort(
      paste0(
        "`link_encounters()` requires `inpatient_admission_data`. Single-",
        "pull linkage (`ed_data` alone) is not supported: `ed_data` is ",
        "queried with `HasBeenE = 1`, so a genuine direct admission ",
        "(`HasBeenE = 0`) structurally never appears in it, and an ED-to-",
        "inpatient escalation already visible within `ed_data` (both ",
        "`HasBeenE` and `HasBeenAdmitted` set on one already-deduplicated ",
        "record) needs no linking; there is only ever one record to ",
        "link. Query a second ESSENCE pull filtered to `HasBeenAdmitted = ",
        "1` (or `HasBeenI = 1`), deduplicate it separately with `dedupe()`, ",
        "and pass it as `inpatient_admission_data`. See ",
        "`vignette(\"encounter-linkage\")`."
      )
    )
  }

  check_data_frame(inpatient_admission_data)

  return_format <- rlang::arg_match(return_format)

  check_merge_fields(merge_fields)

  names(merge_fields) <- janitor::make_clean_names(names(merge_fields))

  # Normalize ed_data ----
  ed_data      <- clean_names_safe(ed_data)
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
  fallback_visit_col_quo <- rlang::enquo(fallback_visit_col)
  has_fallback           <- !rlang::quo_is_null(fallback_visit_col_quo)
  fallback_col_str       <- if (has_fallback) {
    resolve_col_str(ed_data, rlang::sym(rlang::as_name(fallback_visit_col_quo)))
  } else {
    NULL
  }

  # Detect C_Patient_Class_List (optional, more granular derivation) ----
  pc_list_col <- resolve_col_optional(
    ed_data, rlang::sym("C_Patient_Class_List")
  )
  use_pc_list <- !is.null(pc_list_col)
  pc_list_str <- if (use_pc_list) {
    rlang::as_string(pc_list_col)
  } else {
    NA_character_
  }

  # Detect C_Patient_Class_MDT_Updates (optional, per-class timestamps used
  # to chronologically order `.patient_class_sequence`; see below) ----
  mdt_col     <- resolve_col_optional(
    ed_data, rlang::sym("C_Patient_Class_MDT_Updates")
  )
  use_mdt     <- use_pc_list && !is.null(mdt_col)
  mdt_col_str <- if (use_mdt) rlang::as_string(mdt_col) else NA_character_

  # When C_Patient_Class_List is absent, use the standard HasBeen_ flags ----
  if (!use_pc_list) {

    has_been_e_col <- resolve_col_optional(ed_data, rlang::sym("HasBeenE"))
    has_been_admitted_col <- resolve_col_optional(
      ed_data, rlang::sym("HasBeenAdmitted")
    )
    has_been_i_col <- resolve_col_optional(ed_data, rlang::sym("HasBeenI"))
    has_been_o_col <- resolve_col_optional(ed_data, rlang::sym("HasBeenO"))

    has_been_e        <- !is.null(has_been_e_col)
    has_been_admitted <- !is.null(has_been_admitted_col)
    has_been_i        <- !is.null(has_been_i_col)

    if (!has_been_e) {
      rlang::abort(
        paste0(
          "`ed_data` must contain `HasBeenE` or `C_Patient_Class_List` as a ",
          "data field. Include `HasBeenE` in your ESSENCE API pull fields, ",
          "or add `C_Patient_Class_List` for more granular and informative ",
          "output."
        )
      )
    }

    if (!has_been_admitted && !has_been_i) {
      rlang::abort(
        paste0(
          "`ed_data` must contain `HasBeenAdmitted` or `HasBeenI` to ",
          "identify admission escalations. Include one in your ESSENCE API ",
          "pull fields, or add `C_Patient_Class_List` for more granular and ",
          "informative output."
        )
      )
    }

    # Prefer HasBeenAdmitted over HasBeenI when both present ----
    # `HasBeenI` is excluded from the pivot below (so it doesn't contribute
    # a second, redundant "Admitted" row for the same admission) but its
    # column and true 0/1 values are left in `ed_data` untouched; an
    # earlier version of this code dropped the `HasBeenI` column outright,
    # which discarded its real values for every `ed_data` row and surfaced
    # as `has_been_i = NA` on all of them after `bind_rows()` with
    # `inpatient_admission_data` (whose own `HasBeenI` column, untouched,
    # supplied the only non-NA values in the output) ----
    exclude_from_pivot <- character(0)
    if (has_been_admitted && has_been_i) {
      inform_if(
        verbose,
        paste0(
          "Both `HasBeenAdmitted` and `HasBeenI` found in `ed_data`. ",
          "`HasBeenAdmitted` will be used preferentially as it is discharge-",
          "disposition aware and inclusive of ED-to-inpatient escalations."
        )
      )
      exclude_from_pivot <- rlang::as_string(has_been_i_col)
    }

    # Inform about outpatient/observation visits ----
    # A `HasBeenO = 1` co-occurring flag is ordinary ESSENCE data, not a
    # sign of anything wrong: a patient can genuinely be seen in
    # outpatient/observation care and also be triaged in the ED or
    # admitted on the same record. In `link_encounters()`'s intended usage
    # (an ED pull and an inpatient/direct-admit pull), every episode also
    # has an ED or Admitted component, so the "Outpatient" pivot row it
    # contributes is never the primary row and never appears as the
    # collapsed output's `patient_class` value; it only surfaces in
    # `.patient_class_sequence` and in `return_format = "long"` output ----
    if (!is.null(has_been_o_col)) {
      has_been_o_str <- rlang::as_string(has_been_o_col)
      if (any(ed_data[[has_been_o_str]] == 1L, na.rm = TRUE)) {
        inform_if(
          verbose,
          paste0(
            "Outpatient/observation visits detected (`HasBeenO = 1`). These ",
            "contribute an 'Outpatient' entry to `.patient_class_sequence` ",
            "but will not appear as the collapsed output's `patient_class` ",
            "value for an episode that also includes an ED or inpatient-",
            "admission record, which is the typical case for two-pull input."
          )
        )
      }
    }
  }

  # Build long-format visit rows ----
  if (use_pc_list) {

    inform_if(
      verbose,
      "Using `C_Patient_Class_List` to derive complete encounters of care."
    )

    n_missing_pc_list <- sum(
      is.na(ed_data[[pc_list_str]]) | ed_data[[pc_list_str]] == ""
    )
    if (n_missing_pc_list > 0L) {
      rlang::warn(
        paste0(
          n_missing_pc_list, " row(s) had missing or empty ",
          "`C_Patient_Class_List` values. These rows are retained with ",
          "`patient_class = NA` rather than dropped; review before relying ",
          "on `.index_encounter`-based counts for these visits."
        )
      )
    }

    # Split C_Patient_Class_List into one element per patient class ----
    pc_split_list <- lapply(as.character(ed_data[[pc_list_str]]), function(x) {
      if (is.na(x) || x == "") return(NA_character_)
      # Label form has a comma or lowercase letters; code form is all caps
      if (grepl(",", x, fixed = TRUE) || grepl("[a-z]", x)) {
        trimws(strsplit(x, ",", fixed = TRUE)[[1]])
      } else {
        strsplit(x, "", fixed = TRUE)[[1]]
      }
    })

    # Pair C_Patient_Class_MDT_Updates timestamps with the C_Patient_Class_List
    # split above. ESSENCE encodes this as pipe-delimited "{position};
    # timestamp;" segments, one per patient class, where `position` is the
    # 1-based character position in C_Patient_Class_List, e.g.
    # "{1};2026-06-19 16:00:06.000;|{2};2026-06-19 17:55:10.000;" for
    # C_Patient_Class_List = "EI" gives "E" (position 1) a timestamp of
    # 16:00:06 and "I" (position 2) a timestamp of 17:55:10. Positions with
    # no matching segment (or a segment that doesn't match this encoding)
    # fall back to C_Visit_Date_Time/Date+Time below instead ----
    if (use_mdt) {
      mdt_raw_list   <- as.character(ed_data[[mdt_col_str]])
      n_classes_vec  <- vapply(pc_split_list, length, integer(1))
      mdt_split_list <- Map(parse_mdt_updates, mdt_raw_list, n_classes_vec)

      n_unparsed <- sum(mapply(
        function(mdt, parsed) !is.na(mdt) && mdt != "" && all(is.na(parsed)),
        mdt_raw_list, mdt_split_list
      ))
      if (n_unparsed > 0L) {
        rlang::warn(
          paste0(
            n_unparsed, " row(s) had a non-empty ",
            "`C_Patient_Class_MDT_Updates` value that could not be parsed in ",
            "the expected ",
            "`{position};timestamp;` format; chronological ordering for ",
            "these rows falls back to `C_Visit_Date_Time` or `Date`+`Time` ",
            "if available."
          )
        )
      }
    } else {
      mdt_split_list <- lapply(
        pc_split_list,
        function(pc) rep(NA_character_, length(pc))
      )
    }

    ed_long <- ed_data |>
      dplyr::mutate(pc_split = pc_split_list, mdt_split = mdt_split_list) |>
      tidyr::unnest(cols = c("pc_split", "mdt_split")) |>
      dplyr::mutate(
        patient_class = dplyr::case_when(
          # Short code form (single uppercase letters)
          pc_split == "E"            ~ "ED",
          pc_split == "I"            ~ "Inpatient",
          pc_split == "D"            ~ "Direct Admit",
          pc_split == "V"            ~ "Observation",
          pc_split == "O"            ~ "Outpatient",
          pc_split == "B"            ~ "Obstetrics",
          pc_split == "P"            ~ "Preadmit",
          pc_split == "R"            ~ "Recurring",
          # Full label form (comma-separated ESSENCE class names)
          pc_split == "Emergency"    ~ "ED",
          pc_split == "Inpatient"    ~ "Inpatient",
          pc_split == "Direct Admit" ~ "Direct Admit",
          pc_split == "Observation"  ~ "Observation",
          pc_split == "Outpatient"   ~ "Outpatient",
          pc_split == "Obstetrics"   ~ "Obstetrics",
          pc_split == "Preadmit"     ~ "Preadmit",
          pc_split == "Recurring"    ~ "Recurring",
          TRUE                       ~ pc_split
        ),
        .class_time = safe_as_posixct(mdt_split)
      ) |>
      dplyr::select(-pc_split, -mdt_split)

  } else {

    inform_if(
      verbose,
      paste0(
        "Using `HasBeen_` flags to derive complete encounters of care ",
        "since `C_Patient_Class_List` is not present in `ed_data`."
      )
    )

    # Pivot HasBeen_ flags to long format: preserve a copy of each
    # pivoted column under a "_orig" name first, since pivot_longer()
    # consumes (removes) the columns it pivots on. Every synthetic row
    # produced from one original record describes that same record, so
    # each should retain that record's true has_been_* values regardless
    # of which flag triggered its own creation, e.g. an "Admitted->ED"
    # escalation splits one row (HasBeenE = 1, HasBeenAdmitted = 1) into
    # two synthetic rows ("ED" and "Admitted"), and both must still show
    # has_been_e = 1 and has_been_admitted = 1, not just the flag that
    # produced them. Without this, has_been_* end up NA (or, worse,
    # silently wrong after cross-pull max() reconciliation) for any row
    # that never came from inpatient_admission_data directly. `HasBeenI`
    # (when excluded above to prefer `HasBeenAdmitted`) is deliberately
    # left out of the pivot entirely rather than dropped from the data --
    # since it's never pivoted, it's never consumed, and its true 0/1
    # value survives on every row with no `_orig` handling needed ----
    has_been_cols <- grep("^has_been_", names(ed_data), value = TRUE)
    pivot_cols      <- setdiff(has_been_cols, exclude_from_pivot)
    pivot_orig_cols <- paste0(pivot_cols, "_orig")

    ed_long <- ed_data |>
      dplyr::mutate(
        dplyr::across(
          dplyr::all_of(pivot_cols),
          ~ .x,
          .names = "{.col}_orig"
        )
      ) |>
      tidyr::pivot_longer(
        dplyr::all_of(pivot_cols),
        names_to  = "patient_class",
        values_to = "present"
      ) |>
      dplyr::filter(present == 1L) |>
      dplyr::mutate(
        patient_class = dplyr::recode_values(
          patient_class,
          from    = c("has_been_e", "has_been_admitted",
                      "has_been_i", "has_been_o"),
          to      = c("ED",         "Admitted",
                      "Admitted",   "Outpatient"),
          default = "Other"
        )
      ) |>
      dplyr::select(-present) |>
      dplyr::rename_with(
        ~ sub("_orig$", "", .x),
        dplyr::all_of(pivot_orig_cols)
      )

  }

  # Supplement with direct admits from inpatient_admission_data ----
  if (!is.null(inpatient_admission_data)) {

    inpatient_admission_data <- clean_names_safe(inpatient_admission_data)

    # Remove HasBeenE = 1 rows: already in ed_data ----
    ip_hbe_col <- resolve_col_optional(
      inpatient_admission_data,
      rlang::sym("HasBeenE")
    )
    if (!is.null(ip_hbe_col)) {
      ip_hbe_str <- rlang::as_string(ip_hbe_col)
      n_ed_rows  <- sum(
        inpatient_admission_data[[ip_hbe_str]] == 1L,
        na.rm = TRUE
      )
      if (n_ed_rows > 0L) {
        inform_if(
          verbose,
          paste0(
            n_ed_rows, " row(s) with `HasBeenE = 1` removed from ",
            "`inpatient_admission_data`; these visits are already present ",
            "in `ed_data` and would produce double-counted episodes. ",
            "This is expected behavior when `HasBeenAdmitted = 1` is used ",
            "as the inpatient pull filter."
          )
        )
        inpatient_admission_data <- dplyr::filter(
          inpatient_admission_data,
          .data[[ip_hbe_str]] == 0L
        )
      }
    }

    # Tag as Direct Admit and bind ----
    inpatient_admission_data <- dplyr::mutate(
      inpatient_admission_data,
      patient_class = "Direct Admit"
    )

    ed_long <- dplyr::bind_rows(ed_long, inpatient_admission_data)
  }

  # Fall back to C_Visit_Date_Time, then Date+Time, for any row whose
  # .class_time wasn't already set from C_Patient_Class_MDT_Updates above --
  # this also covers the HasBeen_-flag derivation path (which has no
  # C_Patient_Class_MDT_Updates equivalent) and inpatient_admission_data
  # rows in the two-pull path ----
  if (!(".class_time" %in% names(ed_long))) {
    ed_long$.class_time <- as.POSIXct(rep(NA_character_, nrow(ed_long)))
  }

  has_vdt  <- "c_visit_date_time" %in% names(ed_long)
  has_date <- "date" %in% names(ed_long)
  has_time <- "time" %in% names(ed_long)

  if (has_vdt) {
    ed_long <- dplyr::mutate(
      ed_long,
      .class_time = dplyr::if_else(
        is.na(.class_time),
        safe_as_posixct(c_visit_date_time),
        .class_time
      )
    )
  } else if (has_date && has_time) {
    ed_long <- dplyr::mutate(
      ed_long,
      .class_time = dplyr::if_else(
        is.na(.class_time),
        safe_as_posixct(paste(date, time)),
        .class_time
      )
    )
  }

  if (all(is.na(ed_long$.class_time))) {
    rlang::warn(
      paste0(
        "No `C_Patient_Class_MDT_Updates`, `C_Visit_Date_Time`, or ",
        "`Date`+`Time` fields were found (or could be parsed) for ",
        "chronological ordering. `.patient_class_sequence` reflects ",
        "alphabetical order rather than the actual order encounters ",
        "occurred. Include one of these fields in your ESSENCE pull for ",
        "accurate encounter sequencing."
      )
    )
  }

  # Build episode metadata ----
  # A missing facility_col or visit_col value means that row's true
  # identity is unknown, not confirmed to match every other row with the
  # same missing value -- grouping by the raw columns directly (whether
  # via group_by() or `.by =`) follows dplyr's SQL-style GROUP BY
  # convention instead, where every NA is treated as equal to every other
  # NA, silently merging unrelated visits into one episode. Disambiguating
  # only the NA-key rows' `.episode_id` with na_safe_group_id() keeps the
  # normal "{facility}_{visit}" format for every other row unchanged; see
  # ?dedupe's "Facility identifier preference" section for the same
  # category of silent-merge bug. `fallback_visit_col` is the one
  # deliberate exception: a row missing visit_col can still be confirmed
  # to match another row via a secondary identifier (e.g. C_BioSense_ID,
  # observed in real production data to be assigned identically to a real
  # episode's ED and direct-admit rows even when Visit_ID is missing on
  # both); see Details ----
  key_has_na <- is.na(ed_long[[fac_col_str]]) | is.na(ed_long[[visit_col_str]])

  uses_fallback <- if (has_fallback) {
    is.na(ed_long[[visit_col_str]]) &
      !is.na(ed_long[[fac_col_str]]) &
      !is.na(ed_long[[fallback_col_str]])
  } else {
    rep(FALSE, nrow(ed_long))
  }

  still_na_key <- key_has_na & !uses_fallback

  inform_na_key_rows(
    sum(still_na_key), fac_col_str, visit_col_str,
    function(...) inform_if(verbose, ...)
  )
  if (any(uses_fallback)) {
    inform_if(
      verbose,
      paste0(
        sum(uses_fallback), " row(s) with a missing `", visit_col_str,
        "` value matched another row via `", fallback_col_str,
        "` and were treated as one episode."
      )
    )
  }

  group_id <- na_safe_group_id(ed_long, c(fac_col_str, visit_col_str))

  # Built as plain vectors (not inside a dplyr verb's tidy-eval) so the
  # fallback branch's lookup of fallback_col_str is never attempted at all
  # when it is NULL (no fallback_visit_col supplied). A case_when() here
  # would evaluate every right-hand side eagerly, and indexing ed_long with
  # a NULL column name would error even though uses_fallback is all-FALSE
  # in that case ----
  normal_episode_id  <- paste(
    ed_long[[fac_col_str]], ed_long[[visit_col_str]], sep = "_"
  )
  na_key_episode_id  <- paste(
    ed_long[[fac_col_str]], ed_long[[visit_col_str]], group_id, sep = "_"
  )
  fallback_episode_id <- if (has_fallback) {
    paste(ed_long[[fac_col_str]], ed_long[[fallback_col_str]], "fb", sep = "_")
  } else {
    rep(NA_character_, nrow(ed_long))
  }
  # Precedence: fallback match, then unmatchable NA-key singleton, then the
  # normal key; which() treats an NA flag as FALSE ----
  episode_id_vec <- normal_episode_id
  na_key_idx     <- which(still_na_key)
  fallback_idx   <- which(uses_fallback)
  episode_id_vec[na_key_idx]   <- na_key_episode_id[na_key_idx]
  episode_id_vec[fallback_idx] <- fallback_episode_id[fallback_idx]

  # `.by =` groups only for the duration of this one mutate() call, without
  # materializing a separate grouped-tibble object the way group_by() +
  # ungroup() does; cheaper to keep alive across a year of rows ----
  result <- ed_long |>
    dplyr::mutate(.episode_id = episode_id_vec) |>
    dplyr::mutate(
      .patient_class_sequence = compute_patient_class_sequence(
        patient_class, .class_time
      ),
      .episode_n_rows  = dplyr::n(),
      .index_encounter = patient_class == "ED" |
        (patient_class != "ED" & dplyr::n() == 1L),
      .by = .episode_id
    ) |>
    dplyr::select(-.class_time)

  # Collapse each episode to one row ----
  # Deliberately NOT a per-episode helper applied through
  # dplyr::group_modify(): that approach slices out a full-width single-row
  # data.frame per episode and binds every one of them back together at the
  # end, which is the actual source of the memory/time blowup on a full
  # year of data (millions of tiny per-group data.frame objects, all of
  # them live simultaneously until the final bind completes). The block
  # below reconciles only the columns that actually change (has_been_*
  # flags and merge_fields) as plain vectorized, per-episode-grouped
  # column operations, then does a single row filter to keep one row per
  # episode, no per-group data.frame construction, no giant final bind ----
  if (return_format == "collapsed") {
    has_been_cols <- grep("^has_been_", names(result), value = TRUE)
    merge_cols    <- intersect(names(merge_fields), names(result))

    # Episodes with exactly one row need no reconciliation; the "merged"
    # result is trivially that row's own value. Isolating them skips
    # merge_field_value() (and the has_been_ max()) entirely for what is,
    # in real ESSENCE data, the large majority of visits (only episodes
    # with an actual ED-to-inpatient transition or direct-admit linkage
    # have >1 row). Only that smaller multi-row subset needs the grouped
    # reconciliation below ----
    single_row <- dplyr::filter(result, .data[[".episode_n_rows"]] == 1L)
    multi_row  <- dplyr::filter(result, .data[[".episode_n_rows"]] > 1L)

    if (nrow(multi_row) > 0L) {
      multi_row <- multi_row |>
        dplyr::mutate(
          .primary_idx = pick_primary_row_index(patient_class),
          dplyr::across(
            dplyr::all_of(has_been_cols),
            ~ if (all(is.na(.x))) .x else max(.x, na.rm = TRUE)
          ),
          dplyr::across(
            dplyr::all_of(merge_cols),
            ~ merge_field_value(
              values          = .x,
              patient_classes = patient_class,
              primary_value   = .x[.primary_idx[1L]],
              strategy        = merge_fields[[dplyr::cur_column()]],
              delimiter       = merge_delimiter
            )
          ),
          .row_in_group = dplyr::row_number(),
          .by = .episode_id
        ) |>
        dplyr::filter(.data[[".row_in_group"]] == .data[[".primary_idx"]]) |>
        dplyr::select(-dplyr::all_of(c(".primary_idx", ".row_in_group")))
    }

    result <- dplyr::bind_rows(single_row, multi_row) |>
      dplyr::mutate(.index_encounter = TRUE) |>
      dplyr::arrange(.data[[".episode_id"]])
  }

  if (clean_names) clean_names_safe(result) else result
}
