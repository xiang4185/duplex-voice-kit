# Contributing to DuplexVoiceKit

Thank you for helping improve DuplexVoiceKit.

## Before opening a change

- Keep the package Provider-neutral.
- Do not add production credentials, endpoints, audio, transcripts, device identifiers, signing assets, or private deployment details.
- Discuss broad public API or architecture changes in an issue before implementation.
- Prefer focused changes that preserve upload ordering, generation semantics, VAD parameters, reconnect behavior, and audio graph recovery rules.

## Development workflow

1. Fork the repository and create a focused branch from `main`.
2. Make the smallest change that solves the problem.
3. Add or update tests for behavior changes.
4. Run:

   ```bash
   python3 Scripts/static_check.py
   swift test
   swift test -c release
   ```

5. On macOS, also verify the package against an available iOS Simulator with Xcode.
6. Open a pull request describing the motivation, behavior impact, test evidence, and public API changes.

## Code expectations

- Swift 5.10 compatibility is required.
- The minimum deployment target remains iOS 17 unless a separately reviewed change justifies otherwise.
- Avoid replacing the existing concurrency model without a demonstrated correctness need.
- Do not use sleeps to hide races.
- Do not weaken bounded queues, backpressure, stale-generation rejection, sequence filtering, or diagnostics privacy.
- Keep implementation details internal unless downstream integration requires a stable public API.
- New public symbols should normally use the `DVK` prefix.

## Provider integrations

Provider-specific adapters belong in downstream packages or applications. A contribution to the core may define a neutral capability, event, or injection point, but it must not embed a vendor SDK, authentication scheme, production URL, model identifier, or proprietary protocol assumption.

## Tests

Tests should be deterministic and use synthetic audio or in-memory transports. Pull requests must not delete tests merely to make a migration pass.

The public CI runs static checks and real iOS Simulator tests on GitHub-hosted macOS infrastructure.

## Documentation

Update README or files under `docs/` when changing architecture, integration boundaries, security behavior, requirements, or public API.

## License

By submitting a contribution, you agree that it is licensed under the Apache License 2.0.
