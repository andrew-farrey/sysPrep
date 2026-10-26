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
#' `episode_class_sequence()` orders each episode's distinct patient classes
#' by the earliest `class_time` each class occurs at, for example
#' `"Direct Admit->ED"` when the direct-admit record's timestamp precedes the
#' ED record's, and returns that string for every row of the episode. It falls
#' back to alphabetical order when no usable timestamp exists for the episode
#' at all; classes with no timestamp sort after timed classes when some but
#' not all classes in the episode have one. Classes with identical timestamps
#' (every class derived from one record shares that record's timestamp) also
#' fall back to alphabetical order. That is a tiebreak only: when the
#' timestamps are missing or equal the true order cannot be determined from
#' the data, so the alphabetical order carries no clinical meaning.
#'
#' `parse_mdt_segment()` parses one trimmed, non-empty `{position};timestamp;`
#' segment into its position and timestamp string, or returns `NULL` when the
#' segment does not match this encoding or its position is not between 1 and
#' `n_classes`.
#'
#' `pick_primary_row_index()` returns the index of the ED row in an episode
#' if one exists, else `1` (the first row in original order): the row whose
#' values represent the episode when it is collapsed. `episode_primary_row()`
#' marks that row in every episode of a long-format data frame, which is what
#' `.index_encounter` records, so a long-format count of index encounters
#' always equals the number of rows in the collapsed output.
#'
#' @param mdt_str A single `C_Patient_Class_MDT_Updates` string (may be `NA`
#'   or empty).
#' @param seg A single trimmed, non-empty `C_Patient_Class_MDT_Updates`
#'   segment.
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
#' @param episode Vector identifying the episode each row belongs to (for
#'   example `.episode_id`); rows with equal values are one episode.
#'
#' @return `parse_mdt_updates()` returns a character vector of length
#'   `n_classes`. `parse_mdt_segment()` returns a list with `idx` (an integer
#'   position) and `time` (a string), or `NULL`. `safe_as_posixct()` returns
#'   a `POSIXct` vector the length of `x`.
#'   `episode_class_sequence()` returns a character vector the length of
#'   `episode`: each row's episode sequence, `NA` for an episode with no
#'   non-missing patient class. `pick_primary_row_index()` returns a single
#'   integer. `episode_primary_row()` returns a logical vector the length of
#'   `episode`, `TRUE` on each episode's primary row.
#' @keywords internal
parse_mdt_updates <- function(mdt_str, n_classes) {
  out <- rep(NA_character_, n_classes)
  if (is.na(mdt_str) || mdt_str == "") return(out)

  segments <- trimws(strsplit(mdt_str, "|", fixed = TRUE)[[1]])
  for (seg in segments[nzchar(segments)]) {
    parsed <- parse_mdt_segment(seg, n_classes)
    if (!is.null(parsed)) out[parsed$idx] <- parsed$time
  }
  out
}

