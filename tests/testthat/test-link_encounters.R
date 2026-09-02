
# test-link_encounters.R ----

test_that("link_encounters() aborts when inpatient_admission_data is omitted", {
  data <- make_essence_data(n = 5L)
  expect_error(link_encounters(data), "inpatient_admission_data")
})

test_that("link_encounters() aborts when inpatient_admission_data is explicitly NULL", {
  data <- make_essence_data(n = 5L)
  expect_error(
    link_encounters(data, inpatient_admission_data = NULL),
    "inpatient_admission_data"
  )
})

test_that("link_encounters() returns long-format data with patient_class", {
  data <- make_essence_data(n = 10L)
  result <- link_encounters(data, data[0L, ])
  expect_true("patient_class" %in% names(result))
})

test_that("link_encounters() adds episode metadata columns", {
  data <- make_essence_data(n = 5L)
  result <- link_encounters(data, data[0L, ])
  expect_true(all(c(".episode_id", ".episode_n_rows", ".index_encounter") %in%
                  names(result)))
})

test_that("link_encounters() produces two rows for ED+Admitted visits in long format", {
  data <- make_essence_data(n = 3L) |>
    dplyr::mutate(HasBeenAdmitted = 1L)
  result <- link_encounters(data, data[0L, ], return_format = "long")
  # Each visit has HasBeenE = 1 and HasBeenAdmitted = 1 -> 2 rows each
  expect_equal(nrow(result), 6L)
})

test_that("link_encounters() aborts without HasBeenE", {
  data <- make_essence_data(n = 5L) |>
    dplyr::select(-HasBeenE)
  expect_error(link_encounters(data, data[0L, ]), "HasBeenE")
})

test_that("link_encounters() aborts without HasBeenAdmitted or HasBeenI", {
  data <- make_essence_data(n = 5L) |>
    dplyr::select(-HasBeenAdmitted)
  expect_error(link_encounters(data, data[0L, ]), "HasBeenAdmitted")
})

test_that("link_encounters() removes HasBeenE=1 rows from inpatient_admission_data", {
  ed_data        <- make_essence_data(n = 5L)
  inpatient_data <- make_essence_data(n = 3L) |>
    dplyr::mutate(HasBeenE = c(1L, 0L, 0L))
  expect_message(
    link_encounters(ed_data, inpatient_data),
    "HasBeenE = 1"
  )
})

test_that("link_encounters() produces one ED row per visit when HasBeenAdmitted = 0", {
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(HasBeenAdmitted = 0L)
  result <- link_encounters(data, data[0L, ])
  expect_true(all(result$patient_class == "ED"))
  expect_equal(nrow(result), 5L)
})

test_that("link_encounters() preserves true has_been_e/has_been_admitted on an Admitted->ED escalation entirely within ed_data", {
  data <- make_essence_data(n = 3L) |>
    dplyr::mutate(HasBeenAdmitted = 1L)
  result <- link_encounters(data, data[0L, ])
  escalated <- dplyr::filter(result, .episode_n_rows == 2L)
  expect_true(nrow(escalated) > 0L)
  expect_false(any(is.na(escalated$has_been_e)))
  expect_false(any(is.na(escalated$has_been_admitted)))
  expect_true(all(escalated$has_been_e == 1L))
  expect_true(all(escalated$has_been_admitted == 1L))
})

test_that("link_encounters() correctly reconciles has_been_e = 1 (not 0) on a merged continuity-break episode", {
  fixture <- make_readmit_merge_data()
  result  <- suppressMessages(
    link_encounters(fixture$ed_data, fixture$inpatient_admission_data)
  )
  expect_equal(result$has_been_e, 1L)
  expect_equal(result$has_been_admitted, 1L)
})

