# link_encounters(): how each column is reconciled when an ED record and a
# separately submitted inpatient record are linked into one episode ----
#
# Principle: only the HasBeen_ flags, C_Death and DispositionCategory are
# collapsed to one value so the row reflects the whole encounter of care;
# every other field keeps what either record holds. The per-field rules live
# in data-raw/merge_field_classification.csv (internal `merge_field_table`).

# An ED record and the inpatient record that follows it. `ed` and `inp` are
# named lists of one-element vectors added (or replaced) on each record. Both
# records end DISCHARGED (the inpatient pull's record wins that tie) and
# neither names a death, so the death rule stays out of the way ----
rules_pair <- function(ed = list(), inp = list()) {
  fx <- make_readmit_merge_data()
  fx$ed_data$C_Death                                  <- "No"
  fx$ed_data$DispositionCategory                      <- "DISCHARGED"
  fx$inpatient_admission_data$C_Death                 <- "No"
  fx$inpatient_admission_data$DispositionCategory     <- "DISCHARGED"
  fx$inpatient_admission_data$Discharge_Disposition   <- "Admitted to hospital"
  for (nm in names(ed))  fx$ed_data[[nm]]                   <- ed[[nm]]
  for (nm in names(inp)) fx$inpatient_admission_data[[nm]]  <- inp[[nm]]
  fx
}

link_rules <- function(fx, ...) {
  suppressMessages(
    link_encounters(fx$ed_data, fx$inpatient_admission_data, ...)
  )
}

# ---- the rule table ----

test_that("the internal rule table is complete and consistent", {
  tbl <- merge_field_table
  expect_true(all(c("name", "strategy", "follow", "loose") %in% names(tbl)))
  expect_false(anyDuplicated(tbl$name) > 0L)
  expect_true(all(tbl$strategy %in% c(
    merge_strategies, "prefer_informative_disposition", "follow",
    "recompute_length"
  )))

  # every follow / recompute source is itself a table row, and a chain of
  # follow rows always ends (no cycles)
  needs_source <- tbl$strategy %in% c("follow", "recompute_length")
  expect_true(all(tbl$follow[needs_source] %in% tbl$name))
  for (nm in tbl$name[tbl$strategy == "follow"]) {
    seen <- nm
    while (isTRUE(tbl$strategy[match(seen[length(seen)], tbl$name)] == "follow")) {
      nxt <- tbl$follow[match(seen[length(seen)], tbl$name)]
      expect_false(nxt %in% seen, info = nm)
      seen <- c(seen, nxt)
    }
  }
})

test_that("the rule table reproduces the decisions made for specific fields", {
  rule <- function(x) merge_field_table$strategy[match(x, merge_field_table$name)]
  expect_equal(rule("discharge_disposition"), "concat")
  expect_equal(rule("disposition_category"), "prefer_severity")
  expect_equal(rule("c_death"), "prefer_yes")
  expect_equal(rule("death_indicator"), "prefer_yes")
  expect_equal(rule("c_bio_sense_id"), "prefer_informative")
  expect_equal(rule("c_patient_class"), "prefer_informative")
  expect_equal(rule("admit_date_time"), "prefer_informative")
  expect_equal(rule("discharge_date_time"), "prefer_informative_disposition")
  expect_equal(rule("death_date_time"), "prefer_informative_disposition")
  expect_equal(rule("first_date_time_added"), "earliest")
  expect_equal(rule("cc_informative"), "max")
  expect_equal(rule("dd_length"), "recompute_length")
  expect_equal(rule("icd_chapter_flat"), "union_delimited")
  # DeathDateTime (not populated by ESSENCE) must not shadow Death_Date_Time
  expect_false("death_date_time_2" %in% merge_field_table$name)
})

# ---- resolving a rule for every column ----