#' @rdname parse_mdt_updates
parse_mdt_segment <- function(seg, n_classes) {
  m <- regmatches(seg, regexec("^\\{(\\d+)\\}\\s*;\\s*([^;]+)", seg))[[1]]
  if (length(m) != 3L) return(NULL)

  idx <- suppressWarnings(as.integer(m[2]))
  if (is.na(idx) || idx < 1L || idx > n_classes) return(NULL)

  list(idx = idx, time = trimws(m[3]))
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
episode_class_sequence <- function(episode, patient_class, class_time) {
  ep   <- match(episode, unique(episode))
  keep <- !is.na(patient_class)
  if (!any(keep)) return(rep(NA_character_, length(episode)))

  # One row per episode x class, holding the earliest time that class occurs
  # at (NA when none of its rows has a time). Sorting by time with NAs last
  # and keeping the first row of each pair does this without a per-episode
  # R-level loop ----
  d <- data.frame(
    episode = ep[keep],
    class   = patient_class[keep],
    time    = class_time[keep],
    stringsAsFactors = FALSE
  )
  d <- d[order(d$episode, d$class, d$time, na.last = TRUE), ]
  d <- d[!duplicated(d[c("episode", "class")]), ]

  # Within an episode: timed classes in time order, then untimed ones, with
  # ties (and an episode with no timestamps at all) in alphabetical order ----
  d <- d[order(d$episode, is.na(d$time), d$time, d$class), ]

  # Every row of an episode shares its sequence, including a row whose own
  # class is NA; an episode with no class at all gets NA ----
  sequences <- vapply(
    split(d$class, d$episode), paste, character(1L), collapse = "->"
  )
  unname(sequences[match(as.character(ep), names(sequences))])
}

#' @rdname parse_mdt_updates
pick_primary_row_index <- function(patient_classes) {
  ed_idx <- which(patient_classes == "ED")
  if (length(ed_idx) > 0L) return(ed_idx[1])
  1L
}

#' @rdname parse_mdt_updates
episode_primary_row <- function(episode, patient_class) {
  ep        <- match(episode, unique(episode))
  first_row <- match(seq_len(max(ep, 0L)), ep)

  ed_rows  <- which(patient_class == "ED")
  first_ed <- ed_rows[!duplicated(ep[ed_rows])]
  first_row[ep[first_ed]] <- first_ed

  seq_along(ep) == first_row[ep]
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
#'     each other non-empty value unless the accumulated result already
#'     contains it as whole words or whole codes (`contains_whole()`). Text or
#'     a code that appears in one record but not the other is therefore
#'     kept, so extra detail or context is preserved: `"fall"` is not found in
#'     `"waterfall"`, the diagnosis code `"R10.9"` is not found in `"R10.90"`,
#'     and a SNOMED code is matched only as the whole number. Matching ignores
#'     case, punctuation, and spacing.}
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
#'   \item{`prefer_severity`}{For `DispositionCategory`: the most severe value
#'     across the episode's rows, whichever record carries it. `DECEASED`
#'     ranks above `TRANSFERRED` and `ADMIT` (equal), which rank above
#'     `DISCHARGED`, which ranks above `UNKNOWN` and a missing value
#'     (`disposition_severity()`, ignoring case). A value outside the five
#'     ESSENCE categories ranks with `DISCHARGED`. Among equally severe
#'     values the admission-class row's value is kept, then the primary
#'     row's. After the episode is merged, `mark_death_from_disposition()`
#'     sets `C_Death` to affirmative for any episode whose merged value is
#'     `DECEASED`.}
#'   \item{`follow_severity`}{The value from the same record whose
#'     `prefer_severity` field won (the first such field in `merge_fields`),
#'     so a companion field such as `Discharge_Disposition` always comes from
#'     the record that supplied `DispositionCategory`. If that record has no
#'     value for the field, or there is no `prefer_severity` field, the
#'     `prefer_admission` value is used instead.}
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
#' @param text,value Single strings: the text to search and the value to look
#'   for in it.
#' @param severity_row The position, within the episode's rows, of the record
#'   whose `prefer_severity` field won, or `NA` when none did.
#' @param x A vector of `DispositionCategory` values.
#' @param result The collapsed episodes, with cleaned column names.
#'
#' @return `merge_strategies` is a character vector. `check_merge_fields()`
#'   returns `merge_fields` invisibly, or aborts. The `merge_*()` functions
#'   and `merge_field_value()` return a single merged value.
#'   `contains_whole()` returns a single logical. `disposition_severity()`
#'   returns an integer rank per value (0 unknown or missing, 1 discharged,
#'   2 admit or transferred, 3 deceased). `severity_row_index()` returns an
#'   integer position or `NA`. `mark_death_from_disposition()` returns
#'   `result`.
#' @format `merge_strategies` is a character vector of the valid strategy
#'   names.
#' @keywords internal
merge_strategies <- c(
  "concat", "union_delimited", "union_ccdd", "prefer_yes", "prefer_admission",
  "prefer_severity", "follow_severity"
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
                              strategy, delimiter,
                              severity_row = NA_integer_) {
  switch(
    strategy,
    concat           = merge_concat(values, primary_value),
    union_delimited  = merge_union_delimited(values, delimiter),
    union_ccdd       = merge_union_ccdd(values, delimiter),
    prefer_yes       = merge_prefer_yes(values, primary_value),
    prefer_admission = merge_prefer_admission(
      values, patient_classes, primary_value
    ),
    prefer_severity  = merge_prefer_severity(
      values, patient_classes, primary_value
    ),
    follow_severity  = merge_follow_severity(
      values, patient_classes, primary_value, severity_row
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
    if (!identical(v, base) && !contains_whole(base, v)) {
      base <- paste0(base, "; ", v)
    }
  }

  base
}

#' @rdname merge_strategies
contains_whole <- function(text, value) {
  # A word or code is a run of letters and digits, with a "." kept inside it
  # when digits or letters follow (R10.9, 789.00), so a trailing full stop
  # does not become part of the last word ----
  tokenize <- function(x) {
    tolower(regmatches(x, gregexpr("[[:alnum:]]+([.][[:alnum:]]+)*", x))[[1]])
  }
  value_tokens <- tokenize(value)
  if (length(value_tokens) == 0L) return(grepl(value, text, fixed = TRUE))

  text_tokens <- tokenize(text)
  width       <- length(value_tokens)
  if (length(text_tokens) < width) return(FALSE)

  starts <- seq_len(length(text_tokens) - width + 1L)
  any(vapply(
    starts,
    function(i) all(text_tokens[i + seq_len(width) - 1L] == value_tokens),
    logical(1L)
  ))
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

#' @rdname merge_strategies
disposition_severity <- function(x) {
  # ESSENCE's DispositionCategory has five values: DECEASED, ADMIT,
  # TRANSFERRED, DISCHARGED, and UNKNOWN. Matching ignores case and
  # surrounding spaces. A value outside that list ranks with DISCHARGED, so
  # it never outranks a recognized death or onward care ----
  value <- toupper(trimws(as.character(x)))
  rank  <- rep(1L, length(value))
  rank[value %in% c("ADMIT", "TRANSFERRED")] <- 2L
  rank[value %in% "DECEASED"]                <- 3L
  rank[is.na(value) | value %in% c("", "UNKNOWN")] <- 0L
  rank
}

#' @rdname merge_strategies
severity_row_index <- function(values, patient_classes, primary_value) {
  severity <- disposition_severity(values)
  if (all(severity == 0L)) return(NA_integer_)

  # The most severe disposition wins whichever record carries it. Among
  # equally severe values the admission-class record's value is kept (as
  # `prefer_admission` does), then the primary row's, then the first ----
  top_idx <- which(severity == max(severity))
  admission_classes <- c("Inpatient", "Direct Admit", "Admitted")
  admitted_idx <- top_idx[patient_classes[top_idx] %in% admission_classes]
  if (length(admitted_idx) > 0L) return(admitted_idx[1L])
  if (!is.na(primary_value) && primary_value %in% values[top_idx]) {
    return(top_idx[match(primary_value, values[top_idx])])
  }
  top_idx[1L]
}

#' @rdname merge_strategies
merge_prefer_severity <- function(values, patient_classes, primary_value) {
  row <- severity_row_index(values, patient_classes, primary_value)
  if (is.na(row)) return(primary_value)
  values[row]
}

#' @rdname merge_strategies
merge_follow_severity <- function(values, patient_classes, primary_value,
                                  severity_row) {
  # A companion field (Discharge_Disposition) keeps the value from the very
  # record whose DispositionCategory won, so the two never disagree. When
  # that record has no value, the usual prefer_admission value is used
  # rather than dropping a known one ----
  if (!is.na(severity_row)) {
    value <- values[severity_row]
    if (!is.na(value) && nzchar(value)) return(value)
  }
  merge_prefer_admission(values, patient_classes, primary_value)
}

#' @rdname merge_strategies
mark_death_from_disposition <- function(result, merge_fields) {
  # C_Death is brought into line with the merged disposition: when any
  # record in the episode names a death, the episode's C_Death is affirmative
  # even if the record that carried the death left it unmarked. Only the
  # fields merged with `prefer_severity` are read ----
  severity_cols <- intersect(
    names(merge_fields)[merge_fields == "prefer_severity"], names(result)
  )
  if (length(severity_cols) == 0L || !"c_death" %in% names(result)) {
    return(result)
  }

  died <- Reduce(
    `|`, lapply(severity_cols, function(col) {
      disposition_severity(result[[col]]) == 3L
    })
  )
  if (!any(died)) return(result)

  current <- result[["c_death"]]
  yes <- if (is.integer(current)) {
    1L
  } else if (is.numeric(current)) {
    1
  } else if (any(tolower(as.character(current)) == "1", na.rm = TRUE)) {
    "1"
  } else {
    "Yes"
  }
  is_yes <- tolower(as.character(current)) %in% c("yes", "1")
  result[["c_death"]][died & !is_yes] <- yes
  result
}
