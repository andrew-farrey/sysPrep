#' Per-column merge rules for linked episodes
#'
#' When `link_encounters()` links an ED record and a separately submitted
#' inpatient record into one episode, each column of the kept row is
#' reconciled by a rule. The principle: only the `HasBeen_` flags, `C_Death`
#' and `DispositionCategory` are collapsed to one value so the row reflects the
#' whole encounter of care; every other field keeps what either record holds.
#'
#' These helpers resolve and apply those rules.
#'
#' \itemize{
#'   \item `resolve_merge_rules()` assigns a strategy to every column that is
#'     merged. A column named in `merge_fields` uses that strategy. Otherwise
#'     the column is looked up in the internal `merge_field_table` (built from
#'     `data-raw/merge_field_classification.csv`, which follows the NSSP ESSENCE
#'     data dictionary) by its [janitor::make_clean_names()] name, then by a
#'     looser spelling (lower case, no underscores) when that spelling points to
#'     exactly one table row, so `c_biosense_id` finds `C_BioSense_ID`.
#'     Anything else follows its type: text keeps both records' values
#'     (`"concat"`), everything else takes the first informative value
#'     (`"prefer_informative"`).
#'   \item `merge_linked_episodes()` applies the rules to the rows of every
#'     multi-row episode and returns one row per episode. The rules that need
#'     no per-episode logic are computed over whole columns at once, and only
#'     the text-merging rules visit episodes one at a time.
#'   \item `is_informative()` says which values carry information: a missing
#'     value, blank text, or a placeholder such as `"None"` or `"Unknown"` does
#'     not.
#'   \item `merge_prefer_primary()`, `merge_prefer_informative()`,
#'     `merge_earliest()` and `merge_max()` are the one-episode versions of the
#'     matching strategies; `merge_linked_episodes()` must agree with them.
#' }
#'
#' @details
#' Rules that need a winning record use the **primary row** (the ED record when
#' the episode has one, otherwise its first row). A column that takes "the
#' winning record's value unless it is uninformative" takes the primary row's
#' value, or, when that is missing or a placeholder, the first informative
#' value from another record.
#'
#' Two kinds of rule tie a column to another column's winning record, so values
#' that belong together never mix records. `"prefer_informative_disposition"`
#' (discharge and death times) uses the record that won `DispositionCategory`
#' as its winning record. `"follow"` (units, derived lookups, durations) takes
#' the value from whichever record supplied the column it follows, even when
#' that value is missing: a weight and its units, or a zip code and its region,
#' always come from one record. A column whose source is absent from the data
#' falls back to the first informative value.
#'
#' `"recompute_length"` sets `CCOrig_Length`, `CCParsed_Length` and `DD_Length`
#' to the number of characters (separators included) in the merged
#' `ChiefComplaintOrig`, `ChiefComplaintParsed` and `DischargeDiagnosis`. When
#' the length column is present but its text column is not, the winning
#' record's value is kept and a warning says so.
#'
#' @param data A data frame with the episode columns `.episode_id` and
#'   `patient_class`.
#' @param merge_fields `NULL`, or a named character vector mapping column
#'   names (already in [janitor::make_clean_names()] form) to a strategy from
#'   `merge_strategies`. Each entry replaces the table's rule for that column.
#' @param table The rule table; defaults to the internal `merge_field_table`.
#'   Exposed so tests can supply a small table.
#' @param multi_row The rows of the episodes that have more than one row, with
#'   `.episode_id`, `patient_class` and, when present, `.link_pull`.
#' @param rules The data frame returned by `resolve_merge_rules()`.
#' @param merge_delimiter The delimiter used by the `"union_delimited"` and
#'   `"union_ccdd"` strategies.
#' @param severity_col The column merged with `"prefer_severity"`, or `NA`.
#' @param has_been_cols Names of the `HasBeen_` flag columns, which take the
#'   maximum across an episode's rows.
#' @param x,values A vector of one column's values.
#' @param extra Extra text values to treat as uninformative for this column.
#' @param primary_value The primary row's value.
#' @return `resolve_merge_rules()` returns a data frame with one row per
#'   merged column: `column`, `strategy`, and `follow` (the column followed,
#'   or the text column whose length is recomputed, else `NA`).
#'   `merge_linked_episodes()` returns one row per episode.
#'   `is_informative()` returns a logical vector. The `merge_*()` functions
#'   return a single value.
#' @keywords internal
resolve_merge_rules <- function(data, merge_fields,
                                table = merge_field_table) {
  skip <- startsWith(names(data), ".") | names(data) == "patient_class" |
    grepl("^has_been_", names(data))
  cols <- names(data)[!skip]

  # 1. the exact clean name; 2. a looser spelling, only when it names a single
  #    table row ----
  hit      <- match(cols, table$name)
  loose    <- gsub("[^a-z0-9]", "", tolower(cols))
  loose_n  <- table(table$loose)
  loose_ok <- is.na(hit) & loose %in% names(loose_n)
  loose_ok[loose_ok] <- as.integer(loose_n[loose[loose_ok]]) == 1L
  hit[loose_ok] <- match(loose[loose_ok], table$loose)

  strategy <- table$strategy[hit]
  follow   <- table$follow[hit]

  # 3. a column the table does not know follows its type; a table rule for text
  #    never applies to a column that is not text ----
  is_text <- vapply(
    data[cols], function(x) is.character(x) || is.factor(x), logical(1L)
  )
  is_list <- vapply(data[cols], is.list, logical(1L))
  text_only <- c("concat", "union_delimited", "union_ccdd")
  unknown   <- is.na(strategy)
  strategy[unknown] <- ifelse(is_text[unknown], "concat", "prefer_informative")
  strategy[is_list] <- "prefer_primary"
  text_rule_on_other <- !is_text & strategy %in% text_only & !unknown
  strategy[text_rule_on_other] <- "prefer_informative"

  # 4. the caller's strategies replace the table's ----
  if (length(merge_fields) > 0L) {
    named <- match(names(merge_fields), cols)
    keep  <- !is.na(named)
    strategy[named[keep]] <- unname(merge_fields)[keep]
    follow[named[keep]]   <- NA_character_
  }

  data.frame(
    column = cols, strategy = strategy, follow = follow,
    stringsAsFactors = FALSE
  )
}