test_that("resolve_merge_rules() uses the table, then the column type", {
  data <- tibble::tibble(
    .episode_id = "1_A", patient_class = "ED", .index_encounter = TRUE,
    has_been_e = 1L,
    discharge_disposition = "x", age = "30", arrived_date_time = "t",
    custom_text = "a", custom_number = 1.5,
    custom_date = as.Date("2023-01-01"), custom_flag = TRUE
  )
  rules <- resolve_merge_rules(data, merge_fields = NULL)
  strategy <- stats::setNames(rules$strategy, rules$column)

  expect_equal(strategy[["discharge_disposition"]], "concat")
  expect_equal(strategy[["age"]], "prefer_informative")
  expect_equal(strategy[["custom_text"]], "concat")
  expect_equal(strategy[["custom_number"]], "prefer_informative")
  expect_equal(strategy[["custom_date"]], "prefer_informative")
  expect_equal(strategy[["custom_flag"]], "prefer_informative")

  # bookkeeping columns, patient_class and the HasBeen_ flags are not merged
  expect_false(any(c(
    ".episode_id", ".index_encounter", "patient_class", "has_been_e"
  ) %in% rules$column))
})

test_that("a user strategy overrides the table for that column only", {
  data <- tibble::tibble(
    .episode_id = "1_A", patient_class = "ED", .index_encounter = TRUE,
    discharge_disposition = "x", age = "30"
  )
  rules <- resolve_merge_rules(
    data, merge_fields = c(discharge_disposition = "follow_severity")
  )
  strategy <- stats::setNames(rules$strategy, rules$column)
  expect_equal(strategy[["discharge_disposition"]], "follow_severity")
  expect_equal(strategy[["age"]], "prefer_informative")
})

test_that("a column spelled c_biosense_id still matches its table row", {
  data <- tibble::tibble(
    .episode_id = "1_A", patient_class = "ED", .index_encounter = TRUE,
    c_biosense_id = "BS1"
  )
  rules <- resolve_merge_rules(data, merge_fields = NULL)
  expect_equal(rules$strategy[rules$column == "c_biosense_id"],
               "prefer_informative")
})

test_that("an ambiguous loose spelling falls back to the column type", {
  # Two table rows share the loose spelling "deathdatetime" (as Death_Date_Time
  # and DeathDateTime do), so a column spelled that way must not borrow either
  # rule; an exact clean name still matches its own row
  toy <- data.frame(
    name = c("death_date_time", "death_date_time_x", "age"),
    strategy = c("prefer_informative_disposition", "prefer_primary",
                 "prefer_informative"),
    follow = NA_character_,
    loose = c("deathdatetime", "deathdatetime", "age"),
    stringsAsFactors = FALSE
  )
  data <- tibble::tibble(
    .episode_id = "1_A", patient_class = "ED", .index_encounter = TRUE,
    deathdatetime = "t", death_date_time = "t", age = "30"
  )
  rules <- resolve_merge_rules(data, merge_fields = NULL, table = toy)
  strategy <- stats::setNames(rules$strategy, rules$column)
  expect_equal(strategy[["deathdatetime"]], "concat")
  expect_equal(strategy[["death_date_time"]], "prefer_informative_disposition")
})

test_that("check_merge_fields() accepts NULL and the new strategies", {
  expect_silent(check_merge_fields(NULL))
  expect_true(all(
    c("prefer_primary", "prefer_informative", "earliest", "max") %in%
      merge_strategies
  ))
  expect_silent(check_merge_fields(c(x = "earliest", y = "max")))
})

# ---- uninformative values ----

test_that("is_informative() treats blank and placeholder text as missing", {
  expect_equal(
    is_informative(c("a", "", "  ", NA, "None", "unknown", "N/A", "0")),
    c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE)
  )
  # a number is informative unless missing: zero is a real value
  expect_equal(is_informative(c(0, NA, 3)), c(TRUE, FALSE, TRUE))
  expect_equal(
    is_informative(as.POSIXct(c("2023-01-01 08:00:00", NA), tz = "UTC")),
    c(TRUE, FALSE)
  )
})

# ---- raw fields: text and codes keep what both records hold ----

test_that("Discharge_Disposition keeps both records' text", {
  result <- link_rules(rules_pair())
  expect_equal(result$discharge_disposition,
               "Discharged to home; Admitted to hospital")
})

test_that("identical text is not repeated", {
  result <- link_rules(rules_pair(
    inp = list(Discharge_Disposition = "Discharged to home")
  ))
  expect_equal(result$discharge_disposition, "Discharged to home")
})

