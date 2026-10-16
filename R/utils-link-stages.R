#' Stages of link_encounters()
#'
#' Internal helpers that [link_encounters()] runs in order. Each takes the
#' data produced by the previous stage and returns the next, so the exported
#' function reads as a short pipeline and each stage can be understood and
#' tested on its own.
#'
#' @details
#' The stages, in the order `link_encounters()` calls them:
#' \enumerate{
#'   \item `check_inpatient_admission_data()` aborts unless a data frame was
#'     supplied for `inpatient_admission_data` (there is no single-pull mode).
#'   \item `detect_patient_class_source()` finds the optional
#'     `C_Patient_Class_List` and `C_Patient_Class_MDT_Updates` columns, which
#'     decide how patient classes are derived.
#'   \item `validate_has_been_flags()` (only without `C_Patient_Class_List`)
#'     checks that the `HasBeen_` flags needed to derive patient classes are
#'     present and reports which admission flag will be used.
#'   \item `long_from_patient_class_list()` or `long_from_has_been_flags()`
#'     reshapes `ed_data` to one row per patient class.
#'     `long_from_patient_class_list()` uses `split_patient_class_list()` to
#'     split each `C_Patient_Class_List` value into its classes and
#'     `pair_mdt_timestamps()` to attach `C_Patient_Class_MDT_Updates`
#'     timestamps to them.
#'   \item `bind_direct_admits()` tags `inpatient_admission_data` as
#'     `"Direct Admit"` and appends it.
#'   \item `add_class_time()` fills the `.class_time` ordering column.
#'   \item `build_episode_ids()` builds the `.episode_id` for every row.
#'   \item `add_episode_metadata()` adds `.episode_id`,
#'     `.patient_class_sequence`, `.episode_n_rows`, and `.index_encounter`.
#'   \item `collapse_episodes()` reduces each episode to one row
#'     (`return_format = "collapsed"` only).
#' }
#'
#' `long_from_has_been_flags()` pivots the `HasBeen_` flags to long format.
#' It preserves a copy of each pivoted column under an `_orig` name first,
#' since `pivot_longer()` consumes the columns it pivots on. Every synthetic
#' row produced from one original record describes that same record, so each
#' should keep that record's true `has_been_*` values regardless of which
#' flag triggered its own creation: an "Admitted->ED" escalation splits one
#' row (`HasBeenE = 1`, `HasBeenAdmitted = 1`) into two synthetic rows (`ED`
#' and `Admitted`), and both must still show `has_been_e = 1` and
#' `has_been_admitted = 1`. Without this, `has_been_*` end up `NA` (or,
#' worse, silently wrong after cross-pull `max()` reconciliation) for any row
#' that never came from `inpatient_admission_data` directly. `HasBeenI`,
#' when excluded to prefer `HasBeenAdmitted`, is deliberately left out of the
#' pivot rather than dropped from the data, so its true 0/1 value survives on
#' every row.
#'
#' `build_episode_ids()` treats a missing `facility_col` or `visit_col` value
#' as an unknown identity, not as a match for every other missing value (see
#' `na_safe_group_id()`), so only NA-key rows get a unique
#' `.episode_id` and every other row keeps the normal
#' `"{facility}_{visit}"` format. `fallback_visit_col` is the one deliberate
#' exception: a row missing `visit_col` can still be confirmed to match
#' another row via a secondary identifier. The three candidate id strings are
#' built as plain vectors, not inside a dplyr verb, so the fallback lookup is
#' never attempted when no `fallback_visit_col` was supplied.
#'
#' `collapse_episodes()` deliberately avoids a per-episode helper applied
#' through `dplyr::group_modify()`: that slices out a full-width single-row
#' data frame per episode and binds all of them back together, which is the
#' source of the memory and time blowup on a full year of data. It reconciles
#' only the columns that change (`has_been_*` flags and `merge_fields`) as
#' vectorized, per-episode-grouped column operations on the multi-row
#' episodes, then keeps one row per episode.
#'
#' @param inpatient_admission_data A data frame of inpatient admissions. For
#'   `bind_direct_admits()`, the raw (not yet normalized) data frame.
#' @param is_missing Logical. Whether `inpatient_admission_data` was omitted
#'   from the call.
#' @param call The environment errors are attributed to; see
#'   [resolve_col()].
#' @param ed_data The normalized ED data frame ([clean_names_safe()] already
#'   applied).
#' @param verbose Logical. Whether to emit informational messages.
#' @param pc_list_str Name of the `C_Patient_Class_List` column.
#' @param pc_list A vector of `C_Patient_Class_List` values.
#' @param pc_split_list The list returned by `split_patient_class_list()`:
#'   one character vector of patient classes per row of `ed_data`.
#' @param use_mdt Logical. Whether `C_Patient_Class_MDT_Updates` is usable.
#' @param mdt_col_str Name of the `C_Patient_Class_MDT_Updates` column, or
#'   `NA_character_`.
#' @param exclude_from_pivot Character vector of `HasBeen_` columns to leave
#'   out of the pivot.
#' @param ed_long The long-format data frame (one row per patient class)
#'   built so far.
#' @param fac_col_str,visit_col_str Names of the facility and visit columns
#'   in `ed_long`.
#' @param has_fallback Logical. Whether `fallback_visit_col` was supplied.
#' @param fallback_col_str Name of the `fallback_visit_col` column, or `NULL`.
#' @param episode_id_vec Character vector of `.episode_id` values, one per
#'   row of `ed_long`.
#' @param result The long-format data frame with episode metadata.
#' @param merge_fields Named character vector of merge strategies, with
#'   snake_case names.
#' @param merge_delimiter Delimiter used by the delimited merge strategies.
#'
#' @return `check_inpatient_admission_data()` returns its input invisibly or
#'   aborts. `detect_patient_class_source()` returns a list with `use_pc_list`,
#'   `pc_list_str`, `use_mdt`, and `mdt_col_str`. `validate_has_been_flags()`
#'   returns the `HasBeen_` columns to exclude from the pivot. The remaining
#'   stages return the updated long-format data frame, except
#'   `build_episode_ids()`, which returns a character vector.
#' @keywords internal
check_inpatient_admission_data <- function(inpatient_admission_data,
                                           is_missing,
                                           call = rlang::caller_env()) {
  if (is_missing || is.null(inpatient_admission_data)) {
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
      ),
      call = call
    )
  }

  check_data_frame(inpatient_admission_data, call = call)
}

