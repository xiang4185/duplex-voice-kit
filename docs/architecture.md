# Architecture

## Purpose

DuplexVoiceKit isolates the reusable realtime voice core from product UI, authentication, Provider SDKs, backend deployment, and character presentation.

## Layers

```text
Host application
  ├─ UI and product state
  ├─ authentication and configuration
  └─ Provider adapter
       └─ DVKTransport / DVKTransportFactory
            └─ DuplexVoiceKit core
                 ├─ protocol envelopes and sequence tracking
                 ├─ response and server-sequence filtering
                 ├─ VAD / commit / interrupt
                 ├─ serial upload actor
                 ├─ reconnect policy
                 └─ privacy-safe diagnostics
                      └─ iOS audio layer
                           ├─ AVAudioSession
                           └─ one full-duplex AVAudioEngine
```

## Audio ownership

`DVKRealtimeAudioIO` owns a single `AVAudioEngine` for microphone capture and assistant playback. Muting removes capture delivery without replacing the playback engine. The implementation observes audio interruptions, route changes, media-services reset, and engine configuration changes, rebuilding the graph when necessary.

Capture callbacks copy owned audio data and synchronously offer packets to `DVKAudioCaptureSink`. They do not perform network sends, JSON encoding, resampling, or per-frame task creation.

## Upload ordering

The internal upload actor owns one long-running drain task and a bounded nonblocking ingress queue. It is the sole allocator of client sequence and `chunk_index` values.

Each packet carries capture generation metadata. Queue items also carry connection generation metadata. A packet is processed only when both generations match the active state. A new generation clears partial PCM and stale work is rejected without mutating the active generation.

Backpressure closes admission for the active generation and reports a failure rather than allowing unbounded memory growth.

## Interaction state

The VAD preserves fixed realtime thresholds for normal listening and barge-in. It emits speech-start, audio, commit, and rejected-noise actions. Interrupt messages are explicit and response audio is accepted only when response identity and server sequence are current.

## Public and internal API

Public API is limited to stable integration concepts such as session state, configuration, transport, events, diagnostics, capture sink, playback-amplitude sink, response filtering, reconnect policy, audio session, and realtime audio I/O.

Queue internals, generation bookkeeping, VAD storage, codec sequence allocation, diagnostics storage, and upload drain implementation remain internal.

## Deliberate exclusions

DVK does not contain Provider implementations, authentication, production endpoints, backend services, SwiftUI screens, application coordination, signing configuration, Live2D rendering, user content, or deployment automation.