test_that("link_encounters() .index_encounter = TRUE on ED row of multi-class episodes in long format", {
  data <- make_essence_data(n = 3L) |>
    dplyr::mutate(HasBeenAdmitted = 1L)
  result <- link_encounters(data, data[0L, ], return_format = "long")
  multi_class   <- dplyr::filter(result, .episode_n_rows > 1L)
  ed_rows       <- dplyr::filter(multi_class, patient_class == "ED")
  admitted_rows <- dplyr::filter(multi_class, patient_class == "Admitted")
  expect_true(all(ed_rows$.index_encounter))
  expect_false(any(admitted_rows$.index_encounter))
})

test_that("link_encounters() .patient_class_sequence breaks ties alphabetically when classes share one C_Visit_Date_Time", {
  data <- make_essence_data(n = 3L) |>
    dplyr::mutate(HasBeenAdmitted = 1L)
  result <- link_encounters(data, data[0L, ])
  multi_rows <- dplyr::filter(result, .episode_n_rows > 1L)
  # ED and Admitted come from the same row/timestamp here, so they tie and
  # fall back to alphabetical order as the tiebreak.
  expect_true(all(multi_rows$.patient_class_sequence == "Admitted->ED"))
})

test_that("link_encounters() .patient_class_sequence reflects true order via C_Visit_Date_Time when the direct admit precedes the ED record", {
  ed_row <- tibble::tibble(
    HospitalName      = "Central Medical Center",
    Visit_ID          = "V00000001",
    HasBeenE          = 1L,
    HasBeenAdmitted   = 0L,
    C_Visit_Date_Time = as.POSIXct("2023-01-01 08:00:00")
  )
  direct_row <- tibble::tibble(
    HospitalName      = "Central Medical Center",
    Visit_ID          = "V00000001",
    HasBeenE          = 0L,
    HasBeenAdmitted   = 1L,
    C_Visit_Date_Time = as.POSIXct("2023-01-01 06:00:00")
  )
  result <- suppressMessages(
    link_encounters(ed_row, direct_row, return_format = "long")
  )
  expect_true(all(result$.patient_class_sequence == "Direct Admit->ED"))
})

test_that("link_encounters() .patient_class_sequence uses C_Patient_Class_MDT_Updates to order classes within one record", {
  data <- tibble::tibble(
    HospitalName                 = "Central Medical Center",
    Visit_ID                     = "V00000001",
    C_Patient_Class_List         = "EI",
    C_Patient_Class_MDT_Updates  =
      "{1};2023-01-01 10:00:00.000;|{2};2023-01-01 08:00:00.000;"
  )
  result <- suppressMessages(
    link_encounters(data, data[0L, ], return_format = "long")
  )
  # position 2 ("I") was assigned at 08:00, before position 1 ("E") at 10:00
  expect_true(all(result$.patient_class_sequence == "Inpatient->ED"))
})

test_that("link_encounters() .patient_class_sequence falls back to Date+Time when C_Visit_Date_Time is absent", {
  ed_row <- tibble::tibble(
    HospitalName    = "Central Medical Center",
    Visit_ID        = "V00000001",
    HasBeenE        = 1L,
    HasBeenAdmitted = 0L,
    Date            = as.Date("2023-01-01"),
    Time            = "09:00:00"
  )
  direct_row <- tibble::tibble(
    HospitalName    = "Central Medical Center",
    Visit_ID        = "V00000001",
    HasBeenE        = 0L,
    HasBeenAdmitted = 1L,
    Date            = as.Date("2023-01-01"),
    Time            = "07:00:00"
  )
  result <- suppressMessages(
    link_encounters(ed_row, direct_row, return_format = "long")
  )
  expect_true(all(result$.patient_class_sequence == "Direct Admit->ED"))
})

test_that("link_encounters() warns and falls back to alphabetical order when no timestamp field is usable", {
  data <- tibble::tibble(
    HospitalName    = "Central Medical Center",
    Visit_ID        = "V00000001",
    HasBeenE        = 1L,
    HasBeenAdmitted = 1L
  )
  expect_warning(
    result <- suppressMessages(link_encounters(data, data[0L, ], return_format = "long")),
    "chronological ordering"
  )
  expect_true(all(result$.patient_class_sequence == "Admitted->ED"))
})