test_that("an unlisted text column keeps both records' values", {
  result <- link_rules(rules_pair(
    ed = list(Triage_Comment = "chest pain"),
    inp = list(Triage_Comment = "cardiac arrest")
  ))
  expect_equal(result$triage_comment, "chest pain; cardiac arrest")
})

test_that("an unlisted numeric column takes the first informative value", {
  result <- link_rules(rules_pair(
    ed = list(Custom_Score = NA_real_), inp = list(Custom_Score = 7.5)
  ))
  expect_equal(result$custom_score, 7.5)
  result <- link_rules(rules_pair(
    ed = list(Custom_Score = 2), inp = list(Custom_Score = 7.5)
  ))
  expect_equal(result$custom_score, 2)
})

# ---- scalars and times: the winning record, unless it is uninformative ----

test_that("Age takes the winning record's value unless it is uninformative", {
  both <- link_rules(rules_pair(ed = list(Age = "35"), inp = list(Age = "36")))
  expect_equal(both$age, "35")

  missing <- link_rules(rules_pair(
    ed = list(Age = NA_character_), inp = list(Age = "40")
  ))
  expect_equal(missing$age, "40")

  placeholder <- link_rules(rules_pair(
    ed = list(Age = "Unknown"), inp = list(Age = "40")
  ))
  expect_equal(placeholder$age, "40")
})

test_that("identifiers and patient class keep a single value", {
  result <- link_rules(rules_pair(
    ed = list(C_Patient_Class = "E"), inp = list(C_Patient_Class = "I")
  ))
  expect_equal(result$c_bio_sense_id, "BS0000000001")
  expect_equal(result$c_patient_class, "E")
})

test_that("record timestamps and Admit_Date_Time use the winning record", {
  result <- link_rules(rules_pair(
    ed = list(Arrived_Date_Time = "2023-01-01 08:05:00",
              Admit_Date_Time = "2023-01-01 08:30:00"),
    inp = list(Arrived_Date_Time = "2023-01-01 14:05:00",
               Admit_Date_Time = "2023-01-01 14:30:00")
  ))
  expect_equal(result$arrived_date_time, "2023-01-01 08:05:00")
  expect_equal(result$admit_date_time, "2023-01-01 08:30:00")

  filled <- link_rules(rules_pair(
    ed = list(Admit_Date_Time = NA_character_),
    inp = list(Admit_Date_Time = "2023-01-01 14:30:00")
  ))
  expect_equal(filled$admit_date_time, "2023-01-01 14:30:00")
})

test_that("real POSIXct and Date columns are kept as their own type", {
  result <- link_rules(rules_pair(
    ed = list(Custom_Time = as.POSIXct(NA_real_, origin = "1970-01-01", tz = "UTC")),
    inp = list(Custom_Time = as.POSIXct("2023-01-02 10:00:00", tz = "UTC"))
  ))
  expect_s3_class(result$custom_time, "POSIXct")
  expect_equal(format(result$custom_time, tz = "UTC"), "2023-01-02 10:00:00")
})

test_that("outcome times follow the record that won DispositionCategory", {
  # both DISCHARGED: the inpatient pull's record wins the tie
  tie <- link_rules(rules_pair(
    ed = list(Discharge_Date_Time = "2023-01-01 09:00:00"),
    inp = list(Discharge_Date_Time = "2023-01-03 10:00:00")
  ))
  expect_equal(tie$discharge_date_time, "2023-01-03 10:00:00")

  # an inpatient UNKNOWN is not a known outcome, so the ED record wins
  unknown <- link_rules(rules_pair(
    ed = list(Discharge_Date_Time = "2023-01-01 09:00:00"),
    inp = list(Discharge_Date_Time = "2023-01-03 10:00:00",
               DispositionCategory = "UNKNOWN")
  ))
  expect_equal(unknown$discharge_date_time, "2023-01-01 09:00:00")

  # the winner holds no time, so the other record's is kept
  filled <- link_rules(rules_pair(
    ed = list(Discharge_Date_Time = "2023-01-01 09:00:00"),
    inp = list(Discharge_Date_Time = NA_character_)
  ))
  expect_equal(filled$discharge_date_time, "2023-01-01 09:00:00")
})

