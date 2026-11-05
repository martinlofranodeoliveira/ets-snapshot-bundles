# Security

ETS Snapshot Bundles 0.1.0 is a development version. No production-readiness, certification or response-time commitment is asserted.

## Reporting

If GitHub private vulnerability reporting is enabled for this repository, submit a private report at:

https://github.com/martinlofranodeoliveira/ets-snapshot-bundles/security/advisories/new

If that feature is unavailable, use the general contact options on the official [Lofrano Tecnologia homepage](https://lofranotecnologia.com.br) to arrange a private reporting channel. Do not post exploit details, secrets or personal data in public issues. Include a synthetic reproducer, affected runtime versions and the observed impact when possible.

## Boundary

This library assumes trusted code in one local BEAM instance. Protected ETS prevents non-owner writes through ordinary ETS access; it is not confidentiality or tenant isolation. Other VM code may read protected tables, forge messages or structures, alter exposed implementation terms, or kill processes. Direct raw protocol traffic, direct table access and intentional interference with private intermediaries are outside the supported API guarantees.

Admission bounds supported outstanding owner work, not raw mailbox messages, all concurrent application processes or total VM memory. Payload accounting is logical key-plus-value bytes, not physical allocation. Long-lived readers can block publication. There are no lease timeouts, persistence, transparent recovery, network authentication or distributed security guarantees.

The project has no telemetry, tracking, credentials, model dependency or external API at runtime. Tests and the demo use only synthetic fixtures.