test_that("link_encounters() parses a 3-class C_Patient_Class_MDT_Updates value in list order", {
  data <- tibble::tibble(
    HospitalName                 = "Central Medical Center",
    Visit_ID                     = "V00000001",
    C_Patient_Class_List         = "BEI",
    C_Patient_Class_MDT_Updates  = paste0(
      "{1};2026-06-08 16:38:09.000;",
      "|{2};2026-06-08 21:23:16.000;",
      "|{3};2026-06-08 21:29:51.000;"
    )
  )
  result <- suppressMessages(link_encounters(data, data[0L, ], return_format = "long"))
  expect_true(all(result$.patient_class_sequence == "Obstetrics->ED->Inpatient"))
})

test_that("link_encounters() falls back to a position's C_Visit_Date_Time when its MDT segment is missing", {
  data <- tibble::tibble(
    HospitalName                 = "Central Medical Center",
    Visit_ID                     = "V00000001",
    C_Patient_Class_List         = "EI",
    # Only position 1 ("E") has a segment -- position 2 ("I") has none
    C_Patient_Class_MDT_Updates  = "{1};2023-01-01 10:00:00.000;",
    C_Visit_Date_Time            = as.POSIXct("2023-01-01 09:00:00")
  )
  result <- suppressMessages(link_encounters(data, data[0L, ], return_format = "long"))
  expect_true("patient_class" %in% names(result))
  expect_false(any(is.na(result$.patient_class_sequence)))
})

test_that("link_encounters() warns and falls back when C_Patient_Class_MDT_Updates doesn't match the expected format", {
  data <- tibble::tibble(
    HospitalName                = "Central Medical Center",
    Visit_ID                    = "V00000001",
    C_Patient_Class_List        = "EI",
    C_Patient_Class_MDT_Updates = "not-a-date,also-not-a-date",
    C_Visit_Date_Time           = as.POSIXct("2023-01-01 09:00:00")
  )
  expect_warning(
    result <- suppressMessages(link_encounters(data, data[0L, ], return_format = "long")),
    "could not be parsed"
  )
  expect_false(any(is.na(result$.patient_class_sequence)))
})

test_that("link_encounters() parses ISO 8601 'T'-separated timestamps inside C_Patient_Class_MDT_Updates segments", {
  data <- tibble::tibble(
    HospitalName                = "Central Medical Center",
    Visit_ID                    = "V00000001",
    C_Patient_Class_List        = "EI",
    C_Patient_Class_MDT_Updates =
      "{1};2023-01-01T10:00:00;|{2};2023-01-01T08:00:00;"
  )
  result <- suppressMessages(link_encounters(data, data[0L, ], return_format = "long"))
  expect_true(all(result$.patient_class_sequence == "Inpatient->ED"))
})

test_that("link_encounters() prefers HasBeenAdmitted over HasBeenI when both present", {
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(HasBeenI = sample(c(0L, 1L), 5L, replace = TRUE))
  expect_message(link_encounters(data, data[0L, ]), "HasBeenAdmitted")
})

test_that("link_encounters() assigns Direct Admit to inpatient_admission_data rows", {
  ed_data      <- make_essence_data(n = 5L)
  direct_data  <- make_essence_data(n = 3L) |>
    dplyr::mutate(
      Visit_ID = sprintf("V%08d", 101L:103L),
      HasBeenE = 0L
    )
  result       <- link_encounters(ed_data, direct_data)
  direct_rows  <- dplyr::filter(result, patient_class == "Direct Admit")
  expect_equal(nrow(direct_rows), 3L)
})

test_that("link_encounters() clean_names = FALSE returns data frame with expected columns", {
  data   <- make_essence_data(n = 5L)
  result <- link_encounters(data, data[0L, ], clean_names = FALSE)
  expect_s3_class(result, "data.frame")
  expect_true("patient_class"   %in% names(result))
  expect_true(".episode_id"     %in% names(result))
  expect_true(".index_encounter" %in% names(result))
})