test_that("a death time comes from the record that reported the death", {
  result <- link_rules(rules_pair(
    ed = list(Death_Date_Time = NA_character_,
              Discharge_Date_Time = "2023-01-01 09:00:00"),
    inp = list(Death_Date_Time = "2023-01-02 03:00:00",
               Discharge_Date_Time = "2023-01-02 03:10:00",
               C_Death = "Yes", DispositionCategory = "DECEASED")
  ))
  expect_equal(result$death_date_time, "2023-01-02 03:00:00")
  expect_equal(result$discharge_date_time, "2023-01-02 03:10:00")
})

test_that("durations travel with Discharge_Date_Time", {
  both <- link_rules(rules_pair(
    ed = list(Discharge_Date_Time = "2023-01-01 09:00:00",
              MinutesFromVisitToDischarge = "60"),
    inp = list(Discharge_Date_Time = "2023-01-03 10:00:00",
               MinutesFromVisitToDischarge = "2640")
  ))
  expect_equal(both$discharge_date_time, "2023-01-03 10:00:00")
  expect_equal(both$minutes_from_visit_to_discharge, "2640")

  # the winner holds no time, so the duration comes from the record that
  # supplied the time
  fallback <- link_rules(rules_pair(
    ed = list(Discharge_Date_Time = "2023-01-01 09:00:00",
              MinutesFromVisitToDischarge = "60"),
    inp = list(Discharge_Date_Time = NA_character_,
               MinutesFromVisitToDischarge = "2640")
  ))
  expect_equal(fallback$discharge_date_time, "2023-01-01 09:00:00")
  expect_equal(fallback$minutes_from_visit_to_discharge, "60")
})

test_that("a measurement and its units always come from one record", {
  weight <- link_rules(rules_pair(
    ed = list(Weight = "70", Weight_Units = "kg"),
    inp = list(Weight = "154", Weight_Units = "lb")
  ))
  expect_equal(c(weight$weight, weight$weight_units), c("70", "kg"))

  age <- link_rules(rules_pair(
    ed = list(Age = NA_character_, C_Patient_Age_Units = "months",
              AgeGroup = "00-04"),
    inp = list(Age = "40", C_Patient_Age_Units = "years", AgeGroup = "35-44")
  ))
  expect_equal(age$age, "40")
  expect_equal(age$c_patient_age_units, "years")
  expect_equal(age$age_group, "35-44")
})

test_that("zip code, region and state follow one record", {
  result <- link_rules(rules_pair(
    ed = list(Patient_Zip = NA_character_, ZipCode = "99999",
              Region = "KY_A"),
    inp = list(Patient_Zip = "40202", ZipCode = "40202", Region = "KY_B")
  ))
  expect_equal(
    c(result$patient_zip, result$zip_code, result$region),
    c("40202", "40202", "KY_B")
  )
})

test_that("derived race and ethnicity fields follow their source", {
  result <- link_rules(rules_pair(
    ed = list(C_Race = NA_character_, Race_flat = ";White;"),
    inp = list(C_Race = "Black or African American",
               Race_flat = ";Black or African American;")
  ))
  expect_equal(result$c_race, "Black or African American")
  expect_equal(result$race_flat, ";Black or African American;")
})

test_that("a follower without its source column falls back to the first informative value", {
  result <- link_rules(rules_pair(
    ed = list(Region = NA_character_), inp = list(Region = "KY_B")
  ))
  expect_equal(result$region, "KY_B")
})

# ---- derived fields ----

test_that("FirstDateTimeAdded keeps the earliest time", {
  result <- link_rules(rules_pair(
    ed = list(FirstDateTimeAdded = "2023-01-01 08:00:00"),
    inp = list(FirstDateTimeAdded = "2023-01-01 07:00:00")
  ))
  expect_equal(result$first_date_time_added, "2023-01-01 07:00:00")
})

test_that("informative and available indicators are 1 when either record says so", {
  result <- link_rules(rules_pair(
    ed = list(CCInformative = "0", DDAvailable = "1", DDInformative = NA_character_),
    inp = list(CCInformative = "1", DDAvailable = "0", DDInformative = "1")
  ))
  expect_equal(result$cc_informative, "1")
  expect_equal(result$dd_available, "1")
  expect_equal(result$dd_informative, "1")

  typed <- link_rules(rules_pair(
    ed = list(CCAvailable = 0L), inp = list(CCAvailable = 1L)
  ))
  expect_identical(typed$cc_available, 1L)
})