#' @rdname resolve_merge_rules
is_informative <- function(x, extra = NULL) {
  # Text that is blank, or one of ESSENCE's and sites' stand-ins for "no
  # value", says nothing; a number or time is informative unless it is
  # missing, so a zero is a real value. `extra` adds stand-ins that mean
  # "unknown" only in one column ----
  if (is.character(x) || is.factor(x)) {
    value <- tolower(trimws(as.character(x)))
    return(
      !is.na(value) & nzchar(value) &
        !(value %in% c(placeholder_values, extra))
    )
  }
  !is.na(x)
}

# "U" is ESSENCE's code for an unknown Sex; it is a real value in no other
# column the package knows, so it counts as uninformative only there ----
column_placeholders <- list(sex = "u", orig_sex = "u")

placeholder_values <- c(
  "none", "unknown", "unk", "null", "na", "n/a", "nan", "not reported",
  "not available"
)

time_value <- function(x) {
  if (inherits(x, c("POSIXct", "Date"))) return(as.numeric(x))
  as.numeric(safe_as_posixct(x))
}

numeric_value <- function(x) {
  suppressWarnings(as.numeric(as.character(x)))
}

#' @rdname resolve_merge_rules
merge_prefer_primary <- function(primary_value) {
  primary_value
}

#' @rdname resolve_merge_rules
merge_prefer_informative <- function(values, primary_value) {
  if (is_informative(primary_value)) return(primary_value)
  informative <- which(is_informative(values))
  if (length(informative) > 0L) return(values[informative[1L]])
  primary_value
}

#' @rdname resolve_merge_rules
merge_earliest <- function(values, primary_value) {
  when <- time_value(values)
  if (all(is.na(when))) return(primary_value)
  values[which.min(when)]
}

#' @rdname resolve_merge_rules
merge_max <- function(values, primary_value) {
  size <- numeric_value(values)
  if (all(is.na(size))) return(primary_value)
  values[which.max(size)]
}

