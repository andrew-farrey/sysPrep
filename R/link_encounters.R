
# link_encounters() ----
#' Link ED and inpatient admission records into unified care episodes
#'
#' Links ED and direct-admit inpatient records sharing the same
#' `facility_col` x `visit_col` key into a single composite row per true
#' care episode, and reconciles their field values so information present
#' on only one of the source rows is not silently discarded. Corrects two
#' related but distinct duplication mechanisms: the encounter-continuity
#' data quality issue where a patient's ED discharge and immediate
#' direct-admit readmission are reported as separate records sharing the
#' same `Visit_ID` at the same facility, and true direct admissions that
#' are structurally invisible to a `HasBeenE = 1` query.
#'
#' @details
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
#' `facility_col` x `visit_col` key -- one correctly showing `HasBeenE = 1`,
#' one showing `HasBeenAdmitted = 1` and `HasBeenE = 0` -- that otherwise
#' look unrelated. The ED record's fields (e.g. `Discharge_Disposition`,
#' `CCDD`, `C_Death`) reflect only what was known at ED discharge, not the
#' outcome of the encounter that actually continued. Counting both records
#' separately double-counts a single real-world event. This is a data
#' quality artifact, not a distinct clinical pathway.
#'
#' **The invisibility gap.** A patient admitted directly to an inpatient
#' unit without ED triage -- via physician referral, a pre-arranged
#' admission, or similar -- genuinely has `HasBeenAdmitted = 1` and
#' `HasBeenE = 0` with no preceding ED record to find. This visit never
#' appears in a `HasBeenE = 1` query regardless of which syndrome
#' definition or date range is used. This is a real clinical pathway, not
#' a data quality problem -- but a `HasBeenE = 1`-only pull will always
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
#' the episode's rows -- e.g., if the ED row has `HasBeenAdmitted = 0` and the
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
#'   \item{`"prefer_yes"`}{If any row's value is affirmative -- case-insensitive
#'     `"Yes"`, or `1`/`"1"` for 0/1-coded flag columns -- the merged value is
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
#' instead -- one row per patient-class per episode, with no merge applied.
#' Useful for inspecting the raw linkage mechanism directly.
#'
#' ## Single-pull vs. two-pull approach
#'
#' **Single-pull** (`inpatient_admission_data = NULL`, the default): Uses
#' `C_Patient_Class_List` or `HasBeen_` flags within the ED pull to detect
#' visits that transitioned to inpatient care.
#'
#' **Two-pull** (`inpatient_admission_data` supplied): Supplements the ED pull
#' with a separately queried inpatient pull (`HasBeenAdmitted = 1`). Rows with
#' `HasBeenE = 1` are automatically removed from the inpatient pull to prevent
#' duplicate rows for the same underlying record. This is the recommended
#' approach when direct admission volume is material to the surveillance
#' question, and is required to detect the continuity-break artifact
#' when the direct-admit record is entirely absent from the ED pull (i.e.
#' `HasBeenE = 0` on that record, so it would never appear in a `HasBeenE = 1`
#' query).
#'
#' **Do not row-bind `ed_data` and `inpatient_admission_data` into one data
#' frame and call [dedupe()] on the combined result instead of using the
#' two-pull approach above.** `dedupe()`'s `keep` strategies are not aware
#' of the distinction between an ED record and its corresponding
#' direct-admit record -- both just look like two rows sharing a
#' `facility_col` x `visit_col` key -- and will discard one of them based
#' on `order_by` rather than merging them, silently and unpredictably
#' reducing either the ED or the direct-admit count depending on which
#' record's `Arrived_Date_Time` happens to win. Always deduplicate each
#' pull separately, then pass both to `link_encounters()`.
#'
#' ## Linking key and its limitation
#'
#' Records are linked by `facility_col` \eqn{\times} `visit_col`
#' (`HospitalName` \eqn{\times} `Visit_ID` by default).
#'
#' **Limitation:** if a facility's HL7 feed assigns a genuinely different
#' `Visit_ID` to the inpatient leg of a care episode, `link_encounters()`
#' cannot detect the relationship -- the two records will appear as separate
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
#' `C_Patient_Class_List` -- they are easier to interpret and are the
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
#' ESSENCE API pull fields. Splitting each character maps to the HL7/PHIN
#' standard:
#'
#' | Code | Patient class |
#' |------|--------------|
#' | `E`  | ED |
#' | `I`  | Inpatient |
#' | `D`  | Direct Admit |
#' | `V`  | Observation |
#' | `O`  | Outpatient |
#' | `B`  | Obstetrics |
#' | `P`  | Preadmit |
#' | `R`  | Recurring |
#'
#' ## Chronological ordering of `.patient_class_sequence`
#' `.patient_class_sequence` reflects the actual order encounters occurred
#' in, not alphabetical order -- e.g. `"Direct Admit->ED"` when the
#' direct-admit record's timestamp precedes the ED record's, which is the
#' reverse of what typically indicates the continuity-break artifact
#' (an ED visit that transitions into a direct-admit readmission, not a
#' direct admit that precedes an ED visit). Ordering uses the first
#' available field, per row, in this priority:
#' \enumerate{
#'   \item **`C_Patient_Class_MDT_Updates`** (requires `C_Patient_Class_List`).
#'     A concatenated list of timestamps positionally aligned with
#'     `C_Patient_Class_List`, giving the exact moment each class was
#'     assigned -- the only field that can order two classes assigned
#'     within a single record (e.g. `"EI"`). Rows where the two lists'
#'     lengths disagree fall back to the next tier.
#'   \item **`C_Visit_Date_Time`**. Applied per record -- all classes
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
#' ## Episode metadata columns
#' Present regardless of `return_format`. In collapsed output, these
#' describe the episode the collapsed row was built from (e.g.
#' `.episode_n_rows = 2` on a collapsed row means two original records were
#' merged into it).
#' \describe{
#'   \item{`.episode_id`}{A character key combining `facility_col` and
#'     `visit_col`, shared across all rows belonging to the same care episode.}
#'   \item{`.patient_class_sequence`}{All patient classes for the episode
#'     in chronological order and collapsed, e.g., `"Direct Admit->ED"`
#'     when the direct admit occurred first -- see Details.}
#'   \item{`.episode_n_rows`}{Number of original rows the episode was built
#'     from before merging.}
#'   \item{`.index_encounter`}{In long format, `TRUE` on the row that
#'     survives filtering to one row per episode. In collapsed format, always
#'     `TRUE` (retained for schema consistency with long format).}
#' }
#'
#' @param ed_data A deduplicated data frame of ED visits queried with
#'   `HasBeenE = 1`. Requires `HasBeenE` and at least one of
#'   `HasBeenAdmitted`/`HasBeenI` (the standard ESSENCE pull fields), or
#'   `C_Patient_Class_List` for more granular and informative output.
#' @param inpatient_admission_data Optional. A deduplicated data frame of
#'   inpatient visits queried with `HasBeenAdmitted = 1` or `HasBeenI = 1`.
#'   Rows with `HasBeenE = 1` are automatically removed to prevent duplicate
#'   rows for the same underlying record. If `NULL` (default), only visits
#'   present in `ed_data` are linked.
#' @param facility_col <[`tidy-select`][dplyr::dplyr_tidy_select]> Unquoted
#'   column name identifying the facility. Defaults to `HospitalName`.
#'   Accepts both raw ESSENCE names and post-[janitor::clean_names()]
#'   equivalents.
#' @param visit_col <[`tidy-select`][dplyr::dplyr_tidy_select]> Unquoted
#'   column name identifying the visit. Defaults to `Visit_ID`. Accepts
#'   both raw ESSENCE names and post-[janitor::clean_names()] equivalents.
#' @param merge_fields Named character vector mapping column names (raw
#'   ESSENCE names or post-[janitor::clean_names()] equivalents) to a merge
#'   strategy: one of `"concat"`, `"union_delimited"`, `"union_ccdd"`,
#'   `"prefer_yes"`, or `"prefer_admission"`. Only used when
#'   `return_format = "collapsed"`. Defaults to a curated set of ESSENCE
#'   fields known to carry information only visible in the direct-admit
#'   record -- see Details. Extend or override for other fields as needed.
#' @param merge_delimiter Character string. Delimiter used by the
#'   `"union_delimited"` and `"union_ccdd"` strategies. Defaults to `";"`,
#'   matching ESSENCE's convention for `CCDDCategory_flat` and the
#'   within-half structure of `CCDD`/`CCDDParsed`.
#' @param return_format Character string. One of `"collapsed"` (default) or
#'   `"long"`. See Details.
#' @param clean_names Logical. If `TRUE` (default), applies
#'   [janitor::clean_names()] to standardize column names to snake_case
#'   on output.
#' @param verbose Logical. If `FALSE`, suppresses informational messages
#'   (`rlang::inform()`); warnings and errors are always shown regardless.
#'
#' @return When `return_format = "collapsed"` (default), a data frame with
#'   one row per true care episode, `HasBeen_` flags reconciled via max, and
#'   `merge_fields` columns reconciled per their assigned strategy. When
#'   `return_format = "long"`, a data frame in long format with one row per
#'   visit per patient class, unmerged. Both include episode metadata
#'   columns `.episode_id`, `.patient_class_sequence`, `.episode_n_rows`,
#'   and `.index_encounter`.
#'
#' @examples
#' ed_clean <- essence_raw |>
#'   dedupe(order_by = Arrived_Date_Time, keep = "last") |>
#'   filter_care_setting(
#'     fix_facility_type_vector = c("Hillside FSED", "Downtown Emergency Services")
#'   )
#'
#' # Default: one row per true encounter, merged
#' episodes <- link_encounters(ed_clean)
#' nrow(episodes)
#'
#' # Inspect the distribution of care pathways
#' episodes |>
#'   dplyr::count(.patient_class_sequence, sort = TRUE)
#'
#' # Long format: inspect the raw linkage mechanism directly
#' episodes_long <- link_encounters(ed_clean, return_format = "long")
#'
#' \dontrun{
#' # Two-pull linkage with a custom merge strategy for a site-specific field
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
                            inpatient_admission_data = NULL,
                            facility_col             = HospitalName,
                            visit_col                = Visit_ID,
                            merge_fields             = c(
                              CCDD                   = "union_ccdd",
                              CCDDParsed             = "union_ccdd",
                              CCDDCategory_flat      = "union_delimited",
                              C_Death                = "prefer_yes",
                              Discharge_Disposition  = "prefer_admission",
                              DispositionCategory    = "prefer_admission"
                            ),
                            merge_delimiter          = ";",
                            return_format            = c("collapsed", "long"),
                            clean_names              = TRUE,
                            verbose                  = TRUE) {

  return_format <- match.arg(return_format)

  valid_strategies   <- c("concat", "union_delimited", "union_ccdd", "prefer_yes", "prefer_admission")
  invalid_strategies <- setdiff(merge_fields, valid_strategies)
  if (length(invalid_strategies) > 0L) {
    rlang::abort(
      paste0(
        "Invalid merge strategy/strategies in `merge_fields`: ",
        paste(unique(invalid_strategies), collapse = ", "), ". ",
        "Valid strategies: ", paste(valid_strategies, collapse = ", "), "."
      )
    )
  }

  names(merge_fields) <- janitor::make_clean_names(names(merge_fields))

  # Normalize ed_data ----
  ed_data      <- clean_names_safe(ed_data)
  facility_col <- resolve_col(ed_data, rlang::ensym(facility_col))
  visit_col    <- resolve_col(ed_data, rlang::ensym(visit_col))

  fac_col_str   <- rlang::as_string(facility_col)
  visit_col_str <- rlang::as_string(visit_col)

  # Detect C_Patient_Class_List (optional, more granular derivation) ----
  pc_list_col <- resolve_col_optional(ed_data, rlang::sym("C_Patient_Class_List"))
  use_pc_list <- !is.null(pc_list_col)
  pc_list_str <- if (use_pc_list) rlang::as_string(pc_list_col) else NA_character_

  # Detect C_Patient_Class_MDT_Updates (optional, per-class timestamps used
  # to chronologically order `.patient_class_sequence` -- see below) ----
  mdt_col     <- resolve_col_optional(ed_data, rlang::sym("C_Patient_Class_MDT_Updates"))
  use_mdt     <- use_pc_list && !is.null(mdt_col)
  mdt_col_str <- if (use_mdt) rlang::as_string(mdt_col) else NA_character_

  # When C_Patient_Class_List is absent, use the standard HasBeen_ flags ----
  if (!use_pc_list) {

    has_been_e_col        <- resolve_col_optional(ed_data, rlang::sym("HasBeenE"))
    has_been_admitted_col <- resolve_col_optional(ed_data, rlang::sym("HasBeenAdmitted"))
    has_been_i_col        <- resolve_col_optional(ed_data, rlang::sym("HasBeenI"))
    has_been_o_col        <- resolve_col_optional(ed_data, rlang::sym("HasBeenO"))

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
    if (has_been_admitted && has_been_i) {
      inform_if(
        verbose,
        paste0(
          "Both `HasBeenAdmitted` and `HasBeenI` found in `ed_data`. ",
          "`HasBeenAdmitted` will be used preferentially as it is discharge-",
          "disposition aware and inclusive of ED-to-inpatient escalations."
        )
      )
      ed_data <- dplyr::select(
        ed_data,
        -dplyr::all_of(rlang::as_string(has_been_i_col))
      )
    }

    # Warn about outpatient visits ----
    if (!is.null(has_been_o_col)) {
      has_been_o_str <- rlang::as_string(has_been_o_col)
      if (any(ed_data[[has_been_o_str]] == 1L, na.rm = TRUE)) {
        rlang::warn(
          paste0(
            "Outpatient visits detected (`HasBeenO = 1`). These will be labeled ",
            "'Outpatient' in `patient_class` and retained. For overdose or injury ",
            "burden estimation, consider filtering to `HasBeenE = 1` and/or ",
            "`HasBeenAdmitted = 1` at the ESSENCE query level to reduce data volume."
          )
        )
      }
    }
  }

  # Build long-format visit rows ----
  if (use_pc_list) {

    inform_if(
      verbose,
      paste0(
        "Using `C_Patient_Class_List` for patient class derivation -- more ",
        "granular than the `HasBeen_` flags. Accepts code form (e.g. \"EI\") ",
        "and label form (e.g. \"Emergency,Inpatient\") -- independent of ",
        "HasBeen_ flag availability."
      )
    )

    n_missing_pc_list <- sum(
      is.na(ed_data[[pc_list_str]]) | ed_data[[pc_list_str]] == ""
    )
    if (n_missing_pc_list > 0L) {
      rlang::warn(
        paste0(
          n_missing_pc_list, " row(s) had missing or empty ",
          "`C_Patient_Class_List` values. These rows are retained with ",
          "`patient_class = NA` rather than dropped -- review before relying ",
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
    # 1-based character position in C_Patient_Class_List -- e.g.
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
            n_unparsed, " row(s) had a non-empty `C_Patient_Class_MDT_Updates` ",
            "value that could not be parsed in the expected ",
            "`{position};timestamp;` format -- chronological ordering for ",
            "these rows falls back to `C_Visit_Date_Time` or `Date`+`Time` ",
            "if available."
          )
        )
      }
    } else {
      mdt_split_list <- lapply(pc_split_list, function(pc) rep(NA_character_, length(pc)))
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
        "Using `HasBeen_` flags for patient class derivation. For more ",
        "granular and informative output, add `C_Patient_Class_List` to ",
        "your ESSENCE API pull fields."
      )
    )

    # Pivot HasBeen_ flags to long format ----
    ed_long <- ed_data |>
      tidyr::pivot_longer(
        dplyr::starts_with("has_been_"),
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
      dplyr::select(-present)

  }

  # Supplement with direct admits from inpatient_admission_data ----
  if (!is.null(inpatient_admission_data)) {

    inpatient_admission_data <- clean_names_safe(inpatient_admission_data)

    # Remove HasBeenE = 1 rows -- already in ed_data ----
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
            "`inpatient_admission_data` -- these visits are already present ",
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

  if (!any(!is.na(ed_long$.class_time))) {
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
  result <- ed_long |>
    dplyr::mutate(
      .episode_id = paste(
        .data[[fac_col_str]],
        .data[[visit_col_str]],
        sep = "_"
      )
    ) |>
    dplyr::group_by(.data[[fac_col_str]], .data[[visit_col_str]]) |>
    dplyr::mutate(
      .patient_class_sequence = compute_patient_class_sequence(
        patient_class, .class_time
      ),
      .episode_n_rows  = dplyr::n(),
      .index_encounter = patient_class == "ED" |
        (patient_class != "ED" & dplyr::n() == 1L)
    ) |>
    dplyr::ungroup() |>
    dplyr::select(-.class_time)

  if (return_format == "collapsed") {
    result <- result |>
      dplyr::group_by(.data[[".episode_id"]]) |>
      dplyr::group_modify(~ collapse_episode(.x, merge_fields, merge_delimiter)) |>
      dplyr::ungroup()
  }

  if (clean_names) clean_names_safe(result) else result
}

# parse_mdt_updates() ----
# Parses ESSENCE's C_Patient_Class_MDT_Updates encoding: pipe-delimited
# "{position};timestamp;" segments, one per patient class, where `position`
# is the 1-based character position in the corresponding
# C_Patient_Class_List value (e.g. "{1};2026-06-19 16:00:06.000;
# |{2};2026-06-19 17:55:10.000;" for C_Patient_Class_List = "EI"). Returns a
# character vector of length `n_classes` giving the timestamp string at each
# position, NA where no segment matches that position (e.g. a class that was
# never explicitly updated) or the segment doesn't match this encoding.
parse_mdt_updates <- function(mdt_str, n_classes) {
  out <- rep(NA_character_, n_classes)
  if (is.na(mdt_str) || mdt_str == "") return(out)

  segments <- strsplit(mdt_str, "|", fixed = TRUE)[[1]]
  for (seg in segments) {
    seg <- trimws(seg)
    if (!nzchar(seg)) next
    m <- regmatches(seg, regexec("^\\{(\\d+)\\}\\s*;\\s*([^;]+)", seg))[[1]]
    if (length(m) == 3L) {
      idx <- suppressWarnings(as.integer(m[2]))
      if (!is.na(idx) && idx >= 1L && idx <= n_classes) {
        out[idx] <- trimws(m[3])
      }
    }
  }
  out
}

# safe_as_posixct() ----
# Parses a character vector of timestamps for chronological ordering
# purposes. A single malformed or non-standard-format value must not abort
# the whole vectorized parse (as.POSIXct() throws rather than warns when a
# string matches none of its tryFormats) -- unparseable values become NA
# instead, so ordering degrades gracefully to the next tier for just that
# row rather than erroring out link_encounters() entirely. Recognizes
# space- and "T"-separated ISO 8601-style timestamps (with or without a
# trailing "Z") in addition to base R's defaults.
safe_as_posixct <- function(x) {
  if (inherits(x, "POSIXct")) return(x)

  formats <- c(
    "%Y-%m-%dT%H:%M:%OS", "%Y-%m-%d %H:%M:%OS",
    "%Y-%m-%dT%H:%M",     "%Y-%m-%d %H:%M",
    "%Y-%m-%d",
    "%m/%d/%Y %H:%M:%OS", "%m/%d/%Y"
  )

  do.call(c, lapply(as.character(x), function(v) {
    if (is.na(v) || v == "") return(as.POSIXct(NA_character_))
    v_clean <- sub("Z$", "", trimws(v))
    parsed  <- tryCatch(
      as.POSIXct(v_clean, tryFormats = formats),
      error = function(e) as.POSIXct(NA_character_)
    )
    if (is.na(parsed)) as.POSIXct(NA_character_) else parsed
  }))
}

# compute_patient_class_sequence() ----
# Orders an episode's distinct patient classes by the earliest .class_time
# each class occurs at, e.g. "Direct Admit->ED" when the direct-admit
# record's timestamp precedes the ED record's. Falls back to alphabetical
# order (matching legacy behavior) when no usable timestamp exists for the
# episode at all; classes with no timestamp sort after timed classes when
# some but not all classes in the episode have one.
compute_patient_class_sequence <- function(patient_class, class_time) {
  classes <- unique(patient_class)
  classes <- classes[!is.na(classes)]
  if (length(classes) == 0L) return(NA_character_)

  min_time <- do.call(c, lapply(classes, function(cl) {
    times <- class_time[!is.na(patient_class) & patient_class == cl]
    if (all(is.na(times))) return(as.POSIXct(NA))
    min(times, na.rm = TRUE)
  }))

  if (all(is.na(min_time))) {
    return(paste(sort(classes), collapse = "->"))
  }

  ord <- order(min_time, classes, na.last = TRUE)
  paste(classes[ord], collapse = "->")
}

# merge_concat() ----
# Free-text merge: starting from primary_value, appends each other non-empty
# value not already a substring of the accumulated result.
merge_concat <- function(values, primary_value) {
  values <- values[!is.na(values) & values != ""]
  if (length(values) == 0L) return(primary_value)

  base <- if (!is.na(primary_value) && nzchar(primary_value)) primary_value else values[1]

  for (v in values) {
    if (!identical(v, base) && !grepl(v, base, fixed = TRUE)) {
      base <- paste0(base, "; ", v)
    }
  }

  base
}

# merge_union_delimited() ----
# Splits each value on `delimiter`, trims whitespace, and returns the union
# of unique parts (preserving order of first appearance) rejoined with the
# same delimiter.
merge_union_delimited <- function(values, delimiter) {
  values <- values[!is.na(values) & values != ""]
  if (length(values) == 0L) return(NA_character_)

  parts <- unlist(strsplit(values, delimiter, fixed = TRUE))
  parts <- trimws(parts)
  parts <- parts[nzchar(parts)]

  paste(unique(parts), collapse = delimiter)
}

# merge_union_ccdd() ----
# ESSENCE CCDD/CCDDParsed structure: "CC-values|DD-values", with `|`
# separating CC from DD (fixed by the ESSENCE convention, not
# user-configurable) and `delimiter` separating individual values within
# each half. Unions unique values within each half separately, then rejoins.
merge_union_ccdd <- function(values, delimiter) {
  values <- values[!is.na(values) & values != ""]
  if (length(values) == 0L) return(NA_character_)

  cc_parts <- character(0)
  dd_parts <- character(0)

  for (v in values) {
    halves  <- strsplit(v, "|", fixed = TRUE)[[1]]
    cc_half <- if (length(halves) >= 1L) halves[1] else ""
    dd_half <- if (length(halves) >= 2L) halves[2] else ""

    if (nzchar(cc_half)) {
      cc_parts <- c(cc_parts, trimws(strsplit(cc_half, delimiter, fixed = TRUE)[[1]]))
    }
    if (nzchar(dd_half)) {
      dd_parts <- c(dd_parts, trimws(strsplit(dd_half, delimiter, fixed = TRUE)[[1]]))
    }
  }

  cc_parts <- unique(cc_parts[nzchar(cc_parts)])
  dd_parts <- unique(dd_parts[nzchar(dd_parts)])

  paste0(paste(cc_parts, collapse = delimiter), "|", paste(dd_parts, collapse = delimiter))
}

# merge_prefer_yes() ----
# If any value is affirmative -- case-insensitive "Yes", or 1/"1" for
# 0/1-coded flag columns -- the merged value is that affirmative value.
# Otherwise falls back to primary_value.
merge_prefer_yes <- function(values, primary_value) {
  values_clean  <- values[!is.na(values)]
  is_affirmative <- tolower(as.character(values_clean)) %in% c("yes", "1")
  if (any(is_affirmative)) return(values_clean[is_affirmative][1])
  primary_value
}

# merge_prefer_admission() ----
# Returns the value from whichever row's patient_class indicates an
# admission (Inpatient/Direct Admit/Admitted), if such a row has a
# non-missing value for this field. Otherwise falls back to primary_value.
merge_prefer_admission <- function(values, patient_classes, primary_value) {
  admission_classes <- c("Inpatient", "Direct Admit", "Admitted")
  admission_idx <- which(
    patient_classes %in% admission_classes & !is.na(values) & values != ""
  )
  if (length(admission_idx) > 0L) return(values[admission_idx[1]])
  primary_value
}

# merge_field_value() ----
# Dispatches a single field's values to the strategy named in merge_fields.
merge_field_value <- function(values, patient_classes, primary_value, strategy, delimiter) {
  switch(
    strategy,
    concat           = merge_concat(values, primary_value),
    union_delimited  = merge_union_delimited(values, delimiter),
    union_ccdd       = merge_union_ccdd(values, delimiter),
    prefer_yes       = merge_prefer_yes(values, primary_value),
    prefer_admission = merge_prefer_admission(values, patient_classes, primary_value),
    rlang::abort(
      paste0(
        "Unknown merge strategy '", strategy, "' in `merge_fields`. ",
        "Valid strategies: concat, union_delimited, union_ccdd, prefer_yes, ",
        "prefer_admission."
      )
    )
  )
}

# pick_primary_row_index() ----
# Returns the index of the ED row in an episode if one exists, else 1
# (first row in original order). Matches the precedence link_encounters()
# has always given the ED row via .index_encounter.
pick_primary_row_index <- function(patient_classes) {
  ed_idx <- which(patient_classes == "ED")
  if (length(ed_idx) > 0L) return(ed_idx[1])
  1L
}

# collapse_episode() ----
# Collapses one episode's rows (all rows sharing a facility x Visit_ID) into
# a single composite row: has_been_* columns are reconciled via max(),
# columns named in merge_fields are reconciled via their assigned strategy,
# and every other column takes its value from the primary row.
collapse_episode <- function(episode_df, merge_fields, merge_delimiter) {
  primary_idx <- pick_primary_row_index(episode_df$patient_class)
  result_row  <- episode_df[primary_idx, ]

  has_been_cols <- grep("^has_been_", names(episode_df), value = TRUE)
  for (col in has_been_cols) {
    vals <- episode_df[[col]]
    if (!all(is.na(vals))) {
      result_row[[col]] <- max(vals, na.rm = TRUE)
    }
  }

  merge_cols <- intersect(names(merge_fields), names(episode_df))
  for (col in merge_cols) {
    result_row[[col]] <- merge_field_value(
      values          = episode_df[[col]],
      patient_classes = episode_df$patient_class,
      primary_value   = episode_df[[col]][primary_idx],
      strategy        = merge_fields[[col]],
      delimiter       = merge_delimiter
    )
  }

  result_row[[".index_encounter"]] <- TRUE

  result_row
}
