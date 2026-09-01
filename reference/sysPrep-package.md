# sysPrep: Preprocessing Methods for NSSP ESSENCE Syndromic Surveillance Data

Provides a suite of functions for preprocessing and quality assurance of
syndromic surveillance data obtained from the National Syndromic
Surveillance Program (NSSP) Electronic Surveillance System for the Early
Notification of Community-based Epidemics (ESSENCE) API. Functions
address common data quality challenges including visit-level
deduplication with mechanism classification, care setting filtering with
facility type correction, emergency department to inpatient encounter
linkage for accurate burden estimation, and geographic attribution for
out-of-state and non-residential visits. Methods were developed through
applied drug overdose surveillance and cluster detection. Functions have
been validated against records pulled from the NSSP ESSENCE 'va_er'
(Patient Location, Full Details) and 'va_hosp' (Facility Location, Full
Details) data sources.

## Package Options

`options(sysPrep.quiet = TRUE)` suppresses the startup message shown on
[`library(sysPrep)`](https://github.com/andrew-farrey/sysPrep). Set it
in your `.Rprofile` to disable it permanently, or wrap a single call in
[`suppressPackageStartupMessages()`](https://rdrr.io/r/base/message.html)
to suppress it just once.

## See also

Useful links:

- <https://github.com/andrew-farrey/sysPrep>

- <https://andrew-farrey.github.io/sysPrep>

- Report bugs at <https://github.com/andrew-farrey/sysPrep/issues>

## Author

**Maintainer**: Andrew Farrey <afarrey11@outlook.com>
([ORCID](https://orcid.org/0000-0003-4279-0998))

Authors:

- Andrew Farrey <afarrey11@outlook.com>
  ([ORCID](https://orcid.org/0000-0003-4279-0998))
