#' Patient class timing helpers for link_encounters()
#'
#' Internal helpers that decide the chronological order of an episode's
#' patient classes and which row represents the episode.
#'
#' @details
#' `parse_mdt_updates()` parses ESSENCE's `C_Patient_Class_MDT_Updates`
#' encoding: pipe-delimited `{position};timestamp;` segments, one per patient
#' class, where `position` is the 1-based character position in the
#' corresponding `C_Patient_Class_List` value (for example
#' `{1};2026-06-19 16:00:06.000;|{2};2026-06-19 17:55:10.000;` for
#' `C_Patient_Class_List = "EI"`). It returns a character vector of length
#' `n_classes` holding the timestamp string at each position, `NA` where no
#' segment matches that position (for example a class that was never
#' explicitly updated) or the segment does not match this encoding.
#'
#' `safe_as_posixct()` parses timestamps for chronological ordering. A single
#' malformed or non-standard value must not abort the whole vectorized parse
#' (`as.POSIXct()` throws rather than warns when a string matches none of its
#' `tryFormats`), so values that cannot be parsed become `NA` and ordering
#' degrades gracefully to the next tier for just that row instead of failing
#' [link_encounters()] entirely. It recognizes space- and `T`-separated
#' ISO 8601-style timestamps (with or without a trailing `Z`) and US-style
#' `month/day/year` timestamps, trying each format against the whole vector at
#' once and keeping the first format that parses each element.
#'
#' `compute_patient_class_sequence()` orders an episode's distinct patient
#' classes by the earliest `class_time` each class occurs at, for example
#' `"Direct Admit->ED"` when the direct-admit record's timestamp precedes the
#' ED record's. It falls back to alphabetical order (matching legacy behavior)
#' when no usable timestamp exists for the episode at all; classes with no
#' timestamp sort after timed classes when some but not all classes in the
#' episode have one.
#'
#' `pick_primary_row_index()` returns the index of the ED row in an episode
#' if one exists, else `1` (the first row in original order). This matches
#' the precedence [link_encounters()] has always given the ED row via
#' `.index_encounter`.
#'
#' @param mdt_str A single `C_Patient_Class_MDT_Updates` string (may be `NA`
#'   or empty).
#' @param n_classes Integer. The number of patient classes in the
#'   corresponding `C_Patient_Class_List` value.
#' @param x A vector of timestamps, as character or anything coercible with
#'   `as.character()`. A `POSIXct` vector is returned unchanged.
#' @param patient_class Character vector of one episode's patient classes, one
#'   per row (so a class can repeat).
#' @param class_time `POSIXct` vector, parallel to `patient_class`, of the time
#'   each row's class occurred (`NA` where unknown).
#' @param patient_classes Character vector of an episode's patient classes,
#'   one per row.
#'
#' @return `parse_mdt_updates()` returns a character vector of length
#'   `n_classes`. `safe_as_posixct()` returns a `POSIXct` vector the length of
#'   `x`. `compute_patient_class_sequence()` returns a single string, or
#'   `NA_character_` when there is no non-missing patient class.
#'   `pick_primary_row_index()` returns a single integer.
#' @keywords internal
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

#' @rdname parse_mdt_updates
safe_as_posixct <- function(x) {
  if (inherits(x, "POSIXct")) return(x)

  formats <- c(
    "%Y-%m-%dT%H:%M:%OS", "%Y-%m-%d %H:%M:%OS",
    "%Y-%m-%dT%H:%M",     "%Y-%m-%d %H:%M",
    "%Y-%m-%d",
    "%m/%d/%Y %H:%M:%OS", "%m/%d/%Y %H:%M", "%m/%d/%Y"
  )

  x_clean <- sub("Z$", "", trimws(as.character(x)))
  result  <- as.POSIXct(rep(NA_character_, length(x_clean)))

  # Vectorized per-format fill: try each format against the whole vector at
  # once (one C-level strptime() pass) and only keep trying remaining
  # unparsed elements with the next format. This gives the same per-element
  # "first matching format wins" result as the old row-by-row loop, without
  # a separate R function call + tryCatch per row; the row-by-row version
  # is what made this the dominant cost on a full year of data ----
  remaining <- !is.na(x_clean) & x_clean != ""
  for (fmt in formats) {
    if (!any(remaining)) break
    parsed <- suppressWarnings(as.POSIXct(x_clean[remaining], format = fmt))
    ok <- !is.na(parsed)
    if (any(ok)) {
      idx            <- which(remaining)[ok]
      result[idx]    <- parsed[ok]
      remaining[idx] <- FALSE
    }
  }

  result
}