test_that("link_encounters() uses C_Patient_Class_List when present and informs", {
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(C_Patient_Class_List = "E")
  expect_message(
    result <- link_encounters(data, data[0L, ]),
    "C_Patient_Class_List"
  )
  expect_true("patient_class" %in% names(result))
})

test_that("link_encounters() warns and retains NA patient_class for missing/empty C_Patient_Class_List values", {
  data <- tibble::tibble(
    HospitalName         = c("Central Medical Center", "Central Medical Center"),
    Visit_ID             = c("V00000001", "V00000002"),
    C_Patient_Class_List = c("E", NA_character_),
    C_Visit_Date_Time    = as.POSIXct(c("2023-01-01 08:00:00", "2023-01-01 09:00:00"))
  )
  expect_warning(
    result <- suppressMessages(
      link_encounters(data, data[0L, ], return_format = "long")
    ),
    "missing or empty"
  )
  expect_true(any(is.na(result$patient_class)))
})

test_that("link_encounters() C_Patient_Class_List code form maps to patient class labels in long format", {
  data <- make_essence_data(n = 3L) |>
    dplyr::mutate(C_Patient_Class_List = c("EI", "E", "D"))
  result <- suppressMessages(link_encounters(data, data[0L, ], return_format = "long"))
  expect_true("Inpatient"    %in% result$patient_class)
  expect_true("ED"           %in% result$patient_class)
  expect_true("Direct Admit" %in% result$patient_class)
})

test_that("link_encounters() C_Patient_Class_List label form maps to same patient class labels in long format", {
  data <- make_essence_data(n = 3L) |>
    dplyr::mutate(
      C_Patient_Class_List = c("Emergency,Inpatient", "Emergency", "Inpatient")
    )
  result <- suppressMessages(link_encounters(data, data[0L, ], return_format = "long"))
  expect_true("Inpatient" %in% result$patient_class)
  expect_true("ED"        %in% result$patient_class)
})

test_that("link_encounters() warns when HasBeenO = 1 visits are present", {
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(HasBeenO = c(1L, 0L, 0L, 0L, 0L))
  expect_warning(
    link_encounters(data, data[0L, ]),
    "Outpatient"
  )
})

test_that("link_encounters() verbose = FALSE suppresses HasBeenAdmitted-preferred message", {
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(HasBeenI = sample(c(0L, 1L), 5L, replace = TRUE))
  expect_no_message(link_encounters(data, data[0L, ], verbose = FALSE))
})

test_that("link_encounters() warns on HasBeenO regardless of verbose", {
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(HasBeenO = c(1L, 0L, 0L, 0L, 0L))
  expect_warning(
    link_encounters(data, data[0L, ], verbose = FALSE),
    "Outpatient"
  )
})

# merge strategy helper tests ----

test_that("merge_concat() appends new non-duplicate text to primary value", {
  result <- merge_concat(c("abdominal pain", "opioid overdose"), primary_value = "abdominal pain")
  expect_equal(result, "abdominal pain; opioid overdose")
})

test_that("merge_concat() does not duplicate text already present", {
  result <- merge_concat(c("abdominal pain", "abdominal pain"), primary_value = "abdominal pain")
  expect_equal(result, "abdominal pain")
})

test_that("merge_concat() falls back to primary_value when all values are NA/empty", {
  result <- merge_concat(c(NA_character_, ""), primary_value = "abdominal pain")
  expect_equal(result, "abdominal pain")
})

test_that("merge_union_delimited() unions unique delimited values", {
  result <- merge_union_delimited(c("GI;Pain", "Overdose;Toxicology"), delimiter = ";")
  expect_equal(result, "GI;Pain;Overdose;Toxicology")
})

test_that("merge_union_delimited() drops duplicate values across rows", {
  result <- merge_union_delimited(c("GI;Pain", "Pain;Overdose"), delimiter = ";")
  expect_equal(result, "GI;Pain;Overdose")
})

