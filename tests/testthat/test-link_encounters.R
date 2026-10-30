
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

test_that("link_encounters() applies follow_severity to discharge_disposition and prefer_severity to disposition_category", {
  fixture <- make_readmit_merge_data()
  result  <- suppressMessages(
    link_encounters(fixture$ed_data, fixture$inpatient_admission_data)
  )
  expect_equal(result$discharge_disposition, "Expired")
  expect_equal(result$disposition_category, "DECEASED")
})

# prefer_severity: the more severe DispositionCategory wins, whichever record has it ----

test_that("disposition_severity() ranks DECEASED above TRANSFERRED above ADMIT = DISCHARGED above UNKNOWN", {
  expect_identical(
    disposition_severity(c(
      "DECEASED", "ADMIT", "TRANSFERRED", "DISCHARGED", "UNKNOWN", NA, ""
    )),
    c(3L, 1L, 2L, 1L, 0L, 0L, 0L)
  )
  expect_identical(disposition_severity(character(0)), integer(0))
})

test_that("disposition_severity() ignores case and surrounding spaces, and ranks other values with DISCHARGED", {
  expect_identical(
    disposition_severity(c(" deceased ", "Admit", "transferred", "Home")),
    c(3L, 1L, 2L, 1L)
  )
})

test_that("merge_prefer_severity() keeps DECEASED on the ED record over an inpatient DISCHARGED", {
  # the ED record carries the more severe value; the inpatient record's
  # milder value must not win
  result <- merge_prefer_severity(
    values          = c("DECEASED", "DISCHARGED"),
    patient_classes = c("ED", "Direct Admit"),
    primary_value   = "DECEASED"
  )
  expect_equal(result, "DECEASED")
})

test_that("merge_prefer_severity() keeps TRANSFERRED over DISCHARGED from either record", {
  expect_equal(
    merge_prefer_severity(
      c("DISCHARGED", "TRANSFERRED"), c("ED", "Direct Admit"), "DISCHARGED"
    ),
    "TRANSFERRED"
  )
  expect_equal(
    merge_prefer_severity(
      c("TRANSFERRED", "DISCHARGED"), c("ED", "Direct Admit"), "TRANSFERRED"
    ),
    "TRANSFERRED"
  )
})

test_that("merge_prefer_severity() ranks DECEASED above TRANSFERRED and ADMIT", {
  expect_equal(
    merge_prefer_severity(
      c("TRANSFERRED", "DECEASED"), c("ED", "Direct Admit"), "TRANSFERRED"
    ),
    "DECEASED"
  )
  expect_equal(
    merge_prefer_severity(
      c("ADMIT", "DECEASED"), c("ED", "Direct Admit"), "ADMIT"
    ),
    "DECEASED"
  )
})

test_that("merge_prefer_severity() keeps a known category over UNKNOWN", {
  expect_equal(
    merge_prefer_severity(
      c("UNKNOWN", "DISCHARGED"), c("ED", "Direct Admit"), "UNKNOWN"
    ),
    "DISCHARGED"
  )
})

test_that("merge_prefer_severity() breaks ties by admission-class row, then primary row, then first", {
  expect_equal(
    merge_prefer_severity(
      c("ADMIT", "DISCHARGED"), c("ED", "Direct Admit"), "ADMIT"
    ),
    "DISCHARGED"
  )
  expect_equal(
    merge_prefer_severity(
      c("ADMIT", "DISCHARGED"), c("ED", "Observation"), "ADMIT"
    ),
    "ADMIT"
  )
  expect_equal(
    merge_prefer_severity(
      c("ADMIT", "DISCHARGED"), c("Observation", "Outpatient"), "Other"
    ),
    "ADMIT"
  )
})

test_that("an ED ADMIT gives way to the inpatient record's DISCHARGED, and an ED DISCHARGED to its ADMIT", {
  from_ip <- c(FALSE, TRUE)
  expect_equal(
    merge_prefer_severity(
      c("ADMIT", "DISCHARGED"), c("ED", "Direct Admit"), "ADMIT", from_ip
    ),
    "DISCHARGED"
  )
  expect_equal(
    merge_prefer_severity(
      c("DISCHARGED", "ADMIT"), c("ED", "Direct Admit"), "DISCHARGED", from_ip
    ),
    "ADMIT"
  )
})

