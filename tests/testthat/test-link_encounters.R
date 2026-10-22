
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

test_that("link_encounters() honors an explicitly supplied facility_col over the Hospital preference", {
  data <- make_essence_data(n = 5L)
  result <- suppressMessages(
    link_encounters(data, data[0L, ], facility_col = HospitalName)
  )
  expect_true(any(startsWith(result$.episode_id, data$HospitalName[1])))
})

test_that("link_encounters() adds episode metadata columns", {
  data <- make_essence_data(n = 5L)
  result <- link_encounters(data, data[0L, ])
  expect_true(all(
    c(".episode_id", ".episode_n_rows", ".index_encounter") %in% names(result)
  ))
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

test_that("link_encounters() never merges episodes that share a missing visit_id into one", {
  # Regression test: `.episode_id` used to be built as paste(fac, visit,
  # sep = "_") with no NA handling, so rows sharing a missing Visit_ID
  # collapsed to the identical string "1001_NA" and were merged into one
  # episode by the downstream `.by = .episode_id` reconciliation -- even
  # though a missing value means the row's true identity is unknown, not
  # confirmed to match another row with a missing value.
  data <- tibble::tibble(
    Hospital        = c(1001L, 1001L, 1001L),
    Visit_ID        = c(NA, NA, "V1"),
    HasBeenE        = c(1L, 1L, 1L),
    HasBeenAdmitted = c(0L, 0L, 0L)
  )
  result <- suppressWarnings(suppressMessages(
    link_encounters(data, data[0L, ])
  ))
  expect_equal(nrow(result), 3L)
  expect_equal(dplyr::n_distinct(result$.episode_id), 3L)
})

test_that("link_encounters() merges a split episode via fallback_visit_col when visit_id is missing on both sides", {
  # Regression test for a real production case (essence-sql-etl, ~9 years
  # of KY ED/direct-admit data): an ED row and a direct-admit row from the
  # same real episode can both have a missing Visit_ID, but still share
  # C_BioSense_ID. The NA-safety fix above is correct in general (two rows
  # sharing a missing key are not necessarily the same visit), but here
  # C_BioSense_ID is independent evidence that they ARE the same episode --
  # without fallback_visit_col, link_encounters() has no way to use it and
  # leaves both rows unmatched.
  ed <- tibble::tibble(
    Hospital        = 1001L,
    Visit_ID        = NA_character_,
    C_BioSense_ID   = "BS123",
    HasBeenE        = 1L,
    HasBeenAdmitted = 0L
  )
  inp <- tibble::tibble(
    Hospital        = 1001L,
    Visit_ID        = NA_character_,
    C_BioSense_ID   = "BS123",
    HasBeenE        = 0L,
    HasBeenAdmitted = 1L
  )
  result <- suppressWarnings(suppressMessages(
    link_encounters(ed, inp, fallback_visit_col = C_BioSense_ID)
  ))
  expect_equal(nrow(result), 1L)
  expect_equal(result$.episode_n_rows, 2L)
})

test_that("link_encounters() default (no fallback_visit_col) still leaves that same split episode unmatched", {
  ed <- tibble::tibble(
    Hospital        = 1001L,
    Visit_ID        = NA_character_,
    C_BioSense_ID   = "BS123",
    HasBeenE        = 1L,
    HasBeenAdmitted = 0L
  )
  inp <- tibble::tibble(
    Hospital        = 1001L,
    Visit_ID        = NA_character_,
    C_BioSense_ID   = "BS123",
    HasBeenE        = 0L,
    HasBeenAdmitted = 1L
  )
  result <- suppressWarnings(suppressMessages(link_encounters(ed, inp)))
  expect_equal(nrow(result), 2L)
})

test_that("link_encounters() fallback_visit_col does not match rows whose fallback value is also missing", {
  ed <- tibble::tibble(
    Hospital        = 1001L,
    Visit_ID        = NA_character_,
    C_BioSense_ID   = NA_character_,
    HasBeenE        = 1L,
    HasBeenAdmitted = 0L
  )
  inp <- tibble::tibble(
    Hospital        = 1001L,
    Visit_ID        = NA_character_,
    C_BioSense_ID   = NA_character_,
    HasBeenE        = 0L,
    HasBeenAdmitted = 1L
  )
  result <- suppressWarnings(suppressMessages(
    link_encounters(ed, inp, fallback_visit_col = C_BioSense_ID)
  ))
  expect_equal(nrow(result), 2L)
})

test_that("link_encounters() fallback_visit_col does not affect rows with a real visit_id", {
  ed <- tibble::tibble(
    Hospital        = c(1001L, 1001L),
    Visit_ID        = c("V1", "V2"),
    C_BioSense_ID   = c("BS_SAME", "BS_SAME"),
    HasBeenE        = c(1L, 1L),
    HasBeenAdmitted = c(0L, 0L)
  )
  result <- suppressWarnings(suppressMessages(
    link_encounters(ed, ed[0L, ], fallback_visit_col = C_BioSense_ID)
  ))
  expect_equal(nrow(result), 2L)
  expect_equal(dplyr::n_distinct(result$.episode_id), 2L)
})

test_that("link_encounters() informs when fallback_visit_col recovers a match", {
  ed <- tibble::tibble(
    Hospital        = 1001L,
    Visit_ID        = NA_character_,
    C_BioSense_ID   = "BS123",
    HasBeenE        = 1L,
    HasBeenAdmitted = 0L
  )
  inp <- tibble::tibble(
    Hospital        = 1001L,
    Visit_ID        = NA_character_,
    C_BioSense_ID   = "BS123",
    HasBeenE        = 0L,
    HasBeenAdmitted = 1L
  )
  expect_message(
    suppressWarnings(link_encounters(ed, inp, fallback_visit_col = C_BioSense_ID)),
    "matched another row via"
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
  expect_gt(nrow(escalated), 0L)
  expect_false(anyNA(escalated$has_been_e))
  expect_false(anyNA(escalated$has_been_admitted))
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
  expect_false(anyNA(result$.patient_class_sequence))
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
  expect_false(anyNA(result$.patient_class_sequence))
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
  expect_true(anyNA(result$patient_class))
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

test_that("link_encounters() informs (not warns) when HasBeenO = 1 visits are present", {
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(HasBeenO = c(1L, 0L, 0L, 0L, 0L))
  expect_message(
    link_encounters(data, data[0L, ]),
    "Outpatient"
  )
  expect_no_warning(link_encounters(data, data[0L, ]))
})

test_that("link_encounters() verbose = FALSE suppresses HasBeenAdmitted-preferred message", {
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(HasBeenI = sample(c(0L, 1L), 5L, replace = TRUE))
  expect_no_message(link_encounters(data, data[0L, ], verbose = FALSE))
})

test_that("link_encounters() verbose = FALSE suppresses the HasBeenO message", {
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(HasBeenO = c(1L, 0L, 0L, 0L, 0L))
  expect_no_message(link_encounters(data, data[0L, ], verbose = FALSE))
})

test_that("link_encounters() preserves true HasBeenI values (not NA) when HasBeenAdmitted is also present", {
  # Regression test: HasBeenI used to be dropped outright from ed_data to
  # keep it out of the patient_class pivot, which discarded its real 0/1
  # values for every ed_data row -- they only survived on rows sourced
  # from inpatient_admission_data after bind_rows(), showing as NA
  # everywhere else. HasBeenI should now be excluded from the pivot without
  # losing its values.
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(HasBeenI = c(1L, 0L, 1L, 0L, 1L))
  result <- suppressMessages(link_encounters(data, data[0L, ]))
  expect_false(anyNA(result$has_been_i))
  expect_equal(sort(result$has_been_i), sort(data$HasBeenI))
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

# episode_class_sequence() for a single episode ----

compute_patient_class_sequence <- function(patient_class, class_time) {
  episode_class_sequence(
    rep(1L, length(patient_class)), patient_class, class_time
  )[1L]
}

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

test_that("merge_concat() starts from the first value when the primary value is missing", {
  expect_identical(merge_concat(c("a", "b"), NA_character_), "a; b")
  expect_identical(merge_concat(c("a", "b"), ""), "a; b")
})

test_that("pick_primary_row_index() returns 1 when no ED row exists", {
  expect_equal(pick_primary_row_index(c("Direct Admit", "Observation")), 1L)
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

test_that("link_encounters() takes columns outside merge_fields from the primary (ED) row", {
  fixture <- make_readmit_merge_data()
  result  <- suppressMessages(
    link_encounters(fixture$ed_data, fixture$inpatient_admission_data)
  )
  # c_bio_sense_id differs between the ED and direct-admit rows and is not a
  # merge field, so the primary (ED) row's value must survive untouched
  expect_identical(result$c_bio_sense_id, "BS0000000001")
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
  expect_gt(nrow(ed_only), 0L)
  expect_false(any(is.infinite(ed_only$has_been_admitted)))
  expect_false(anyNA(ed_only$has_been_admitted))
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

# link_encounters() contract: link, never drop ----
# 1. an ED row with no inpatient counterpart, and a standalone inpatient
#    admission with no ED counterpart, are neither touched nor dropped;
# 2. only a HasBeenE = 1 row and a HasBeenE = 0 row sharing hospital x
#    visit_id are combined;
# 3. the combined row carries every HasBeen_ flag that is 1 on either side,
#    and no HasBeen_ value is ever NA.

make_contract_pulls <- function() {
  ed <- tibble::tibble(
    Hospital = c(1001L, 1001L, 1001L, 1002L),
    Visit_ID = c("V1", "V2", "V3", "V1"),
    HasBeenE = 1L,
    HasBeenAdmitted = c(0L, 1L, 0L, 0L),
    CCDD = c("cc_a|dd_a", "cc_b|dd_b", "cc_c|dd_c", "cc_d|dd_d"),
    C_Death = "No",
    Discharge_Disposition = "Discharged",
    C_Visit_Date_Time = c(
      "2026-01-01 08:00:00", "2026-01-02 08:00:00",
      "2026-01-03 08:00:00", "2026-01-04 08:00:00"
    )
  )
  ip <- tibble::tibble(
    Hospital = c(1001L, 1001L, 1001L, 1001L),
    # V2 is also in the ED pull (HasBeenE = 1): a duplicate to remove.
    # V3 continues an ED visit: to be linked. V4/V5 are standalone.
    Visit_ID = c("V2", "V3", "V4", "V5"),
    HasBeenE = c(1L, 0L, 0L, 0L),
    HasBeenAdmitted = 1L,
    CCDD = c("cc_b|dd_b", "cc_x|dd_x", "cc_y|dd_y", "cc_z|dd_z"),
    C_Death = c("No", "Yes", "No", "No"),
    Discharge_Disposition = c("Discharged", "Expired", "Home", "Home"),
    C_Visit_Date_Time = c(
      "2026-01-02 08:00:00", "2026-01-03 20:00:00",
      "2026-01-05 08:00:00", "2026-01-06 08:00:00"
    )
  )
  list(ed = ed, ip = ip)
}

test_that("an ED row with no inpatient counterpart is neither changed nor dropped", {
  pulls  <- make_contract_pulls()
  result <- suppressMessages(link_encounters(pulls$ed, pulls$ip))

  v1 <- dplyr::filter(result, hospital == 1001L, visit_id == "V1")
  expect_equal(nrow(v1), 1L)
  expect_equal(v1$patient_class, "ED")
  expect_equal(v1$.episode_n_rows, 1L)
  expect_equal(v1$ccdd, "cc_a|dd_a")
  expect_equal(v1$c_death, "No")
  expect_equal(v1$discharge_disposition, "Discharged")
  expect_equal(c(v1$has_been_e, v1$has_been_admitted), c(1L, 0L))
  # same Visit_ID at a different hospital is a different visit
  v1_other <- dplyr::filter(result, hospital == 1002L, visit_id == "V1")
  expect_equal(nrow(v1_other), 1L)
  expect_equal(v1_other$ccdd, "cc_d|dd_d")
})

test_that("an ED row that escalated within the ED pull is kept once with both flags", {
  pulls  <- make_contract_pulls()
  result <- suppressMessages(link_encounters(pulls$ed, pulls$ip))
  v2 <- dplyr::filter(result, hospital == 1001L, visit_id == "V2")
  expect_equal(nrow(v2), 1L)
  expect_equal(c(v2$has_been_e, v2$has_been_admitted), c(1L, 1L))
})

test_that("standalone inpatient admissions are neither changed nor dropped", {
  pulls  <- make_contract_pulls()
  result <- suppressMessages(link_encounters(pulls$ed, pulls$ip))
  for (v in c("V4", "V5")) {
    row <- dplyr::filter(result, hospital == 1001L, visit_id == v)
    src <- dplyr::filter(pulls$ip, Visit_ID == v)
    expect_equal(nrow(row), 1L)
    expect_equal(row$patient_class, "Direct Admit")
    expect_equal(row$.episode_n_rows, 1L)
    expect_equal(row$ccdd, src$CCDD)
    expect_equal(row$c_death, src$C_Death)
    expect_equal(row$discharge_disposition, src$Discharge_Disposition)
    expect_equal(c(row$has_been_e, row$has_been_admitted), c(0L, 1L))
  }
})

test_that("only hospital x visit_id matches are linked, from HasBeenE = 1 and HasBeenE = 0 rows", {
  pulls  <- make_contract_pulls()
  result <- suppressMessages(link_encounters(pulls$ed, pulls$ip))

  # 4 distinct ED visits + 2 standalone admissions; the HasBeenE = 1 copy of
  # V2 in the inpatient pull is a duplicate and does not add a row
  expect_equal(nrow(result), 6L)
  # V2's ED + Admitted classes (one record) and V3's ED + Direct Admit
  # records are the multi-row episodes; V1 (x2), V4 and V5 are single-row
  expect_equal(sort(result$visit_id[result$.episode_n_rows > 1L]), c("V2", "V3"))
  expect_equal(sum(result$patient_class == "Direct Admit"), 2L)

  v3 <- dplyr::filter(result, hospital == 1001L, visit_id == "V3")
  expect_equal(nrow(v3), 1L)
  expect_equal(v3$.episode_n_rows, 2L)
  expect_equal(v3$patient_class, "ED")
  expect_equal(v3$.patient_class_sequence, "ED->Direct Admit")
})

test_that("a linked row combines clinical information and carries every flag that is 1", {
  pulls  <- make_contract_pulls()
  result <- suppressMessages(link_encounters(pulls$ed, pulls$ip))
  v3 <- dplyr::filter(result, hospital == 1001L, visit_id == "V3")

  # ED row had HasBeenAdmitted = 0, the admission row 1: the link carries 1
  expect_equal(c(v3$has_been_e, v3$has_been_admitted), c(1L, 1L))
  expect_equal(v3$ccdd, "cc_c;cc_x|dd_c;dd_x")
  expect_equal(v3$c_death, "Yes")
  expect_equal(v3$discharge_disposition, "Expired")
})

test_that("a HasBeen_ flag is never NA, and a 1 on either side is never lost", {
  pulls  <- make_contract_pulls()
  result <- suppressMessages(link_encounters(pulls$ed, pulls$ip))
  flags  <- result[grepl("^has_been_", names(result))]
  expect_false(anyNA(flags))
  expect_true(all(unlist(flags) %in% c(0L, 1L)))
})

test_that("HasBeenAdmitted is preferred over HasBeenI when both are in the ED pull", {
  pulls <- make_contract_pulls()
  # HasBeenI = 1 where HasBeenAdmitted = 0 would add a second 'Admitted' row
  # per record if HasBeenI were used alongside HasBeenAdmitted
  pulls$ed$HasBeenI <- pulls$ed$HasBeenAdmitted
  pulls$ip$HasBeenI <- pulls$ip$HasBeenAdmitted
  expect_message(
    result <- link_encounters(pulls$ed, pulls$ip),
    "will be used preferentially"
  )
  expect_equal(nrow(result), 6L)
  expect_false(anyNA(result$has_been_i))
})

test_that("link_encounters() never drops or invents a visit across random pulls", {
  set.seed(7)
  for (i in 1:25) {
    n_keys <- 40L
    keys <- tibble::tibble(
      Hospital = sample(1001:1003, n_keys, replace = TRUE),
      Visit_ID = sprintf("V%03d", sample(500, n_keys))
    ) |>
      dplyr::distinct()
    pick <- function(p) keys[stats::runif(nrow(keys)) < p, ]
    ed <- pick(0.6)
    ed$HasBeenE <- 1L
    ed$HasBeenAdmitted <- sample(0:1, nrow(ed), replace = TRUE)
    ed$C_Visit_Date_Time <- "2026-01-01 08:00:00"
    ip <- pick(0.5)
    ip$HasBeenE <- sample(0:1, nrow(ip), replace = TRUE, prob = c(0.8, 0.2))
    ip$HasBeenAdmitted <- 1L
    ip$C_Visit_Date_Time <- "2026-01-02 08:00:00"
    if (nrow(ed) == 0L || nrow(ip) == 0L) next

    result <- suppressMessages(link_encounters(ed, ip))
    ip_kept <- ip[ip$HasBeenE == 0L, ]
    expected_keys <- unique(rbind(
      ed[c("Hospital", "Visit_ID")], ip_kept[c("Hospital", "Visit_ID")]
    ))

    expect_equal(nrow(result), nrow(expected_keys))
    expect_equal(anyDuplicated(result[c("hospital", "visit_id")]), 0L)

    flags <- result[grepl("^has_been_", names(result))]
    expect_false(anyNA(flags))

    # every flag that is 1 on any input row of a visit is 1 on its output row
    all_rows <- dplyr::bind_rows(ed, ip_kept)
    for (f in c("HasBeenE", "HasBeenAdmitted")) {
      expected <- tapply(
        all_rows[[f]], paste(all_rows$Hospital, all_rows$Visit_ID), max
      )
      got <- stats::setNames(
        result[[janitor::make_clean_names(f)]],
        paste(result$hospital, result$visit_id)
      )
      expect_equal(unname(got[names(expected)]), unname(as.integer(expected)))
    }
  }
})

# kept regression tests ----

make_review_pulls <- function() {
  list(
    ed = tibble::tibble(
      Hospital = 1001L, Visit_ID = c("V1", "V2"),
      HasBeenE = 1L, HasBeenAdmitted = c(0L, 0L),
      C_Visit_Date_Time = c("2026-01-01 08:00:00", "2026-01-02 08:00:00")
    ),
    ip = tibble::tibble(
      Hospital = 1001L, Visit_ID = c("V3", "V3"),
      HasBeenE = 0L, HasBeenAdmitted = 1L,
      C_Visit_Date_Time = c("2026-01-03 08:00:00", "2026-01-04 08:00:00")
    )
  )
}

test_that("long-format .index_encounter marks exactly one row per episode, even with no ED row", {
  pulls <- make_review_pulls()
  result <- suppressMessages(
    link_encounters(pulls$ed, pulls$ip, return_format = "long")
  )
  per_episode <- tapply(result$.index_encounter, result$.episode_id, sum)
  expect_true(all(per_episode == 1L))
  expect_equal(
    sum(result$.index_encounter),
    nrow(suppressMessages(link_encounters(pulls$ed, pulls$ip)))
  )
})

test_that("long-format .index_encounter marks only the first of two ED rows in an episode", {
  ed <- tibble::tibble(
    Hospital = 1001L, Visit_ID = "V1", HasBeenE = 1L, HasBeenAdmitted = 0L,
    C_Visit_Date_Time = c("2026-01-01 08:00:00", "2026-01-01 09:00:00")
  )
  result <- suppressMessages(
    link_encounters(ed, ed[0L, ], return_format = "long")
  )
  expect_equal(result$.index_encounter, c(TRUE, FALSE))
})

test_that("link_encounters() aborts when inpatient_admission_data lacks a linking column", {
  pulls <- make_review_pulls()
  expect_error(
    suppressMessages(
      link_encounters(pulls$ed, dplyr::select(pulls$ip, -Hospital))
    ),
    "missing the linking column.*hospital"
  )
})

test_that("clean_names = FALSE restores the input's column names and keeps added columns", {
  pulls <- make_review_pulls()
  result <- suppressMessages(
    link_encounters(pulls$ed, pulls$ip, clean_names = FALSE)
  )
  expect_true(all(c("Hospital", "Visit_ID", "HasBeenE") %in% names(result)))
  expect_false("hospital" %in% names(result))
  expect_true(all(
    c(".episode_id", ".index_encounter", "patient_class") %in% names(result)
  ))
})

test_that("episode_class_sequence() computes each episode independently", {
  result <- episode_class_sequence(
    episode       = c("a", "a", "b", "b", "c"),
    patient_class = c("ED", "Direct Admit", "Inpatient", "ED", NA),
    class_time    = as.POSIXct(c(
      "2023-01-01 08:00:00", "2023-01-01 06:00:00",
      "2023-01-02 08:00:00", "2023-01-02 06:00:00", NA
    ), tz = "UTC")
  )
  expect_equal(
    result,
    c("Direct Admit->ED", "Direct Admit->ED", "ED->Inpatient", "ED->Inpatient",
      NA_character_)
  )
})

test_that("episode_class_sequence() gives a row with an NA class its episode's sequence", {
  result <- episode_class_sequence(
    episode       = c("a", "a"),
    patient_class = c("ED", NA),
    class_time    = as.POSIXct(c("2023-01-01 08:00:00", NA), tz = "UTC")
  )
  expect_equal(result, c("ED", "ED"))
})

test_that("episode_primary_row() marks the first ED row, else the first row, of each episode", {
  result <- episode_primary_row(
    episode       = c("a", "a", "b", "b", "c", "c"),
    patient_class = c("Direct Admit", "ED", "Direct Admit", "Inpatient", "ED", "ED")
  )
  expect_equal(result, c(FALSE, TRUE, TRUE, FALSE, TRUE, FALSE))
})

# identifiers are text ----

test_that("link_encounters() links a numeric Visit_ID in one pull to the same text value in the other", {
  ed <- tibble::tibble(
    Hospital = 1001L, Visit_ID = c(100000, 200), HasBeenE = 1L,
    HasBeenAdmitted = 0L, C_Visit_Date_Time = "2026-01-01 08:00:00"
  )
  ip <- tibble::tibble(
    Hospital = 1001L, Visit_ID = c("100000", "300"), HasBeenE = 0L,
    HasBeenAdmitted = 1L, C_Visit_Date_Time = "2026-01-02 08:00:00"
  )
  result <- suppressMessages(link_encounters(ed, ip))

  expect_type(result$visit_id, "character")
  # 100000 must match "100000", not as.character()'s "1e+05"
  linked <- dplyr::filter(result, visit_id == "100000")
  expect_equal(nrow(linked), 1L)
  expect_equal(linked$.episode_n_rows, 2L)
  expect_equal(sort(result$visit_id), c("100000", "200", "300"))
})

test_that("link_encounters() holds Visit_ID as text when both pulls deliver numbers, and keeps NA", {
  ed <- tibble::tibble(
    Hospital = 1001L, Visit_ID = c(1, NA), HasBeenE = 1L,
    HasBeenAdmitted = 0L, C_Visit_Date_Time = "2026-01-01 08:00:00"
  )
  ip <- tibble::tibble(
    Hospital = 1001L, Visit_ID = 2, HasBeenE = 0L, HasBeenAdmitted = 1L,
    C_Visit_Date_Time = "2026-01-02 08:00:00"
  )
  result <- suppressMessages(link_encounters(ed, ip))
  expect_type(result$visit_id, "character")
  expect_equal(sum(is.na(result$visit_id)), 1L)
  expect_true(all(c("1", "2") %in% result$visit_id))
})

test_that("fallback_visit_col is held as text in both pulls too", {
  ed <- tibble::tibble(
    Hospital = 1001L, Visit_ID = NA_character_, C_BioSense_ID = 555,
    HasBeenE = 1L, HasBeenAdmitted = 0L,
    C_Visit_Date_Time = "2026-01-01 08:00:00"
  )
  ip <- tibble::tibble(
    Hospital = 1001L, Visit_ID = NA_character_, C_BioSense_ID = "555",
    HasBeenE = 0L, HasBeenAdmitted = 1L,
    C_Visit_Date_Time = "2026-01-02 08:00:00"
  )
  result <- suppressMessages(
    link_encounters(ed, ip, fallback_visit_col = C_BioSense_ID)
  )
  expect_equal(nrow(result), 1L)
  expect_equal(result$.episode_n_rows, 2L)
  expect_type(result$c_bio_sense_id, "character")
})

test_that("as_text_cols() converts factors and leaves text and other columns alone", {
  d <- tibble::tibble(
    a = factor(c("x", "y")), b = c("p", "q"), c = c(1.5, 100000), d = 1:2
  )
  result <- as_text_cols(d, c("a", "b", "c"))
  expect_identical(result$a, c("x", "y"))
  expect_identical(result$b, c("p", "q"))
  expect_identical(result$c, c("1.5", "100000"))
  expect_identical(result$d, 1:2)
})

test_that("dedupe() compares Visit_ID as text and returns its type unchanged", {
  as_num <- tibble::tibble(
    Hospital = 1L, Visit_ID = c(100000, 100000, 7), x = 1:3
  )
  as_txt <- dplyr::mutate(as_num, Visit_ID = c("100000", "100000", "7"))
  expect_equal(nrow(dedupe(as_num)), nrow(dedupe(as_txt)))
  expect_type(dedupe(as_num)$visit_id, "double")
  expect_type(dedupe(as_txt)$visit_id, "character")
})

# verbose on dedupe() and summarize_duplicates() ----

test_that("dedupe() verbose = FALSE silences the missing-key message", {
  data <- tibble::tibble(Hospital = 1L, Visit_ID = c(NA, NA, "V1"), x = 1:3)
  expect_message(dedupe(data), "missing")
  expect_no_message(dedupe(data, verbose = FALSE))
  expect_equal(nrow(suppressMessages(dedupe(data))), 3L)
  expect_error(dedupe(data, verbose = NA), "verbose")
})

test_that("summarize_duplicates() verbose = FALSE silences the missing-key message", {
  data <- tibble::tibble(Hospital = 1L, Visit_ID = c(NA, NA, "V1"), x = 1:3)
  expect_message(summarize_duplicates(data), "missing")
  expect_no_message(summarize_duplicates(data, verbose = FALSE))
  expect_error(summarize_duplicates(data, verbose = "yes"), "verbose")
})

# linking keys (facility, visit, fallback) are held as text ----

test_that("link_encounters() links a numeric Hospital in one pull to the same text value in the other", {
  ed <- tibble::tibble(
    Hospital = c(1001L, 1002L), Visit_ID = c("V1", "V2"), HasBeenE = 1L,
    HasBeenAdmitted = 0L, C_Visit_Date_Time = "2026-01-01 08:00:00"
  )
  ip <- tibble::tibble(
    Hospital = c("1001", "1003"), Visit_ID = c("V1", "V9"), HasBeenE = 0L,
    HasBeenAdmitted = 1L, C_Visit_Date_Time = "2026-01-02 08:00:00"
  )
  result <- suppressMessages(link_encounters(ed, ip))

  expect_type(result$hospital, "character")
  expect_equal(nrow(result), 3L)
  linked <- dplyr::filter(result, hospital == "1001", visit_id == "V1")
  expect_equal(nrow(linked), 1L)
  expect_equal(linked$.episode_n_rows, 2L)
  # the episode id is unchanged by the type conversion
  expect_equal(linked$.episode_id, "1001_V1")
})

test_that("link_encounters() holds a numeric Hospital as text even when both pulls agree", {
  pulls <- make_review_pulls()
  result <- suppressMessages(link_encounters(pulls$ed, pulls$ip))
  expect_type(pulls$ed$Hospital, "integer")
  expect_type(result$hospital, "character")
  expect_true(all(result$hospital == "1001"))
})

test_that("as_text_cols() writes large numbers in full and keeps NA", {
  d <- tibble::tibble(h = c(1e5, 1234567890123, NA))
  expect_identical(as_text_cols(d, "h")$h, c("100000", "1234567890123", NA))
})

# concat: whole words and whole codes ----

test_that("contains_whole() matches whole words, phrases, and codes only", {
  expect_true(contains_whole("seen in ED today", "ED"))
  expect_true(contains_whole("fall from bed.", "bed"))
  expect_false(contains_whole("waterfall", "fall"))
  expect_false(contains_whole("needed oxygen", "need"))
  # diagnosis codes: the dot belongs to the code
  expect_true(contains_whole("dx R10.9; K35.80", "R10.9"))
  expect_false(contains_whole("dx R10.90", "R10.9"))
  expect_false(contains_whole("dx R10.9", "R10"))
  expect_true(contains_whole("dx 789.00", "789.00"))
  expect_false(contains_whole("dx 789.001", "789.00"))
  # SNOMED codes are whole numbers
  expect_true(contains_whole("snomed 29857009 pain", "29857009"))
  expect_false(contains_whole("snomed 298570091", "29857009"))
  # multi-word phrases match as a run of whole words, ignoring case/spacing
  expect_true(contains_whole("Chest  Pain, nausea", "chest pain"))
  expect_false(contains_whole("chest wall pain", "chest pain"))
  # a value with no letters or digits is matched literally
  expect_true(contains_whole("a --- b", "---"))
  expect_false(contains_whole("a -- b", "---"))
  # a value longer than the text cannot be contained in it
  expect_false(contains_whole("chest", "chest pain"))
})

test_that("merge_concat() keeps text and codes found in one record but not the other", {
  expect_identical(merge_concat(c("needed", "ed"), "needed"), "needed; ed")
  expect_identical(
    merge_concat(c("fell from waterfall", "fall"), "fell from waterfall"),
    "fell from waterfall; fall"
  )
  expect_identical(merge_concat(c("R10.90", "R10.9"), "R10.90"), "R10.90; R10.9")
  expect_identical(
    merge_concat(c("abdominal pain", "abdominal pain, vomiting"), "abdominal pain"),
    "abdominal pain; abdominal pain, vomiting"
  )
})

test_that("merge_concat() does not repeat a value already present as whole words or codes", {
  expect_identical(merge_concat(c("seen in ED", "ED"), "seen in ED"), "seen in ED")
  expect_identical(
    merge_concat(c("dx R10.9; K35.80", "K35.80"), "dx R10.9; K35.80"),
    "dx R10.9; K35.80"
  )
  expect_identical(merge_concat(c("Chest Pain", "chest pain"), "Chest Pain"), "Chest Pain")
})