test_that("merge_union_ccdd() unions CC and DD halves separately", {
  result <- merge_union_ccdd(
    c("abdominal pain|R10.9", "opioid overdose|T40.6"),
    delimiter = ";"
  )
  expect_equal(result, "abdominal pain;opioid overdose|R10.9;T40.6")
})

test_that("merge_union_ccdd() drops duplicate values within each half", {
  result <- merge_union_ccdd(
    c("abdominal pain|R10.9", "abdominal pain;opioid overdose|R10.9;T40.6"),
    delimiter = ";"
  )
  expect_equal(result, "abdominal pain;opioid overdose|R10.9;T40.6")
})

test_that("merge_union_delimited() returns NA when all values are NA/empty", {
  result <- merge_union_delimited(c(NA_character_, ""), delimiter = ";")
  expect_true(is.na(result))
})

test_that("merge_union_ccdd() returns NA when all values are NA/empty", {
  result <- merge_union_ccdd(c(NA_character_, ""), delimiter = ";")
  expect_true(is.na(result))
})

test_that("merge_union_ccdd() handles a value with an empty CC half", {
  result <- merge_union_ccdd("|R10.9", delimiter = ";")
  expect_equal(result, "|R10.9")
})

test_that("merge_union_ccdd() handles a value with no pipe (empty DD half)", {
  result <- merge_union_ccdd("abdominal pain", delimiter = ";")
  expect_equal(result, "abdominal pain|")
})

test_that("merge_prefer_yes() returns Yes when any value is Yes", {
  result <- merge_prefer_yes(c("No", "Yes"), primary_value = "No")
  expect_equal(result, "Yes")
})

test_that("merge_prefer_yes() falls back to primary_value when no value is Yes", {
  result <- merge_prefer_yes(c("No", "No"), primary_value = "No")
  expect_equal(result, "No")
})

test_that("merge_prefer_admission() returns value from the admission-class row", {
  result <- merge_prefer_admission(
    values          = c("Discharged to home", "Expired"),
    patient_classes = c("ED", "Direct Admit"),
    primary_value   = "Discharged to home"
  )
  expect_equal(result, "Expired")
})

test_that("merge_prefer_admission() falls back to primary_value when no admission-class row exists", {
  result <- merge_prefer_admission(
    values          = c("Discharged to home", "Observed"),
    patient_classes = c("ED", "Observation"),
    primary_value   = "Discharged to home"
  )
  expect_equal(result, "Discharged to home")
})

test_that("merge_field_value() dispatches to the correct strategy", {
  result <- merge_field_value(
    values          = c("No", "Yes"),
    patient_classes = c("ED", "Direct Admit"),
    primary_value   = "No",
    strategy        = "prefer_yes",
    delimiter       = ";"
  )
  expect_equal(result, "Yes")
})

test_that("merge_field_value() aborts on an unknown strategy", {
  expect_error(
    merge_field_value(
      values = "x", patient_classes = "ED", primary_value = "x",
      strategy = "not_a_real_strategy", delimiter = ";"
    ),
    "Unknown merge strategy"
  )
})

# parse_mdt_updates() ----

test_that("parse_mdt_updates() returns all NA when mdt_str is NA", {
  result <- parse_mdt_updates(NA_character_, n_classes = 2L)
  expect_true(all(is.na(result)))
})

test_that("parse_mdt_updates() returns all NA when mdt_str is an empty string", {
  result <- parse_mdt_updates("", n_classes = 2L)
  expect_true(all(is.na(result)))
})

test_that("parse_mdt_updates() skips empty segments between pipe delimiters", {
  result <- parse_mdt_updates(
    "{1};2023-01-01 10:00:00.000;||{2};2023-01-01 08:00:00.000;",
    n_classes = 2L
  )
  expect_equal(result[1], "2023-01-01 10:00:00.000")
  expect_equal(result[2], "2023-01-01 08:00:00.000")
})

# safe_as_posixct() ----

test_that("safe_as_posixct() parses standard space-separated timestamps", {
  result <- safe_as_posixct("2023-01-01 08:00:00")
  expect_equal(result, as.POSIXct("2023-01-01 08:00:00"))
})