#' @rdname resolve_merge_rules
merge_linked_episodes <- function(multi_row, rules, merge_delimiter,
                                  severity_col, has_been_cols) {
  n             <- nrow(multi_row)
  episode_id    <- multi_row[[".episode_id"]]
  ep            <- match(episode_id, unique(episode_id))
  n_ep          <- max(ep)
  patient_class <- multi_row[["patient_class"]]
  is_primary    <- episode_primary_row(ep, patient_class)

  # primary_pos: each episode's primary row; pos: a row's place in its
  # episode's order of candidates (primary row first, then the others in the
  # order they arrive) ----
  primary_pos <- integer(n_ep)
  primary_pos[ep[is_primary]] <- which(is_primary)
  pos <- integer(n)
  pos[order(ep, !is_primary, seq_len(n))] <- seq_len(n)

  from_inpatient <- if (".link_pull" %in% names(multi_row)) {
    multi_row[[".link_pull"]] == "inpatient"
  } else {
    rep(FALSE, n)
  }
  groups <- split(seq_len(n), ep)

  # The record that won DispositionCategory, per episode (NA when no record
  # reports a known outcome) ----
  severity_row <- rep(NA_integer_, n_ep)
  if (!is.na(severity_col)) {
    category <- multi_row[[severity_col]]
    severity_row <- vapply(
      seq_len(n_ep),
      function(e) {
        rows <- groups[[e]]
        hit  <- severity_row_index(
          category[rows], patient_class[rows], category[primary_pos[e]],
          from_inpatient[rows]
        )
        if (is.na(hit)) NA_integer_ else rows[hit]
      },
      integer(1L)
    )
  }
  disposition_base <- ifelse(is.na(severity_row), primary_pos, severity_row)

  # The first informative row of each episode, starting from `base` ----
  supplier_of <- function(informative, base) {
    rows <- which(informative)
    if (length(rows) == 0L) return(base)
    rank        <- pos
    rank[base]  <- 0L
    ordered     <- rows[order(ep[rows], rank[rows])]
    first       <- ordered[!duplicated(ep[ordered])]
    out         <- base
    out[ep[first]] <- first
    out
  }
  # One row per episode chosen by the smallest key among rows with a key ----
  pick_by <- function(has_key, key) {
    rows <- which(has_key)
    out  <- primary_pos
    if (length(rows) > 0L) {
      ordered <- rows[order(ep[rows], key[rows], rows)]
      first   <- ordered[!duplicated(ep[ordered])]
      out[ep[first]] <- first
    }
    out
  }

  suppliers <- new.env(parent = emptyenv())
  rule_of   <- function(col) rules[match(col, rules$column), , drop = FALSE]
  own_supplier <- function(col, strategy) {
    base <- if (identical(strategy, "prefer_informative_disposition")) {
      disposition_base
    } else {
      primary_pos
    }
    supplier_of(
      is_informative(multi_row[[col]], column_placeholders[[col]]), base
    )
  }
  get_supplier <- function(col, depth = 0L) {
    cached <- get0(col, envir = suppliers, inherits = FALSE)
    if (!is.null(cached)) return(cached)
    rule <- rule_of(col)
    source <- rule$follow
    out <- if (identical(rule$strategy, "follow") && !is.na(source) &&
                 source %in% rules$column && depth < 10L) {
      get_supplier(source, depth + 1L)
    } else {
      own_supplier(col, rule$strategy)
    }
    assign(col, out, envir = suppliers)
    out
  }

  merged <- multi_row[primary_pos, , drop = FALSE]

  for (col in has_been_cols) {
    x <- multi_row[[col]]
    merged[[col]] <- x[pick_by(!is.na(x), -as.numeric(x))]
  }

  not_recomputed <- character(0)

  # Length columns are computed from merged text, so they come last ----
  recompute <- rules$strategy == "recompute_length"
  for (i in c(which(!recompute), which(recompute))) {
    col      <- rules$column[i]
    strategy <- rules$strategy[i]
    x        <- multi_row[[col]]

    merged[[col]] <- switch(
      strategy,
      prefer_primary = x[primary_pos],
      prefer_informative = ,
      prefer_informative_disposition = ,
      follow = x[get_supplier(col)],
      earliest = {
        when <- time_value(x)
        x[pick_by(!is.na(when), when)]
      },
      max = {
        size <- numeric_value(x)
        x[pick_by(!is.na(size), -size)]
      },
      prefer_yes = {
        yes <- !is.na(x) & tolower(as.character(x)) %in% c("yes", "1")
        x[pick_by(yes, rep(0, n))]
      },
      recompute_length = {
        text_col <- rules$follow[i]
        winner   <- x[supplier_of(is_informative(x), primary_pos)]
        if (is.na(text_col) || !text_col %in% names(merged)) {
          not_recomputed <- c(not_recomputed, col)
          winner
        } else {
          size <- nchar(as.character(merged[[text_col]]), keepNA = TRUE)
          if (is.character(x)) {
            ifelse(is.na(size), winner, as.character(size))
          } else if (is.integer(x)) {
            ifelse(is.na(size), winner, as.integer(size))
          } else {
            ifelse(is.na(size), winner, as.numeric(size))
          }
        }
      },
      union_delimited = merge_union_delimited_all(
        x, ep, n_ep, merge_delimiter
      ),
      {
        # the text-merging strategies visit episodes one at a time; when an
        # episode holds at most one distinct informative value there is
        # nothing to join, and the column's first informative value is it
        merge_each_episode(
          x, strategy, groups, primary_pos, severity_row, patient_class,
          from_inpatient, ep, n_ep, merge_delimiter,
          fallback = x[supplier_of(is_informative(x), primary_pos)]
        )
      }
    )
  }

  if (length(not_recomputed) > 0L) {
    warn_lengths_not_recomputed(not_recomputed, rules)
  }
  merged
}