test_that("merge_prefer_severity() falls back to primary_value when every value is unknown or missing", {
  expect_equal(
    merge_prefer_severity(
      c(NA, "UNKNOWN"), c("ED", "Direct Admit"), "primary"
    ),
    "primary"
  )
})

test_that("link_encounters() keeps DECEASED recorded on the inpatient record and marks C_Death", {
  fixture <- make_readmit_merge_data()
  # the inpatient record names the death but leaves C_Death unmarked
  fixture$inpatient_admission_data$C_Death <- "No"
  result <- suppressMessages(
    link_encounters(fixture$ed_data, fixture$inpatient_admission_data)
  )
  expect_equal(result$disposition_category, "DECEASED")
  expect_equal(result$c_death, "Yes")
})

test_that("link_encounters() keeps TRANSFERRED over DISCHARGED without touching C_Death", {
  fixture <- make_readmit_merge_data()
  fixture$inpatient_admission_data$C_Death <- "No"
  fixture$inpatient_admission_data$DispositionCategory <- "TRANSFERRED"
  result <- suppressMessages(
    link_encounters(fixture$ed_data, fixture$inpatient_admission_data)
  )
  expect_equal(result$disposition_category, "TRANSFERRED")
  expect_equal(result$c_death, "No")
})

test_that("link_encounters() keeps DECEASED on the ED record even when it also has HasBeenAdmitted = 1", {
  fixture <- make_readmit_merge_data()
  fixture$ed_data$HasBeenAdmitted <- 1L
  fixture$ed_data$DispositionCategory <- "DECEASED"
  fixture$inpatient_admission_data$DispositionCategory <- "DISCHARGED"
  fixture$inpatient_admission_data$C_Death <- "No"
  result <- suppressMessages(
    link_encounters(fixture$ed_data, fixture$inpatient_admission_data)
  )
  expect_equal(result$disposition_category, "DECEASED")
  expect_equal(result$c_death, "Yes")
})

test_that("severity_row_index() returns the winning position, or NA when nothing is known", {
  expect_equal(
    severity_row_index(
      c("DISCHARGED", "DECEASED"), c("ED", "Direct Admit"), "DISCHARGED"
    ),
    2L
  )
  expect_equal(
    severity_row_index(c("DECEASED", "DISCHARGED"), c("ED", "Admitted"), "x"),
    1L
  )
  # equally severe, no admission-class row: the primary row's value, found by
  # position
  expect_equal(
    severity_row_index(
      c("ADMIT", "DISCHARGED"), c("Observation", "Outpatient"), "DISCHARGED"
    ),
    2L
  )
  expect_true(is.na(
    severity_row_index(c(NA, "UNKNOWN"), c("ED", "Direct Admit"), "x")
  ))
})

test_that("merge_follow_severity() takes the value from the winning record, else prefer_admission", {
  expect_equal(
    merge_follow_severity(
      c("Discharged to home", "Expired"), c("ED", "Direct Admit"),
      "Discharged to home", severity_row = 2L
    ),
    "Expired"
  )
  # the winning record has no value: fall back to the admission-class value
  expect_equal(
    merge_follow_severity(
      c("Discharged to home", NA), c("ED", "Direct Admit"),
      "Discharged to home", severity_row = 2L
    ),
    "Discharged to home"
  )
  expect_equal(
    merge_follow_severity(
      c("Discharged to home", ""), c("ED", "Direct Admit"),
      "Discharged to home", severity_row = 2L
    ),
    "Discharged to home"
  )
  # no winner at all
  expect_equal(
    merge_follow_severity(
      c("Home", "Expired"), c("ED", "Direct Admit"), "Home",
      severity_row = NA_integer_
    ),
    "Expired"
  )
})

test_that("Discharge_Disposition comes from the record that supplied DispositionCategory", {
  fixture <- make_readmit_merge_data()
  fixture$inpatient_admission_data$DispositionCategory <- "TRANSFERRED"
  fixture$inpatient_admission_data$Discharge_Disposition <-
    "Transferred to another facility"
  result <- suppressMessages(
    link_encounters(fixture$ed_data, fixture$inpatient_admission_data)
  )
  expect_equal(result$disposition_category, "TRANSFERRED")
  expect_equal(result$discharge_disposition, "Transferred to another facility")
})