#' @rdname parse_mdt_updates
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

#' @rdname parse_mdt_updates
pick_primary_row_index <- function(patient_classes) {
  ed_idx <- which(patient_classes == "ED")
  if (length(ed_idx) > 0L) return(ed_idx[1])
  1L
}

#' Merge strategies for link_encounters()
#'
#' Internal helpers that reconcile one field across the rows of a multi-row
#' care episode when [link_encounters()] collapses it to a single row.
#'
#' @details
#' `merge_strategies` is the set of strategy names accepted by
#' `merge_fields`. It is validated up front by `check_merge_fields()` and
#' listed again by `merge_field_value()`'s fallback error, so the two can
#' never drift apart. `merge_field_value()` dispatches one field's values to
#' the strategy named in `merge_fields`.
#'
#' The strategies are:
#' \describe{
#'   \item{`concat`}{Free-text merge: starting from `primary_value`, appends
#'     each other non-empty value not already a substring of the accumulated
#'     result.}
#'   \item{`union_delimited`}{Splits each value on `delimiter`, trims
#'     whitespace, and returns the union of unique parts (in order of first
#'     appearance) rejoined with the same delimiter.}
#'   \item{`union_ccdd`}{For the ESSENCE `CCDD`/`CCDDParsed` structure
#'     `"CC-values|DD-values"`: `|` separates CC from DD (fixed by the ESSENCE
#'     convention, not user-configurable) and `delimiter` separates values
#'     within each half. Unions unique values within each half separately,
#'     then rejoins.}
#'   \item{`prefer_yes`}{If any value is affirmative (case-insensitive
#'     `"Yes"`, or `1`/`"1"` for 0/1-coded flag columns), the merged value is
#'     that affirmative value; otherwise `primary_value`.}
#'   \item{`prefer_admission`}{The value from whichever row's
#'     `patient_class` indicates an admission (Inpatient, Direct Admit, or
#'     Admitted), if that row has a non-missing value; otherwise
#'     `primary_value`.}
#' }
#'
#' `check_merge_fields()` aborts, attributed to [link_encounters()], unless
#' `merge_fields` is a named character vector (possibly empty) whose values
#' are all valid strategies.
#'
#' @param merge_fields A named character vector mapping column names to
#'   strategy names.
#' @param call The environment errors are attributed to; see
#'   [resolve_col()].
#' @param values The field's values across the episode's rows.
#' @param patient_classes The episode's patient classes, one per row.
#' @param primary_value The value on the episode's primary row (see
#'   `pick_primary_row_index()`), used as the fallback.
#' @param strategy A single strategy name from `merge_strategies`.
#' @param delimiter The delimiter separating individual values within a
#'   field.
#'
#' @return `merge_strategies` is a character vector. `check_merge_fields()`
#'   returns `merge_fields` invisibly, or aborts. The `merge_*()` functions
#'   and `merge_field_value()` return a single merged value.
#' @format `merge_strategies` is a character vector of the valid strategy
#'   names.
#' @keywords internal
merge_strategies <- c(
  "concat", "union_delimited", "union_ccdd", "prefer_yes", "prefer_admission"
)

#' @rdname merge_strategies
check_merge_fields <- function(merge_fields, call = rlang::caller_env()) {
  nms <- names(merge_fields)
  is_named_chr <- is.character(merge_fields) &&
    (length(merge_fields) == 0L ||
       (!is.null(nms) && !anyNA(nms) && all(nzchar(nms))))
  if (!is_named_chr) {
    rlang::abort(
      c(
        paste0(
          "`merge_fields` must be a named character vector mapping column ",
          "names to merge strategies."
        ),
        "i" = paste0(
          "For example: `c(CCDD = \"union_ccdd\", ",
          "C_Death = \"prefer_yes\")`."
        )
      ),
      call = call
    )
  }

  invalid_strategies <- setdiff(merge_fields, merge_strategies)
  if (length(invalid_strategies) > 0L) {
    rlang::abort(
      paste0(
        "Invalid merge strategy/strategies in `merge_fields`: ",
        paste(unique(invalid_strategies), collapse = ", "), ". ",
        "Valid strategies: ", paste(merge_strategies, collapse = ", "), "."
      ),
      call = call
    )
  }
  invisible(merge_fields)
}