test_that("delimited code lists are united and keep their outer delimiters", {
  both_outer <- link_rules(rules_pair(
    ed = list(ICD_Chapter_Flat = ";12;9;"), inp = list(ICD_Chapter_Flat = ";9;5;")
  ))
  expect_equal(both_outer$icd_chapter_flat, ";12;9;5;")

  no_outer <- link_rules(rules_pair(
    ed = list(ICD_Chapter_Flat = "12;9"), inp = list(ICD_Chapter_Flat = "9;5")
  ))
  expect_equal(no_outer$icd_chapter_flat, "12;9;5")

  mixed <- link_rules(rules_pair(
    ed = list(ICD_Chapter_Flat = ";12;"), inp = list(ICD_Chapter_Flat = "5")
  ))
  expect_equal(mixed$icd_chapter_flat, "12;5")

  # CCDDCategory_flat has always been united with the delimiter
  expect_equal(link_rules(rules_pair())$ccdd_category_flat,
               "GI;Pain;Overdose;Toxicology")
})

test_that("DeathIndicator is Yes when either record says so", {
  result <- link_rules(rules_pair(
    ed = list(DeathIndicator = "No"), inp = list(DeathIndicator = "Yes")
  ))
  expect_equal(result$death_indicator, "Yes")
})

# ---- lengths are recomputed from the merged text ----

test_that("length columns are recomputed from the merged text, separators included", {
  result <- link_rules(rules_pair(
    ed = list(ChiefComplaintOrig = "abdominal pain", CCOrig_Length = "14",
              DischargeDiagnosis = "R10.9", DD_Length = "5"),
    inp = list(ChiefComplaintOrig = "overdose", CCOrig_Length = "8",
               DischargeDiagnosis = "T40.6", DD_Length = "5")
  ))
  expect_equal(result$chief_complaint_orig, "abdominal pain; overdose")
  expect_equal(result$cc_orig_length, "24")
  expect_equal(result$discharge_diagnosis, "R10.9; T40.6")
  expect_equal(result$dd_length, "12")
})

test_that("a numeric length column stays numeric", {
  result <- link_rules(rules_pair(
    ed = list(ChiefComplaintOrig = "abdominal pain", CCOrig_Length = 14L),
    inp = list(ChiefComplaintOrig = "overdose", CCOrig_Length = 8L)
  ))
  expect_identical(result$cc_orig_length, 24L)
})

test_that("a length column without its source keeps the winner's value and warns", {
  fx <- rules_pair(
    ed = list(CCOrig_Length = "14"), inp = list(CCOrig_Length = "8")
  )
  expect_warning(
    result <- link_rules(fx),
    "not recomputed"
  )
  expect_equal(result$cc_orig_length, "14")
  expect_warning(link_rules(fx), "ChiefComplaintOrig")
})

test_that("no warning is raised when no length column is present or nothing is linked", {
  expect_no_warning(link_rules(rules_pair()))
  fx <- rules_pair(ed = list(CCOrig_Length = "14"), inp = list(CCOrig_Length = "8"))
  fx$ed_data$Visit_ID <- "V00000099"   # no longer the same visit: nothing linked
  expect_no_warning(link_rules(fx))
})

# ---- overrides, defaults and what does not change ----

test_that("merge_fields overrides one column and leaves the rest on the table", {
  result <- link_rules(
    rules_pair(ed = list(Age = NA_character_), inp = list(Age = "40")),
    merge_fields = c(Discharge_Disposition = "follow_severity")
  )
  # follow_severity: the text from the record that supplied the category
  expect_equal(result$discharge_disposition, "Admitted to hospital")
  expect_equal(result$age, "40")
})

test_that("prefer_primary keeps the primary row's value even when it is empty", {
  result <- link_rules(
    rules_pair(ed = list(Age = NA_character_), inp = list(Age = "40")),
    merge_fields = c(Age = "prefer_primary")
  )
  expect_true(is.na(result$age))
})

test_that("merge_fields = NULL is the default", {
  expect_null(formals(link_encounters)$merge_fields)
})