test_that("Discharge_Disposition follows DispositionCategory to the ED record when it wins", {
  fixture <- make_readmit_merge_data()
  fixture$ed_data$HasBeenAdmitted <- 1L
  fixture$ed_data$DispositionCategory <- "DECEASED"
  fixture$ed_data$Discharge_Disposition <- "Expired"
  fixture$inpatient_admission_data$DispositionCategory <- "DISCHARGED"
  fixture$inpatient_admission_data$Discharge_Disposition <-
    "Discharged to home"
  result <- suppressMessages(
    link_encounters(fixture$ed_data, fixture$inpatient_admission_data)
  )
  expect_equal(result$disposition_category, "DECEASED")
  expect_equal(result$discharge_disposition, "Expired")
})

test_that("Discharge_Disposition falls back when the winning record has none", {
  fixture <- make_readmit_merge_data()
  fixture$inpatient_admission_data$Discharge_Disposition <- NA_character_
  result <- suppressMessages(
    link_encounters(fixture$ed_data, fixture$inpatient_admission_data)
  )
  expect_equal(result$disposition_category, "DECEASED")
  expect_equal(result$discharge_disposition, "Discharged to home")
})

test_that("follow_severity falls back to prefer_admission when no prefer_severity field is present", {
  fixture <- make_readmit_merge_data()
  result <- suppressMessages(
    link_encounters(
      fixture$ed_data, fixture$inpatient_admission_data,
      merge_fields = c(Discharge_Disposition = "follow_severity")
    )
  )
  expect_equal(result$discharge_disposition, "Expired")
})

test_that("severity_row_index() breaks a tie in favor of the inpatient pull's record", {
  # row 2 is the ED record's own "Admitted" row, row 3 the inpatient record
  expect_equal(
    severity_row_index(
      c("DISCHARGED", "ADMIT", "DISCHARGED"),
      c("ED", "Admitted", "Direct Admit"), "DISCHARGED",
      from_inpatient = c(FALSE, FALSE, TRUE)
    ),
    3L
  )
  # without pull information the first admission-class row wins, as before
  expect_equal(
    severity_row_index(
      c("DISCHARGED", "ADMIT", "DISCHARGED"),
      c("ED", "Admitted", "Direct Admit"), "DISCHARGED"
    ),
    2L
  )
})

test_that("an ED ADMIT gives way to the inpatient record's DISCHARGED whatever the ED HasBeenAdmitted flag", {
  for (ed_admitted in c(0L, 1L)) {
    fixture <- make_readmit_merge_data()
    fixture$ed_data$HasBeenAdmitted <- ed_admitted
    fixture$ed_data$DispositionCategory <- "ADMIT"
    fixture$ed_data$Discharge_Disposition <- "Admitted to inpatient"
    fixture$inpatient_admission_data$DispositionCategory <- "DISCHARGED"
    fixture$inpatient_admission_data$Discharge_Disposition <-
      "Discharged home"
    fixture$inpatient_admission_data$C_Death <- "No"
    result <- suppressMessages(
      link_encounters(fixture$ed_data, fixture$inpatient_admission_data)
    )
    expect_equal(result$disposition_category, "DISCHARGED")
    expect_equal(result$discharge_disposition, "Discharged home")
  }
})

test_that("an ED DISCHARGED followed by an inpatient ADMIT merges to ADMIT", {
  fixture <- make_readmit_merge_data()
  fixture$inpatient_admission_data$DispositionCategory <- "ADMIT"
  fixture$inpatient_admission_data$Discharge_Disposition <-
    "Admitted to inpatient"
  fixture$inpatient_admission_data$C_Death <- "No"
  result <- suppressMessages(
    link_encounters(fixture$ed_data, fixture$inpatient_admission_data)
  )
  expect_equal(result$disposition_category, "ADMIT")
  expect_equal(result$discharge_disposition, "Admitted to inpatient")
})

