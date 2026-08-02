# Security and Privacy

## Trust boundary

DuplexVoiceKit processes realtime audio in memory and exposes neutral transport and diagnostic interfaces. The host application remains responsible for user consent, authentication, data retention, network policy, Provider terms, and platform privacy declarations.

## Repository rules

The public repository must not contain:

- Provider tokens, API keys, private keys, certificates, or signing profiles;
- production domains or private deployment instructions;
- user recordings, cloned-voice samples, transcripts, chat text, or database files;
- device allowlists, personal identifiers, proprietary prompts, or model assets;
- application archives or release-signing configuration.

Synthetic test audio and example endpoints must be obviously non-production and contain no user data.

## Diagnostics

`DVKDiagnosticsSnapshot` is designed for operational ordering and health analysis. It may contain counters, generations, queue depth, recent chunk indices, state, timing, safe categories, and short hashes.

Diagnostics must not include:

- authorization headers or tokens;
- transcripts or message bodies;
- base64 audio or raw PCM;
- Provider speaker or cloned-voice identifiers;
- full session identifiers when a short hash is sufficient.

Downstream applications should apply the same rule when extending diagnostics.

## Audio lifecycle

Captured buffers are copied into owned packet data before leaving the realtime callback. Partial PCM is cleared when capture generation changes, capture pauses, a connection aborts, backpressure occurs, or a send failure invalidates the active generation.

Applications should avoid persisting raw audio unless the user has explicitly consented and the product has a documented retention policy.

## Transport security

A Provider adapter should use authenticated encrypted transport, validate server identity through platform networking, use short-lived credentials when possible, and classify failures without embedding response bodies in logs.

DVK intentionally does not implement certificate pinning or a global authentication scheme because those policies belong to the host application and Provider adapter.

## Public reporting

Never place sensitive details in a public issue or pull request. Follow `SECURITY.md` for private vulnerability reporting. Reproductions should use synthetic payloads and redacted identifiers.

## Static enforcement

`Scripts/static_check.py` checks required boundaries, common sensitive file extensions, product/Provider terms, production WebSocket literals, upload invariants, realtime callback constraints, and prohibited diagnostic fields. Static checks supplement review; they do not replace secret scanning or application-level privacy review.
## Public Showcase boundary

The existing security guidance above remains in force. The Showcase adds no credentials, production address, provider SDK, real audio, persistent database, or user identity. Limited privacy keeps the page browsable, blocks voice actions explicitly, and exposes a local re-authorization callback without presenting a system permission prompt.
