
# test-zzz.R ----

test_that(".onAttach() suppresses the startup message when sysPrep.quiet = TRUE", {
  withr::local_options(sysPrep.quiet = TRUE)
  expect_no_message(sysPrep:::.onAttach(libname = NULL, pkgname = "sysPrep"))
})

test_that(".onAttach() shows the startup message by default", {
  withr::local_options(sysPrep.quiet = NULL)
  expect_message(
    sysPrep:::.onAttach(libname = NULL, pkgname = "sysPrep"),
    "sysPrep"
  )
})