test_that("a TRANSFERRED on either record outranks an ADMIT or DISCHARGED on the other", {
  for (side in c("ed_data", "inpatient_admission_data")) {
    fixture <- make_readmit_merge_data()
    fixture$ed_data$DispositionCategory <- "ADMIT"
    fixture$inpatient_admission_data$DispositionCategory <- "DISCHARGED"
    fixture$inpatient_admission_data$C_Death <- "No"
    fixture[[side]]$DispositionCategory <- "TRANSFERRED"
    result <- suppressMessages(
      link_encounters(fixture$ed_data, fixture$inpatient_admission_data)
    )
    expect_equal(result$disposition_category, "TRANSFERRED")
  }
})

test_that(".link_pull and .link_src_row never appear in the output", {
  fixture <- make_readmit_merge_data()
  collapsed <- suppressMessages(
    link_encounters(fixture$ed_data, fixture$inpatient_admission_data)
  )
  long <- suppressMessages(
    link_encounters(
      fixture$ed_data, fixture$inpatient_admission_data,
      return_format = "long"
    )
  )
  for (output in list(collapsed, long)) {
    expect_false(any(c(".link_pull", ".link_src_row") %in% names(output)))
  }
})

test_that("collapse_episodes() works without pull information and ranks by severity", {
  result <- tibble::tibble(
    .episode_id = c("1_A", "1_A"), .episode_n_rows = 2L,
    patient_class = c("ED", "Direct Admit"),
    disposition_category = c("DISCHARGED", "DECEASED"),
    c_death = c("No", "No")
  )
  collapsed <- collapse_episodes(
    result,
    merge_fields = c(
      disposition_category = "prefer_severity", c_death = "prefer_yes"
    ),
    merge_delimiter = ";"
  )
  expect_equal(nrow(collapsed), 1L)
  expect_equal(collapsed$disposition_category, "DECEASED")
  expect_equal(collapsed$c_death, "Yes")
})

test_that("a text 0/1 C_Death column stays 0/1 coded when a linked episode is marked", {
  fixture <- make_readmit_merge_data()
  fixture$ed_data$C_Death <- "0"
  fixture$inpatient_admission_data$C_Death <- "0"
  unlinked <- fixture$ed_data
  unlinked$Visit_ID <- "V00000009"
  unlinked$C_Death <- "1"
  ed <- dplyr::bind_rows(fixture$ed_data, unlinked)
  result <- suppressMessages(
    link_encounters(ed, fixture$inpatient_admission_data)
  )
  expect_equal(nrow(result), 2L)
  expect_equal(sort(unique(result$c_death)), "1")
  expect_equal(
    result$disposition_category[result$visit_id == "V00000001"], "DECEASED"
  )
})

test_that("mark_death_from_disposition() reads the C_Death coding from the reference column", {
  merge_fields <- c(
    disposition_category = "prefer_severity", c_death = "prefer_yes"
  )
  linked <- tibble::tibble(disposition_category = "DECEASED", c_death = "0")
  reference <- tibble::tibble(
    disposition_category = c("DECEASED", "DISCHARGED"), c_death = c("0", "1")
  )
  expect_equal(
    mark_death_from_disposition(linked, merge_fields, reference)$c_death, "1"
  )
  # a Yes/No reference keeps Yes
  yes_no <- tibble::tibble(
    disposition_category = c("DECEASED", "DISCHARGED"),
    c_death = c("No", "Yes")
  )
  expect_equal(
    mark_death_from_disposition(
      tibble::tibble(disposition_category = "DECEASED", c_death = "No"),
      merge_fields, yes_no
    )$c_death,
    "Yes"
  )
})

test_that("link_encounters() leaves a record with no linked counterpart unchanged", {
  ed <- make_readmit_merge_data()$ed_data
  ip <- make_readmit_merge_data()$inpatient_admission_data
  ip$Visit_ID <- "V00000099"
  result <- suppressMessages(link_encounters(ed, ip))
  expect_equal(nrow(result), 2L)
  expect_equal(
    result$disposition_category[result$visit_id == "V00000001"], "DISCHARGED"
  )
  expect_equal(result$c_death[result$visit_id == "V00000001"], "No")
})