#' @rdname merge_strategies
merge_field_value <- function(values, patient_classes, primary_value,
                              strategy, delimiter) {
  switch(
    strategy,
    concat           = merge_concat(values, primary_value),
    union_delimited  = merge_union_delimited(values, delimiter),
    union_ccdd       = merge_union_ccdd(values, delimiter),
    prefer_yes       = merge_prefer_yes(values, primary_value),
    prefer_admission = merge_prefer_admission(
      values, patient_classes, primary_value
    ),
    rlang::abort(
      paste0(
        "Unknown merge strategy `", strategy, "` in `merge_fields`. ",
        "Valid strategies: ", paste(merge_strategies, collapse = ", "), "."
      )
    )
  )
}

#' @rdname merge_strategies
merge_concat <- function(values, primary_value) {
  values <- values[!is.na(values) & values != ""]
  if (length(values) == 0L) return(primary_value)

  base <- if (!is.na(primary_value) && nzchar(primary_value)) {
    primary_value
  } else {
    values[1]
  }

  for (v in values) {
    if (!identical(v, base) && !grepl(v, base, fixed = TRUE)) {
      base <- paste0(base, "; ", v)
    }
  }

  base
}

#' @rdname merge_strategies
merge_union_delimited <- function(values, delimiter) {
  values <- values[!is.na(values) & values != ""]
  if (length(values) == 0L) return(NA_character_)

  parts <- unlist(strsplit(values, delimiter, fixed = TRUE))
  parts <- trimws(parts)
  parts <- parts[nzchar(parts)]

  paste(unique(parts), collapse = delimiter)
}

#' @rdname merge_strategies
merge_union_ccdd <- function(values, delimiter) {
  values <- values[!is.na(values) & values != ""]
  if (length(values) == 0L) return(NA_character_)

  # Vectorized across all of this group's values at once, rather than
  # calling strsplit()/trimws() per value in a loop; trimws() compiles a
  # perl regex on every call, and this function runs once per multi-row
  # episode, so per-value looping is the difference between O(episodes)
  # and O(episodes x rows-per-episode) regex compiles on a full year of
  # data ----
  halves    <- strsplit(values, "|", fixed = TRUE)
  half_at   <- function(i) {
    vapply(halves, function(h) if (length(h) >= i) h[i] else "", character(1L))
  }
  cc_halves <- half_at(1L)
  dd_halves <- half_at(2L)

  cc_halves <- cc_halves[nzchar(cc_halves)]
  dd_halves <- dd_halves[nzchar(dd_halves)]

  split_parts <- function(x) {
    if (length(x) == 0L) return(character(0))
    trimws(unlist(strsplit(x, delimiter, fixed = TRUE), use.names = FALSE))
  }
  cc_parts <- split_parts(cc_halves)
  dd_parts <- split_parts(dd_halves)

  cc_parts <- unique(cc_parts[nzchar(cc_parts)])
  dd_parts <- unique(dd_parts[nzchar(dd_parts)])

  paste0(
    paste(cc_parts, collapse = delimiter), "|",
    paste(dd_parts, collapse = delimiter)
  )
}

#' @rdname merge_strategies
merge_prefer_yes <- function(values, primary_value) {
  values_clean  <- values[!is.na(values)]
  is_affirmative <- tolower(as.character(values_clean)) %in% c("yes", "1")
  if (any(is_affirmative)) return(values_clean[is_affirmative][1])
  primary_value
}

#' @rdname merge_strategies
merge_prefer_admission <- function(values, patient_classes, primary_value) {
  admission_classes <- c("Inpatient", "Direct Admit", "Admitted")
  admission_idx <- which(
    patient_classes %in% admission_classes & !is.na(values) & values != ""
  )
  if (length(admission_idx) > 0L) return(values[admission_idx[1]])
  primary_value
}
