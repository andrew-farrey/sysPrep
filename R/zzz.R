
# .onAttach() ----
# Displays a short startup message when the package is attached via
# library()/require(). Uses .onAttach (not .onLoad) so the message only
# fires on explicit user attachment, never when sysPrep is loaded silently
# as another package's dependency. packageStartupMessage() is used rather
# than message()/cat() so the banner is suppressible via
# suppressPackageStartupMessages(), per CRAN policy on package start-up
# messages. Also checks options(sysPrep.quiet = TRUE) for users who want to
# suppress it permanently (e.g., in .Rprofile) without wrapping every
# library(sysPrep) call.
.onAttach <- function(libname, pkgname) {
  if (isTRUE(getOption("sysPrep.quiet", FALSE))) {
    return(invisible())
  }

  version <- utils::packageVersion(pkgname)

  packageStartupMessage(
    "\u2b21 ", pkgname, " ", version, "\n\n",
    "Preprocessing methods for NSSP ESSENCE syndromic surveillance data.\n",
    "This is an independent R package and is not affiliated with the National\n",
    "Syndromic Surveillance Program (NSSP) or the Centers for Disease\n",
    "Control and Prevention (CDC).\n\n",
    "Docs:      https://andrew-farrey.github.io/sysPrep/\n",
    "Vignettes: browseVignettes(\"sysPrep\")\n\n",
    "Deduplication method used by your site not present?\n",
    "Please let me know by submitting an issue here:\n",
    "https://github.com/andrew-farrey/sysPrep/issues"
  )
}