test_that("mark_death_from_disposition() writes C_Death in the form the column already uses", {
  merge_fields <- c(
    disposition_category = "prefer_severity", c_death = "prefer_yes"
  )
  dead <- "DECEASED"
  as_text <- tibble::tibble(disposition_category = dead, c_death = "No")
  expect_equal(
    mark_death_from_disposition(as_text, merge_fields)$c_death, "Yes"
  )
  as_flag_text <- tibble::tibble(
    disposition_category = c(dead, "DISCHARGED"), c_death = c("0", "1")
  )
  expect_equal(
    mark_death_from_disposition(as_flag_text, merge_fields)$c_death,
    c("1", "1")
  )
  as_int <- tibble::tibble(disposition_category = dead, c_death = 0L)
  expect_identical(
    mark_death_from_disposition(as_int, merge_fields)$c_death, 1L
  )
  as_dbl <- tibble::tibble(disposition_category = dead, c_death = 0)
  expect_identical(
    mark_death_from_disposition(as_dbl, merge_fields)$c_death, 1
  )
})

test_that("mark_death_from_disposition() leaves C_Death alone when there is nothing to mark", {
  merge_fields <- c(
    disposition_category = "prefer_severity", c_death = "prefer_yes"
  )
  no_death <- tibble::tibble(
    disposition_category = "DISCHARGED", c_death = "No"
  )
  expect_identical(
    mark_death_from_disposition(no_death, merge_fields), no_death
  )

  no_c_death <- tibble::tibble(disposition_category = "DECEASED")
  expect_identical(
    mark_death_from_disposition(no_c_death, merge_fields), no_c_death
  )

  old_strategy <- c(
    disposition_category = "prefer_admission", c_death = "prefer_yes"
  )
  dead_no_flag <- tibble::tibble(
    disposition_category = "DECEASED", c_death = "No"
  )
  expect_identical(
    mark_death_from_disposition(dead_no_flag, old_strategy), dead_no_flag
  )
})