#' @rdname resolve_merge_rules
merge_union_delimited_all <- function(x, ep, n_ep, delimiter) {
  # merge_union_delimited() for every episode at once: split all the values,
  # keep each episode's distinct parts in the order they first appear, and
  # join them. An episode with no value at all is NA, as in the one-episode
  # version ----
  value   <- as.character(x)
  rows    <- which(!is.na(value) & value != "")
  out     <- rep(NA_character_, n_ep)
  if (length(rows) == 0L) return(out)
  out[unique(ep[rows])] <- ""

  parts <- strsplit(value[rows], delimiter, fixed = TRUE)
  token <- trimws(unlist(parts, use.names = FALSE))
  owner <- rep(ep[rows], lengths(parts))
  keep  <- nzchar(token)
  token <- token[keep]
  owner <- owner[keep]
  first <- !duplicated(paste(owner, token, sep = "\r"))
  pieces <- split(token[first], owner[first])
  if (length(pieces) > 0L) {
    out[as.integer(names(pieces))] <- vapply(
      pieces, paste, character(1L), collapse = delimiter
    )
  }

  # the list keeps a delimiter at both ends when every value had one ----
  trimmed   <- trimws(value[rows])
  has_outer <- startsWith(trimmed, delimiter) & endsWith(trimmed, delimiter)
  n_values  <- tabulate(ep[rows], n_ep)
  n_outer   <- tabulate(ep[rows][has_outer], n_ep)
  wrap      <- n_values > 0L & n_values == n_outer & !is.na(out) & nzchar(out)
  out[wrap] <- paste0(delimiter, out[wrap], delimiter)
  out
}

merge_each_episode <- function(x, strategy, groups, primary_pos, severity_row,
                               patient_class, from_inpatient, ep, n_ep,
                               delimiter, fallback) {
  # The text-merging rules visit episodes one at a time, which is slow at
  # scale, so the work is cut two ways. An episode with at most one distinct
  # informative value has nothing to join (its first informative value, the
  # `fallback`, is the answer). And the rules that depend only on the values
  # (concat, the unions) compute each distinct combination of values once:
  # most text columns repeat a handful of combinations across thousands of
  # episodes ----
  joins_values <- strategy %in% c("concat", "union_delimited", "union_ccdd")
  informative  <- NULL
  todo         <- rep(TRUE, n_ep)
  if (identical(strategy, "concat")) {
    informative <- is_informative(x)
    rows        <- which(informative)
    distinct    <- !duplicated(
      paste(ep[rows], as.character(x[rows]), sep = "\r")
    )
    todo        <- tabulate(ep[rows][distinct], n_ep) > 1L
  }

  out      <- fallback
  episodes <- which(todo)
  if (length(episodes) == 0L) return(out)

  if (joins_values) {
    shown <- as.character(x)
    shown[is.na(shown)] <- "\001"
    key <- vapply(
      episodes,
      function(e) {
        paste(
          c(shown[primary_pos[e]], shown[groups[[e]]]), collapse = "\r"
        )
      },
      character(1L)
    )
    first    <- !duplicated(key)
    computed <- character(sum(first))
    for (k in seq_along(computed)) {
      e    <- episodes[first][k]
      rows <- groups[[e]]
      computed[k] <- if (is.null(informative)) {
        merge_field_value(
          values = x[rows], patient_classes = patient_class[rows],
          primary_value = x[primary_pos[e]], strategy = strategy,
          delimiter = delimiter
        )
      } else {
        merge_concat(
          x[rows], x[primary_pos[e]], informative[rows],
          informative[primary_pos[e]]
        )
      }
    }
    out[episodes] <- computed[match(key, key[first])]
    return(out)
  }

  for (e in episodes) {
    rows <- groups[[e]]
    out[e] <- merge_field_value(
      values          = x[rows],
      patient_classes = patient_class[rows],
      primary_value   = x[primary_pos[e]],
      strategy        = strategy,
      delimiter       = delimiter,
      severity_row    = if (is.na(severity_row[e])) {
        NA_integer_
      } else {
        match(severity_row[e], rows)
      },
      from_inpatient  = from_inpatient[rows]
    )
  }
  out
}

warn_lengths_not_recomputed <- function(columns, rules) {
  # every length column and its text column are rows of the table ----
  api <- function(name) {
    merge_field_table$api[match(name, merge_field_table$name)]
  }
  sources <- rules$follow[match(columns, rules$column)]
  rlang::warn(
    c(
      paste0(
        "Length column(s) not recomputed after linked records were merged: ",
        paste0("`", api(columns), "`", collapse = ", "), "."
      ),
      "i" = paste0(
        "Each is recomputed from its text column (",
        paste0("`", api(sources), "`", collapse = ", "),
        "), which is not in the data; the winning record's value was kept."
      )
    )
  )
}