#' @rdname check_inpatient_admission_data
detect_patient_class_source <- function(ed_data) {
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
  # to chronologically order `.patient_class_sequence`) ----
  mdt_col     <- resolve_col_optional(
    ed_data, rlang::sym("C_Patient_Class_MDT_Updates")
  )
  use_mdt     <- use_pc_list && !is.null(mdt_col)
  mdt_col_str <- if (use_mdt) rlang::as_string(mdt_col) else NA_character_

  list(
    use_pc_list = use_pc_list,
    pc_list_str = pc_list_str,
    use_mdt     = use_mdt,
    mdt_col_str = mdt_col_str
  )
}

#' @rdname check_inpatient_admission_data
validate_has_been_flags <- function(ed_data, verbose,
                                    call = rlang::caller_env()) {
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
      ),
      call = call
    )
  }

  if (!has_been_admitted && !has_been_i) {
    rlang::abort(
      paste0(
        "`ed_data` must contain `HasBeenAdmitted` or `HasBeenI` to ",
        "identify admission escalations. Include one in your ESSENCE API ",
        "pull fields, or add `C_Patient_Class_List` for more granular and ",
        "informative output."
      ),
      call = call
    )
  }

  # Prefer HasBeenAdmitted over HasBeenI when both present ----
  # `HasBeenI` is excluded from the pivot (so it doesn't contribute a
  # second, redundant "Admitted" row for the same admission) but its column
  # and true 0/1 values are left in `ed_data` untouched; an earlier version
  # of this code dropped the `HasBeenI` column outright, which discarded its
  # real values for every `ed_data` row and surfaced as `has_been_i = NA` on
  # all of them after `bind_rows()` with `inpatient_admission_data` (whose
  # own `HasBeenI` column, untouched, supplied the only non-NA values in the
  # output) ----
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
  # A `HasBeenO = 1` co-occurring flag is ordinary ESSENCE data, not a sign
  # of anything wrong: a patient can genuinely be seen in
  # outpatient/observation care and also be triaged in the ED or admitted on
  # the same record. In `link_encounters()`'s intended usage (an ED pull and
  # an inpatient/direct-admit pull), every episode also has an ED or
  # Admitted component, so the "Outpatient" pivot row it contributes is
  # never the primary row and never appears as the collapsed output's
  # `patient_class` value; it only surfaces in `.patient_class_sequence` and
  # in `return_format = "long"` output ----
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

  exclude_from_pivot
}

