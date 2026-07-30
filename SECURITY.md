# Security Policy

## Supported versions

DuplexVoiceKit is currently pre-1.0. Security fixes are applied to the `main` branch. No older release line is supported until versioned releases are published.

## Reporting a vulnerability

Do not disclose a suspected vulnerability, credential, private endpoint, user audio, transcript, or other sensitive material in a public issue.

Prefer GitHub Private Vulnerability Reporting for this repository when it is available. If that channel is unavailable, open a public issue containing only a minimal, non-sensitive request for a private reporting channel. Do not include exploit details or production data in that issue.

A useful private report should include:

- affected commit or version;
- impact and prerequisites;
- minimal reproduction using synthetic data;
- suggested mitigation, when known;
- whether the issue involves Provider credentials, audio content, diagnostics, or transport behavior.

## Scope

Security-sensitive areas include:

- transport boundary and event decoding;
- upload ordering, generation checks, and backpressure;
- diagnostics redaction and short hashes;
- audio capture/playback lifecycle;
- Provider adapters implemented by downstream applications.

Provider authentication, backend infrastructure, and application-specific storage are outside this repository, but vulnerabilities caused by an unsafe public API boundary are in scope.

## Disclosure

Please allow reasonable time for validation and remediation before public disclosure. Confirmed reports will be acknowledged in the relevant changelog or security advisory when appropriate.