test_that("safe_as_posixct() parses ISO 8601 'T'-separated timestamps", {
  result <- safe_as_posixct("2023-01-01T08:00:00")
  expect_equal(result, as.POSIXct("2023-01-01 08:00:00"))
})

test_that("safe_as_posixct() strips a trailing 'Z' before parsing", {
  result <- safe_as_posixct("2023-01-01T08:00:00Z")
  expect_equal(result, as.POSIXct("2023-01-01 08:00:00"))
})

test_that("safe_as_posixct() parses US-style m/d/Y timestamps with seconds", {
  result <- safe_as_posixct("01/15/2023 08:00:00")
  expect_equal(result, as.POSIXct("2023-01-15 08:00:00"))
})

test_that("safe_as_posixct() parses US-style m/d/Y timestamps without seconds", {
  # Regression test: this format previously fell through to the
  # date-only "%m/%d/%Y" pattern, which matches only the date prefix and
  # silently discards the trailing time -- producing midnight instead of
  # erroring or returning NA. Asserting the exact time (not just
  # non-NA) is what would have caught that.
  result <- safe_as_posixct("01/15/2023 08:00")
  expect_equal(result, as.POSIXct("2023-01-15 08:00:00"))
})

test_that("safe_as_posixct() parses US-style m/d/Y date-only values", {
  result <- safe_as_posixct("01/15/2023")
  expect_equal(result, as.POSIXct("2023-01-15"))
})

test_that("safe_as_posixct() returns NA instead of erroring on unparseable values", {
  expect_no_error(result <- safe_as_posixct("not-a-date"))
  expect_true(is.na(result))
})

test_that("safe_as_posixct() returns NA for NA and empty string input", {
  result <- safe_as_posixct(c(NA_character_, ""))
  expect_true(all(is.na(result)))
})

test_that("safe_as_posixct() passes already-POSIXct input through unchanged", {
  input <- as.POSIXct("2023-01-01 08:00:00")
  expect_equal(safe_as_posixct(input), input)
})

test_that("safe_as_posixct() handles a mix of valid and unparseable values in one vector", {
  result <- safe_as_posixct(c("2023-01-01T08:00:00", "garbage"))
  expect_equal(result[1], as.POSIXct("2023-01-01 08:00:00"))
  expect_true(is.na(result[2]))
})

# compute_patient_class_sequence() ----

test_that("compute_patient_class_sequence() orders classes by ascending class_time", {
  result <- compute_patient_class_sequence(
    patient_class = c("ED", "Direct Admit"),
    class_time    = as.POSIXct(c("2023-01-01 08:00:00", "2023-01-01 06:00:00"))
  )
  expect_equal(result, "Direct Admit->ED")
})

test_that("compute_patient_class_sequence() breaks ties alphabetically", {
  result <- compute_patient_class_sequence(
    patient_class = c("ED", "Admitted"),
    class_time    = as.POSIXct(c("2023-01-01 08:00:00", "2023-01-01 08:00:00"))
  )
  expect_equal(result, "Admitted->ED")
})

test_that("compute_patient_class_sequence() falls back to alphabetical order when all class_time are NA", {
  result <- compute_patient_class_sequence(
    patient_class = c("ED", "Direct Admit"),
    class_time    = as.POSIXct(c(NA, NA))
  )
  expect_equal(result, "Direct Admit->ED")
})

test_that("compute_patient_class_sequence() returns NA when all patient_class values are NA", {
  result <- compute_patient_class_sequence(
    patient_class = c(NA_character_, NA_character_),
    class_time    = as.POSIXct(c(NA, NA))
  )
  expect_true(is.na(result))
})

test_that("compute_patient_class_sequence() puts classes with no timestamp last when some classes have one", {
  result <- compute_patient_class_sequence(
    patient_class = c("ED", "Direct Admit"),
    class_time    = as.POSIXct(c("2023-01-01 08:00:00", NA))
  )
  expect_equal(result, "ED->Direct Admit")
})