test_that("prefer_admission is still available and takes the first admission-class row", {
  fixture <- make_readmit_merge_data()
  # the ED record's own "Admitted" row comes first, so its value is kept
  fixture$ed_data$HasBeenAdmitted <- 1L
  result <- suppressMessages(
    link_encounters(
      fixture$ed_data, fixture$inpatient_admission_data,
      merge_fields = c(DispositionCategory = "prefer_admission")
    )
  )
  expect_equal(result$disposition_category, "DISCHARGED")
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

test_that("as_key_text() keeps different long identifiers different", {
  v <- c(1234567890123456, 1234567890123457, 100000, 1.5, NA)
  expect_identical(
    as_key_text(v),
    c("1234567890123456", "1234567890123457", "100000", "1.5", NA)
  )
  expect_identical(as_key_text(c("a", NA)), c("a", NA))
  expect_identical(as_key_text(factor("x")), "x")
})

test_that("link_encounters() does not merge two long numeric Visit_IDs", {
  ed <- tibble::tibble(
    Hospital = 1, Visit_ID = c(1234567890123456, 1234567890123457),
    HasBeenE = 1L, HasBeenAdmitted = 0L,
    C_Visit_Date_Time = "2025-01-01 10:00:00"
  )
  ip <- tibble::tibble(
    Hospital = "1", Visit_ID = "1234567890123456", HasBeenE = 0L,
    HasBeenAdmitted = 1L, C_Visit_Date_Time = "2025-01-02 10:00:00"
  )
  result <- suppressMessages(link_encounters(ed, ip))
  expect_equal(nrow(result), 2L)
  linked <- dplyr::filter(result, visit_id == "1234567890123456")
  expect_equal(linked$.episode_n_rows, 2L)
  other <- dplyr::filter(result, visit_id == "1234567890123457")
  expect_equal(other$.episode_n_rows, 1L)
})

# a record with a missing key stays one visit ----

test_that("an NA-key record with several patient classes stays one episode (HasBeen_ flags)", {
  ed <- tibble::tibble(
    Hospital = "1", Visit_ID = c(NA, "V2"), HasBeenE = 1L,
    HasBeenAdmitted = c(1L, 0L),
    C_Visit_Date_Time = "2025-01-01 10:00:00"
  )
  ip <- tibble::tibble(
    Hospital = "1", Visit_ID = "V9", HasBeenE = 0L, HasBeenAdmitted = 1L,
    C_Visit_Date_Time = "2025-01-02 10:00:00"
  )
  result <- suppressMessages(link_encounters(ed, ip))
  expect_equal(nrow(result), 3L)
  na_key <- dplyr::filter(result, is.na(visit_id))
  expect_equal(nrow(na_key), 1L)
  expect_equal(na_key$.episode_n_rows, 2L)
  expect_equal(na_key$has_been_e, 1L)
  expect_equal(na_key$has_been_admitted, 1L)
  expect_false(".link_src_row" %in% names(result))
})

test_that("an NA-key record with several patient classes stays one episode (class list)", {
  ed <- tibble::tibble(
    Hospital = "1", Visit_ID = c(NA, "V2"),
    C_Patient_Class_List = c("EI", "E"),
    HasBeenE = 1L, HasBeenAdmitted = c(1L, 0L),
    C_Visit_Date_Time = "2025-01-01 10:00:00"
  )
  ip <- tibble::tibble(
    Hospital = "1", Visit_ID = "V9", HasBeenE = 0L, HasBeenAdmitted = 1L,
    C_Visit_Date_Time = "2025-01-02 10:00:00"
  )
  result <- suppressMessages(link_encounters(ed, ip))
  expect_equal(nrow(result), 3L)
  expect_equal(sum(is.na(result$visit_id)), 1L)
  long <- suppressMessages(link_encounters(ed, ip, return_format = "long"))
  expect_equal(sum(long$.index_encounter), 3L)
})

test_that("the missing-key message counts records, not expanded rows", {
  ed <- tibble::tibble(
    Hospital = "1", Visit_ID = c(NA, "V2"), HasBeenE = 1L,
    HasBeenAdmitted = c(1L, 0L), C_Visit_Date_Time = "2025-01-01 10:00:00"
  )
  ip <- tibble::tibble(
    Hospital = "1", Visit_ID = "V9", HasBeenE = 0L, HasBeenAdmitted = 1L,
    C_Visit_Date_Time = "2025-01-02 10:00:00"
  )
  expect_message(link_encounters(ed, ip), "^1 row\\(s\\) have a missing")
})

test_that("na_safe_group_id() keeps NA-key rows that share a row_id together", {
  d <- tibble::tibble(a = c("x", NA, NA, "y"), b = 1)
  expect_equal(length(unique(na_safe_group_id(d, c("a", "b")))), 4L)
  ids <- na_safe_group_id(d, c("a", "b"), row_id = c(1, 2, 2, 3))
  expect_equal(ids[2], ids[3])
  expect_equal(length(unique(ids)), 3L)
})

test_that("build_episode_ids() treats each NA-key row as its own record without a source id", {
  long <- tibble::tibble(h = c("1", "1"), v = c(NA, NA))
  ids <- build_episode_ids(long, "h", "v", FALSE, NULL, FALSE)
  expect_equal(length(unique(ids)), 2L)
})

# the two pulls carry the same HasBeen_ flags; one record per visit per pull ----

make_flag_pulls <- function() {
  list(
    ed = tibble::tibble(
      Hospital = "1", Visit_ID = c("A", "B"), HasBeenE = 1L,
      HasBeenAdmitted = 0L, HasBeenI = 0L,
      C_Visit_Date_Time = "2025-01-01 10:00:00"
    ),
    ip = tibble::tibble(
      Hospital = "1", Visit_ID = c("A", "Q"), HasBeenE = 0L,
      HasBeenAdmitted = 1L, HasBeenI = 1L,
      C_Visit_Date_Time = "2025-01-02 10:00:00"
    )
  )
}

test_that("link_encounters() is quiet when both pulls carry the same HasBeen_ flags", {
  pulls <- make_flag_pulls()
  expect_no_warning(
    suppressMessages(link_encounters(pulls$ed, pulls$ip))
  )
})

test_that("link_encounters() aborts when a HasBeen_ flag is in only one pull", {
  pulls <- make_flag_pulls()
  pulls$ip$HasBeenI <- NULL
  expect_error(
    suppressMessages(link_encounters(pulls$ed, pulls$ip)),
    "only in `ed_data`: `has_been_i`"
  )

  pulls <- make_flag_pulls()
  pulls$ed$HasBeenI <- NULL
  expect_error(
    suppressMessages(link_encounters(pulls$ed, pulls$ip)),
    "only in `inpatient_admission_data`: `has_been_i`"
  )
})

test_that("the flag error names both sides, the required fields, and ignores verbose", {
  pulls <- make_flag_pulls()
  pulls$ed$HasBeenO <- 0L
  pulls$ip$HasBeenI <- NULL
  error <- tryCatch(
    link_encounters(pulls$ed, pulls$ip, verbose = FALSE),
    error = function(e) e
  )
  expect_s3_class(error, "rlang_error")
  expect_equal(rlang::call_name(error$call), "link_encounters")
  message <- conditionMessage(error)
  expect_match(message, "must carry the same `HasBeen_` flag columns")
  expect_match(message, "only in `ed_data`: ")
  expect_match(message, "`has_been_o`")
  expect_match(message, "`has_been_i`")
  expect_match(message, "Required fields")
})

test_that("link_encounters() accepts pulls that carry no HasBeen_ flags at all", {
  ed <- tibble::tibble(
    Hospital = "1", Visit_ID = "A", C_Patient_Class_List = "E",
    C_Visit_Date_Time = "2025-01-01 10:00:00"
  )
  ip <- tibble::tibble(
    Hospital = "1", Visit_ID = "A", C_Visit_Date_Time = "2025-01-02 10:00:00"
  )
  result <- suppressMessages(link_encounters(ed, ip))
  expect_equal(nrow(result), 1L)
  expect_equal(result$.episode_n_rows, 2L)
})

test_that("link_encounters() reports episodes with several records from one pull", {
  pulls <- make_flag_pulls()
  pulls$ed <- dplyr::bind_rows(pulls$ed, pulls$ed[1, ])
  expect_message(
    link_encounters(pulls$ed, pulls$ip),
    "1 episode\\(s\\) hold more than one record from the same pull"
  )
  expect_no_message(
    link_encounters(pulls$ed, pulls$ip, verbose = FALSE)
  )

  pulls <- make_flag_pulls()
  pulls$ip <- dplyr::bind_rows(pulls$ip, pulls$ip[2, ])
  expect_message(
    link_encounters(pulls$ed, pulls$ip),
    "hold more than one record from the same pull"
  )
})

test_that("a linked pair and an in-record escalation are not reported as same-pull duplicates", {
  pulls <- make_flag_pulls()
  # visit A is in both pulls (linked); visit B escalates inside one ED record
  pulls$ed$HasBeenAdmitted[2] <- 1L
  messages <- character()
  withCallingHandlers(
    link_encounters(pulls$ed, pulls$ip),
    message = function(m) {
      messages <<- c(messages, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  expect_false(any(grepl("same pull", messages)))
})

test_that("inform_same_pull_duplicates() does nothing without the source columns", {
  expect_null(inform_same_pull_duplicates(tibble::tibble(a = 1), "x", TRUE))
})

test_that("link_encounters() names itself when the two pulls cannot be combined", {
  ed <- tibble::tibble(
    Hospital = "1", Visit_ID = "A", HasBeenE = "1", HasBeenAdmitted = "0",
    C_Visit_Date_Time = "2025-01-01 10:00:00"
  )
  ip <- tibble::tibble(
    Hospital = "1", Visit_ID = "B", HasBeenE = 0L, HasBeenAdmitted = 1L,
    C_Visit_Date_Time = "2025-01-02 10:00:00"
  )
  expect_error(
    suppressMessages(link_encounters(ed, ip)),
    "could not be combined",
    class = "rlang_error"
  )
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

test_that("link_encounters() keeps the input column order", {
  ed <- essence_ed_raw
  ip <- essence_inp_raw
  out <- suppressMessages(link_encounters(ed, ip, clean_names = FALSE))
  expect_equal(
    names(out),
    c(names(ed), "patient_class", ".episode_id", ".patient_class_sequence",
      ".episode_n_rows", ".index_encounter")
  )
})

test_that("link_encounters() tracks a reordered input for both return formats", {
  front <- function(d) {
    d[, c("HasBeenE", "HasBeenAdmitted",
          setdiff(names(d), c("HasBeenE", "HasBeenAdmitted")))]
  }
  ed <- front(essence_ed_raw)
  ip <- front(essence_inp_raw)
  for (fmt in c("collapsed", "long")) {
    out <- suppressMessages(
      link_encounters(ed, ip, return_format = fmt, clean_names = FALSE)
    )
    expect_equal(names(out)[seq_along(ed)], names(ed))
  }
})