#' @rdname check_inpatient_admission_data
split_patient_class_list <- function(pc_list) {
  lapply(as.character(pc_list), function(x) {
    if (is.na(x) || x == "") return(NA_character_)
    # Label form has a comma or lowercase letters; code form is all caps
    if (grepl(",", x, fixed = TRUE) || grepl("[a-z]", x)) {
      trimws(strsplit(x, ",", fixed = TRUE)[[1]])
    } else {
      strsplit(x, "", fixed = TRUE)[[1]]
    }
  })
}

#' @rdname check_inpatient_admission_data
pair_mdt_timestamps <- function(ed_data, pc_split_list, use_mdt,
                                mdt_col_str) {
  # Pair C_Patient_Class_MDT_Updates timestamps with the C_Patient_Class_List
  # split. ESSENCE encodes this as pipe-delimited "{position};timestamp;"
  # segments, one per patient class, where `position` is the 1-based
  # character position in C_Patient_Class_List, e.g.
  # "{1};2026-06-19 16:00:06.000;|{2};2026-06-19 17:55:10.000;" for
  # C_Patient_Class_List = "EI" gives "E" (position 1) a timestamp of
  # 16:00:06 and "I" (position 2) a timestamp of 17:55:10. Positions with
  # no matching segment (or a segment that doesn't match this encoding)
  # fall back to C_Visit_Date_Time/Date+Time in add_class_time() instead ----
  if (!use_mdt) {
    return(lapply(
      pc_split_list,
      function(pc) rep(NA_character_, length(pc))
    ))
  }

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

  mdt_split_list
}

#' @rdname check_inpatient_admission_data
long_from_patient_class_list <- function(ed_data, pc_list_str, use_mdt,
                                         mdt_col_str, verbose) {
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

  pc_split_list  <- split_patient_class_list(ed_data[[pc_list_str]])
  mdt_split_list <- pair_mdt_timestamps(
    ed_data, pc_split_list, use_mdt, mdt_col_str
  )

  ed_data |>
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
}

#' @rdname check_inpatient_admission_data
long_from_has_been_flags <- function(ed_data, exclude_from_pivot, verbose) {
  inform_if(
    verbose,
    paste0(
      "Using `HasBeen_` flags to derive complete encounters of care ",
      "since `C_Patient_Class_List` is not present in `ed_data`."
    )
  )

  has_been_cols   <- grep("^has_been_", names(ed_data), value = TRUE)
  pivot_cols      <- setdiff(has_been_cols, exclude_from_pivot)
  pivot_orig_cols <- paste0(pivot_cols, "_orig")

  ed_data |>
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

#' @rdname check_inpatient_admission_data
bind_direct_admits <- function(ed_long, inpatient_admission_data, verbose) {
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

  dplyr::bind_rows(ed_long, inpatient_admission_data)
}

#' @rdname check_inpatient_admission_data
add_class_time <- function(ed_long) {
  # Fall back to C_Visit_Date_Time, then Date+Time, for any row whose
  # .class_time wasn't already set from C_Patient_Class_MDT_Updates --
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

  ed_long
}

#' @rdname check_inpatient_admission_data
build_episode_ids <- function(ed_long, fac_col_str, visit_col_str,
                              has_fallback, fallback_col_str, verbose) {
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

  episode_id_vec
}

#' @rdname check_inpatient_admission_data
add_episode_metadata <- function(ed_long, episode_id_vec) {
  # `.by =` groups only for the duration of this one mutate() call, without
  # materializing a separate grouped-tibble object the way group_by() +
  # ungroup() does; cheaper to keep alive across a year of rows ----
  ed_long |>
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
}

#' @rdname check_inpatient_admission_data
collapse_episodes <- function(result, merge_fields, merge_delimiter) {
  has_been_cols <- grep("^has_been_", names(result), value = TRUE)
  merge_cols    <- intersect(names(merge_fields), names(result))

  # Episodes with exactly one row need no reconciliation; the "merged"
  # result is trivially that row's own value. Isolating them skips
  # merge_field_value() (and the has_been_ max()) entirely for what is, in
  # real ESSENCE data, the large majority of visits (only episodes with an
  # actual ED-to-inpatient transition or direct-admit linkage have >1 row).
  # Only that smaller multi-row subset needs the grouped reconciliation
  # below ----
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

  dplyr::bind_rows(single_row, multi_row) |>
    dplyr::mutate(.index_encounter = TRUE) |>
    dplyr::arrange(.data[[".episode_id"]])
}
