# Builds the internal `merge_field_table` (R/sysdata.rda) that link_encounters()
# uses to decide how each ESSENCE column is reconciled when an ED record and an
# inpatient record are linked into one episode.
#
# The specification is data-raw/merge_field_classification.csv, which lists the
# `dataDetails` pull columns (from the NSSP ESSENCE data dictionary, "ESSENCE
# API and Data Details" tab, with the processing rules on the "ESSENCE" tab).
# Edit the CSV, then rerun this script and commit both the CSV and
# R/sysdata.rda:
#
#   source("data-raw/merge_field_table.R")
#
# Columns kept in the table:
#   name     the column name as janitor::make_clean_names() writes it, which is
#            how link_encounters() sees every column
#   loose    the same name lower-cased with every non-alphanumeric removed; used
#            only to match a spelling such as `c_biosense_id` when it points to
#            exactly one table row
#   strategy the engine's merge strategy (see ?merge_strategies)
#   follow   for strategy "follow": the clean name of the column whose winning
#            record supplies this column too; for "recompute_length": the clean
#            name of the text column whose length is recomputed
#
# Fields the dictionary marks as not populated, not in use or not ingested are
# listed in the CSV as "excluded" and are left out here: they take the default
# for their type if a pull happens to contain them.

csv_path <- if (exists("merge_csv_path")) {
  merge_csv_path
} else {
  "data-raw/merge_field_classification.csv"
}

spec <- utils::read.csv(csv_path, stringsAsFactors = FALSE, na.strings = "")

# CSV strategy -> engine strategy
engine <- c(
  winner_keeps             = "prefer_informative",
  winner_keeps_disposition = "prefer_informative_disposition",
  concat                   = "concat",
  prefer_yes               = "prefer_yes",
  min                      = "earliest",
  max                      = "max",
  primary                  = "prefer_primary",
  union_delimited          = "union_delimited",
  union_ccdd               = "union_ccdd",
  follow                   = "follow",
  recompute_length         = "recompute_length",
  death_rule               = "prefer_yes",
  prefer_severity          = "prefer_severity"
)

spec <- spec[spec$strategy != "excluded", , drop = FALSE]
stopifnot(all(spec$strategy %in% names(engine)))

# One name at a time: make_clean_names() de-duplicates within a vector by
# appending _2, _3, ..., which would corrupt repeated `follow` sources and hide
# genuine collisions between two API names
clean <- function(x) {
  vapply(
    x, function(s) janitor::make_clean_names(s), character(1L),
    USE.NAMES = FALSE
  )
}

merge_field_table <- data.frame(
  name     = clean(spec$api_name),
  strategy = unname(engine[spec$strategy]),
  follow   = ifelse(
    is.na(spec$follow_source), NA_character_, clean(spec$follow_source)
  ),
  stringsAsFactors = FALSE
)
merge_field_table$loose <- gsub("[^a-z0-9]", "", tolower(spec$api_name))
# the field's name as ESSENCE spells it, for messages
merge_field_table$api   <- spec$api_name

# Two API names can clean to the same name; keep the first so a lookup is
# unambiguous, and say so
dups <- merge_field_table$name[duplicated(merge_field_table$name)]
if (length(dups) > 0L) {
  message("Duplicate clean names dropped: ", paste(unique(dups), collapse = ", "))
  merge_field_table <- merge_field_table[!duplicated(merge_field_table$name), ]
}

# Every "follow" and "recompute_length" source must itself be a table row
needs_source <- merge_field_table$strategy %in% c("follow", "recompute_length")
stopifnot(
  !anyNA(merge_field_table$follow[needs_source]),
  all(merge_field_table$follow[needs_source] %in% merge_field_table$name)
)

rownames(merge_field_table) <- NULL
save(merge_field_table, file = "R/sysdata.rda", compress = "xz", version = 2)
message(
  "Wrote R/sysdata.rda: ", nrow(merge_field_table), " fields, ",
  sum(merge_field_table$strategy == "follow"), " follow rows"
)