test_that("a record that is not linked is left exactly as it arrived", {
  fx <- rules_pair(ed = list(Age = "Unknown", Discharge_Disposition = "Left"))
  unlinked <- fx$ed_data
  unlinked$Visit_ID    <- "V00000077"
  unlinked$C_BioSense_ID <- "BS0000000077"
  fx$ed_data <- dplyr::bind_rows(fx$ed_data, unlinked)
  fx$inpatient_admission_data$Age <- "40"
  result <- link_rules(fx)
  lone <- result[result$visit_id == "V00000077", ]
  expect_equal(nrow(lone), 1L)
  expect_equal(lone$age, "Unknown")
  expect_equal(lone$discharge_disposition, "Left")
})

test_that("flags, C_Death and DispositionCategory still reflect the whole encounter", {
  result <- link_rules(make_readmit_merge_data())
  expect_equal(result$has_been_e, 1L)
  expect_equal(result$has_been_admitted, 1L)
  expect_equal(result$c_death, "Yes")
  expect_equal(result$disposition_category, "DECEASED")
})

# ---- the vectorised engine agrees with the one-episode-at-a-time functions ----

test_that("collapse_episodes() agrees with the scalar merge functions", {
  set.seed(42)
  n_ep   <- 40L
  pieces <- c(NA, "", "None", "a", "b", "c", "10", "2", "7")
  draw   <- function(n) sample(pieces, n, replace = TRUE)
  lists  <- c(NA, "", ";1;2;", ";2;3;", "2;3", "1", ";", "None", "chest pain",
              "pain", "Chest Pain.", "fall")
  rows_per_ep <- sample(2:3, n_ep, replace = TRUE)

  result <- tibble::tibble(
    .episode_id = rep(sprintf("1_%02d", seq_len(n_ep)), rows_per_ep),
    patient_class = unlist(lapply(rows_per_ep, function(k) {
      c("ED", c("Inpatient", "Direct Admit")[seq_len(k - 1L)])
    })),
    a = draw(sum(rows_per_ep)), b = draw(sum(rows_per_ep)),
    c = draw(sum(rows_per_ep)), d = draw(sum(rows_per_ep)),
    e = sample(lists, sum(rows_per_ep), replace = TRUE),
    f = sample(lists, sum(rows_per_ep), replace = TRUE),
    g = sample(lists, sum(rows_per_ep), replace = TRUE)
  )
  result$.episode_n_rows  <- rep(rows_per_ep, rows_per_ep)
  result$.index_encounter <- result$patient_class == "ED"

  merge_fields <- c(
    a = "prefer_informative", b = "prefer_primary", c = "earliest", d = "max",
    e = "union_delimited", f = "concat", g = "union_ccdd"
  )
  collapsed <- collapse_episodes(result, merge_fields, merge_delimiter = ";")

  for (ep in unique(result$.episode_id)) {
    rows    <- result[result$.episode_id == ep, ]
    primary <- which(rows$patient_class == "ED")[1L]
    got     <- collapsed[collapsed$.episode_id == ep, ]
    for (col in names(merge_fields)) {
      expected <- merge_field_value(
        values = rows[[col]], patient_classes = rows$patient_class,
        primary_value = rows[[col]][primary],
        strategy = merge_fields[[col]], delimiter = ";"
      )
      expect_identical(got[[col]], expected, info = paste(ep, col))
    }
  }
})

test_that("the scalar strategies behave as documented", {
  expect_equal(merge_prefer_informative(c(NA, "x", "y"), NA_character_), "x")
  expect_equal(merge_prefer_informative(c("p", "x"), "p"), "p")
  expect_true(is.na(merge_prefer_informative(c(NA_character_, "None"), NA_character_)))
  expect_true(is.na(merge_prefer_primary(NA_character_)))
  expect_equal(
    merge_earliest(c("2023-01-02 08:00:00", "2023-01-01 07:00:00"), "2023-01-02 08:00:00"),
    "2023-01-01 07:00:00"
  )
  expect_equal(merge_earliest(c("junk", NA), "junk"), "junk")
  expect_equal(merge_max(c("0", "1", NA), "0"), "1")
  expect_equal(merge_max(c(2L, 9L), 2L), 9L)
  expect_equal(merge_max(c("x", NA), "x"), "x")
})

