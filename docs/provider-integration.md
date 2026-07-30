# Provider Integration

## Boundary

DuplexVoiceKit does not connect to a specific realtime voice service by itself. A host application or separate adapter package implements `DVKTransport` and, when useful, `DVKTransportFactory`. An application that already owns its WebSocket lifecycle can implement only `DVKOutboundTransport` for `DVKAudioUploadPipeline`.

```swift
public protocol DVKOutboundTransport: Sendable {
    func send(_ message: DVKOutboundMessage) async throws
}

public protocol DVKTransport: DVKOutboundTransport {
    func connect() async throws
    func events() -> AsyncStream<DVKInboundEvent>
    func disconnect() async
}
```

The repository does not include a runnable backend. See [Backend requirements](backend-requirements.md) for the compatible Gateway boundary and the planned `duplex-voice-gateway` project.

## Adapter responsibilities

A Provider adapter is responsible for:

1. obtaining credentials from the host application's secure configuration;
2. establishing and maintaining the Provider connection;
3. encoding `DVKOutboundMessage` into the Provider wire protocol;
4. decoding Provider messages into `DVKInboundEvent`;
5. preserving `sessionID`, `traceID`, sequence, response ID, timestamp, and chunk-index semantics where applicable;
6. mapping recoverable and terminal errors without exposing credentials or user content;
7. terminating its event stream and network resources on disconnect.

The adapter must not move upload ordering or `chunk_index` allocation out of the DVK upload core. Provider payload customization should be passed through neutral injected payloads rather than hard-coded into DVK.

## Authentication

Credentials must remain outside this package. Recommended patterns include short-lived tokens supplied by the host application or tokens obtained from an application-controlled backend. Never commit API keys, signing secrets, refresh tokens, or production endpoints.

Do not place credentials in event payloads, diagnostics, error descriptions, issue reports, or CI logs.

## Event mapping

An adapter should map the Provider protocol into stable DVK concepts instead of leaking vendor names through the core API. Typical mappings include:

- session ready/resumed/closed;
- server-push response start, audio delta, audio done, and cancellation;
- listening/thinking state changes;
- interrupt acknowledgement;
- degraded or error state;
- server sequence metadata.

Unknown Provider fields should be ignored or retained only inside the adapter unless they represent a reusable cross-provider capability.

## Receive stream

`events()` returns an `AsyncStream<DVKInboundEvent>`. The adapter should enforce a single clear lifecycle for each connection and avoid silently creating duplicate receive loops. Reconnection policy may be coordinated by the host using DVK's neutral reconnect primitives.

## Testing an adapter

Use an in-memory transport or a local synthetic server. Test at least:

- outbound encoding and inbound decoding;
- event ordering and server sequence handling;
- response ID mismatch rejection;
- reconnect and disconnect lifecycle;
- authentication failure classification;
- malformed payload rejection;
- absence of tokens and user content in logs.

Provider integration tests and credentials belong outside the core repository.
