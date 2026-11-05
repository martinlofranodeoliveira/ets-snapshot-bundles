# Runtime identity and reproducibility

The source targets Elixir 1.18 (such as Elixir 1.18.6 on OTP 28) and newer compatible runtimes, including Elixir 1.20.5 on OTP 29. There are no Hex or other library dependencies. Mix, ExUnit, ETS, monitors, aliases and atomics are supplied by Elixir/OTP.

Because container image tags such as `elixir:1.18` and `elixir:1.20.5` can resolve to different image digests over time, the CI workflow records the resolved image identity for each run:

1. Pull the official `elixir:1.18` or `elixir:1.20.5` image.
2. Print Docker's `RepoDigests` for the resolved image.
3. Run `elixir --version` inside that image before the tests.
4. Run the deterministic test seed and asserting demo with container networking disabled.

Retain the exact digest line and complete version output from the environment log when reproducing a run. The workflow does not publish images, packages or releases.

Local version observation:

```sh
elixir --version
mix run -e 'IO.puts("OTP " <> System.otp_release())'
```

For an available Docker image, inspect its resolved digest and version locally:

```sh
docker image inspect elixir:1.18 --format '{{json .RepoDigests}}'
docker run --rm --network none elixir:1.18 elixir --version
```

The demo reports the active Elixir and OTP release strings at runtime. Compilation and tests require no network access or external dependency preparation.
