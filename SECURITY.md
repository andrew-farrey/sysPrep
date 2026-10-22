# Security and data-exposure policy

## Reporting a security problem

`sysPrep` is an offline R package: it does not open network connections,
store credentials, or run a service. If you believe you have found a
vulnerability (for example, code that could execute untrusted input),
please report it privately through GitHub’s “Report a vulnerability”
button on the [Security
tab](https://github.com/andrew-farrey/sysPrep/security), or email the
maintainer at the address in the `DESCRIPTION` file. Please do not open
a public issue for a vulnerability.

## Accidentally posted sensitive data

`sysPrep` processes syndromic surveillance records, which can be
sensitive. If patient-level data, identifiable facility information, or
anything covered by a data use agreement has been posted in an issue,
pull request, or comment (including in a screenshot or copied console
output), please contact the maintainer immediately by the same private
routes so it can be removed. Do not wait for a reply before editing or
deleting your own post.

Please reproduce problems with the package’s synthetic datasets instead;
see
[CONTRIBUTING.md](https://andrew-farrey.github.io/sysPrep/CONTRIBUTING.md).

## Supported versions

Fixes are made to the current release only.
