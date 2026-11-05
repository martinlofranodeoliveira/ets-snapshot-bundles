# Contributing

Use Elixir 1.18 or newer with compatible OTP. No Hex dependency installation is needed.

```sh
mix compile
mix test --seed 0
mix run demo/demo.exs
mix format
```

Describe the behavior being changed and update `docs/contract.md` when observable results or bounds change. Preserve the development version's explicit error vocabulary, same-PID leases, instance identity and no-history resource accounting unless proposing a documented contract change.

Add regression tests with independent expected values and synthetic data. Concurrency tests should use monitors, message barriers, OTP system suspension or the documented test-only admission seams, not sleeps. A test's receipt of reader DOWN alone does not prove the index has handled its separate DOWN; establish an owner-side barrier. Verify actual tables and monitors when changing reclamation.

Do not add secrets, personal data, private client code, telemetry, external runtime services, publishing workflows or unsupported performance claims. Discuss new dependencies before introducing them; the current project intentionally uses only OTP and Elixir standard facilities.

Issues and pull requests belong at https://github.com/martinlofranodeoliveira/ets-snapshot-bundles . General organizational contact is the [official homepage](https://lofranotecnologia.com.br). Do not disclose security vulnerabilities in public issues; see [SECURITY.md](SECURITY.md).