test_that("Sex 'U' (unknown) does not hide a known sex on the other record", {
  result <- link_rules(rules_pair(ed = list(Sex = "U"), inp = list(Sex = "F")))
  expect_equal(result$sex, "F")
  kept <- link_rules(rules_pair(ed = list(Sex = "M"), inp = list(Sex = "F")))
  expect_equal(kept$sex, "M")
  # "U" is a real value in other columns
  other <- link_rules(rules_pair(
    ed = list(Triage_Level = "U"), inp = list(Triage_Level = "2")
  ))
  expect_equal(other$triage_level, "U; 2")
})

# ---- edge cases ----

test_that("contains_whole() rejects a value that is longer than the text", {
  expect_false(contains_whole("pain", "pain pain"))
  expect_true(contains_whole("severe chest pain", "chest pain"))
})

test_that("merge_earliest() reads Date and POSIXct values as they are", {
  days <- as.Date(c("2023-01-05", "2023-01-02"))
  expect_equal(merge_earliest(days, days[1]), days[2])
  times <- as.POSIXct(c("2023-01-05 10:00:00", "2023-01-05 09:00:00"), tz = "UTC")
  expect_equal(merge_earliest(times, times[1]), times[2])
})

test_that("a double length column stays double", {
  result <- link_rules(rules_pair(
    ed = list(ChiefComplaintOrig = "abdominal pain", CCOrig_Length = 14),
    inp = list(ChiefComplaintOrig = "overdose", CCOrig_Length = 8)
  ))
  expect_identical(result$cc_orig_length, 24)
})

test_that("a united list is NA when no record holds a value", {
  result <- link_rules(rules_pair(
    ed = list(ICD_Chapter_Flat = NA_character_),
    inp = list(ICD_Chapter_Flat = "")
  ))
  expect_true(is.na(result$icd_chapter_flat))
})

test_that("a text strategy chosen for a number turns that column into text", {
  result <- link_rules(
    rules_pair(ed = list(Custom_Score = 2), inp = list(Custom_Score = 7.5)),
    merge_fields = c(Custom_Score = "concat")
  )
  expect_equal(result$custom_score, "2; 7.5")
})

# ---- decisions from the review of the flagged rows (2026-11-18) ----

test_that("encounter-specific identifiers keep both records' values", {
  result <- link_rules(rules_pair(
    ed = list(Unique_Physician_Identifier = "ED-DOC-1",
              Insurance_Company_ID = "INS-A"),
    inp = list(Unique_Physician_Identifier = "WARD-DOC-9",
               Insurance_Company_ID = "INS-B")
  ))
  expect_equal(result$unique_physician_identifier, "ED-DOC-1; WARD-DOC-9")
  expect_equal(result$insurance_company_id, "INS-A; INS-B")

  # patient identifiers describe the patient, so they stay a single value
  same <- link_rules(rules_pair(
    ed = list(Medical_Record_Number = "MRN1"),
    inp = list(Medical_Record_Number = "MRN1x")
  ))
  expect_equal(same$medical_record_number, "MRN1")
})

test_that("Body_Mass_Index comes from the record that supplied the weight", {
  both <- link_rules(rules_pair(
    ed = list(Weight = "70", Body_Mass_Index = "22.1"),
    inp = list(Weight = "154", Body_Mass_Index = "47.0")
  ))
  expect_equal(c(both$weight, both$body_mass_index), c("70", "22.1"))

  # the ED record holds no weight, so both come from the inpatient record
  supplied <- link_rules(rules_pair(
    ed = list(Weight = NA_character_, Body_Mass_Index = "22.1"),
    inp = list(Weight = "154", Body_Mass_Index = "47.0")
  ))
  expect_equal(c(supplied$weight, supplied$body_mass_index), c("154", "47.0"))
})

test_that("the rule table records the reviewed decisions", {
  rule <- function(x) merge_field_table$strategy[match(x, merge_field_table$name)]
  expect_equal(rule("unique_physician_identifier"), "concat")
  expect_equal(rule("insurance_company_id"), "concat")
  expect_equal(rule("body_mass_index"), "follow")
  expect_equal(
    merge_field_table$follow[match("body_mass_index", merge_field_table$name)],
    "weight"
  )
  expect_equal(rule("dd_converted"), "concat")
})