test_that("compute_patient_class_sequence() collapses repeated classes to one entry", {
  result <- compute_patient_class_sequence(
    patient_class = c("ED", "ED", "Direct Admit"),
    class_time    = as.POSIXct(c("2023-01-01 08:00:00", "2023-01-01 09:00:00", "2023-01-01 10:00:00"))
  )
  expect_equal(result, "ED->Direct Admit")
})

# primary row selection and episode collapsing tests ----

test_that("pick_primary_row_index() returns the index of the ED row when present", {
  expect_equal(pick_primary_row_index(c("Direct Admit", "ED")), 2L)
})

test_that("pick_primary_row_index() returns 1 when no ED row exists", {
  expect_equal(pick_primary_row_index(c("Direct Admit", "Observation")), 1L)
})

test_that("collapse_episode() reconciles has_been_ flags via max", {
  episode <- tibble::tibble(
    patient_class      = c("ED", "Direct Admit"),
    has_been_e         = c(1L, 0L),
    has_been_admitted  = c(0L, 1L)
  )
  result <- collapse_episode(episode, merge_fields = character(0), merge_delimiter = ";")
  expect_equal(nrow(result), 1L)
  expect_equal(result$has_been_e, 1L)
  expect_equal(result$has_been_admitted, 1L)
})

test_that("collapse_episode() applies merge_fields strategies", {
  episode <- tibble::tibble(
    patient_class = c("ED", "Direct Admit"),
    c_death       = c("No", "Yes"),
    ccdd          = c("abdominal pain|R10.9", "opioid overdose|T40.6")
  )
  result <- collapse_episode(
    episode,
    merge_fields    = c(c_death = "prefer_yes", ccdd = "union_ccdd"),
    merge_delimiter = ";"
  )
  expect_equal(result$c_death, "Yes")
  expect_equal(result$ccdd, "abdominal pain;opioid overdose|R10.9;T40.6")
})

test_that("collapse_episode() passes through untouched columns from the primary row", {
  episode <- tibble::tibble(
    patient_class = c("ED", "Direct Admit"),
    hospital_name = c("Central Medical Center", "Central Medical Center"),
    visit_id      = c("V00000001", "V00000001"),
    unrelated_col = c("ed_value", "admit_value")
  )
  result <- collapse_episode(episode, merge_fields = character(0), merge_delimiter = ";")
  expect_equal(result$unrelated_col, "ed_value")
})

test_that("collapse_episode() handles a single-row episode as a no-op", {
  episode <- tibble::tibble(patient_class = "ED", c_death = "No")
  result <- collapse_episode(
    episode,
    merge_fields    = c(c_death = "prefer_yes"),
    merge_delimiter = ";"
  )
  expect_equal(nrow(result), 1L)
  expect_equal(result$c_death, "No")
})

test_that("collapse_episode() folds across more than 2 rows without error", {
  episode <- tibble::tibble(
    patient_class = c("ED", "Direct Admit", "Observation"),
    has_been_e    = c(1L, 0L, 0L),
    c_death       = c("No", "No", "Yes")
  )
  result <- collapse_episode(
    episode,
    merge_fields    = c(c_death = "prefer_yes"),
    merge_delimiter = ";"
  )
  expect_equal(nrow(result), 1L)
  expect_equal(result$has_been_e, 1L)
  expect_equal(result$c_death, "Yes")
})

# integration tests: merge behavior via full link_encounters() calls ----

test_that("link_encounters() collapses ED + Direct Admit rows into one row by default", {
  fixture <- make_readmit_merge_data()
  result  <- suppressMessages(
    link_encounters(fixture$ed_data, fixture$inpatient_admission_data)
  )
  expect_equal(nrow(result), 1L)
})

test_that("link_encounters() reconciles has_been_admitted via max in collapsed output", {
  fixture <- make_readmit_merge_data()
  result  <- suppressMessages(
    link_encounters(fixture$ed_data, fixture$inpatient_admission_data)
  )
  expect_equal(result$has_been_admitted, 1L)
})

test_that("link_encounters() applies prefer_yes to c_death in collapsed output", {
  fixture <- make_readmit_merge_data()
  result  <- suppressMessages(
    link_encounters(fixture$ed_data, fixture$inpatient_admission_data)
  )
  expect_equal(result$c_death, "Yes")
})

test_that("link_encounters() applies prefer_admission to discharge_disposition in collapsed output", {
  fixture <- make_readmit_merge_data()
  result  <- suppressMessages(
    link_encounters(fixture$ed_data, fixture$inpatient_admission_data)
  )
  expect_equal(result$discharge_disposition, "Expired")
  expect_equal(result$disposition_category, "Died")
})

test_that("link_encounters() applies union_ccdd to ccdd in collapsed output", {
  fixture <- make_readmit_merge_data()
  result  <- suppressMessages(
    link_encounters(fixture$ed_data, fixture$inpatient_admission_data)
  )
  expect_equal(result$ccdd, "abdominal pain;opioid overdose|R10.9;T40.6")
})

test_that("link_encounters() applies union_delimited to ccdd_category_flat in collapsed output", {
  fixture <- make_readmit_merge_data()
  result  <- suppressMessages(
    link_encounters(fixture$ed_data, fixture$inpatient_admission_data)
  )
  expect_equal(result$ccdd_category_flat, "GI;Pain;Overdose;Toxicology")
})

test_that("link_encounters() collapsed output's patient_class reflects the primary (ED) row", {
  fixture <- make_readmit_merge_data()
  result  <- suppressMessages(
    link_encounters(fixture$ed_data, fixture$inpatient_admission_data)
  )
  expect_equal(result$patient_class, "ED")
})

test_that("link_encounters() return_format = 'long' still shows both original rows for the merge fixture", {
  fixture <- make_readmit_merge_data()
  result  <- suppressMessages(
    link_encounters(
      fixture$ed_data, fixture$inpatient_admission_data,
      return_format = "long"
    )
  )
  expect_equal(nrow(result), 2L)
})

test_that("link_encounters() custom merge_fields strategy is respected", {
  fixture <- make_readmit_merge_data()
  result  <- suppressMessages(
    link_encounters(
      fixture$ed_data, fixture$inpatient_admission_data,
      merge_fields = c(C_Death = "concat")
    )
  )
  expect_equal(result$c_death, "No; Yes")
})

test_that("link_encounters() preserves true has_been_ values (not NA or -Inf) for ED-only episodes with no direct-admit match (two-pull)", {
  ed_data <- make_essence_data(n = 5L) |>
    dplyr::mutate(HasBeenAdmitted = 0L)
  direct_data <- make_essence_data(n = 2L) |>
    dplyr::mutate(
      Visit_ID = sprintf("V%08d", 101L:102L),
      HasBeenE = 0L
    )
  result <- suppressMessages(link_encounters(ed_data, direct_data))
  ed_only <- dplyr::filter(result, patient_class == "ED", .episode_n_rows == 1L)
  expect_true(nrow(ed_only) > 0L)
  expect_false(any(is.infinite(ed_only$has_been_admitted)))
  expect_false(any(is.na(ed_only$has_been_admitted)))
  expect_true(all(ed_only$has_been_e == 1L))
  expect_true(all(ed_only$has_been_admitted == 0L))
})

test_that("link_encounters() .index_encounter is TRUE in collapsed output for a multi-row episode with no ED row", {
  data <- make_essence_data(n = 1L) |>
    dplyr::mutate(C_Patient_Class_List = "ID")
  result <- suppressMessages(link_encounters(data, data[0L, ]))
  expect_equal(nrow(result), 1L)
  expect_true(result$.index_encounter)
})

test_that("link_encounters() aborts on an invalid merge strategy", {
  fixture <- make_readmit_merge_data()
  expect_error(
    link_encounters(
      fixture$ed_data, fixture$inpatient_admission_data,
      merge_fields = c(C_Death = "not_a_real_strategy")
    ),
    "Invalid merge strategy"
  )
})
