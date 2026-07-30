# Backend Requirements

DuplexVoiceKit is an iOS client-side realtime voice core. This repository does not include a directly runnable voice backend.

## Deployment shape

```text
iOS App
   ↓ DVKTransport or DVKOutboundTransport
Compatible Voice Gateway
   ↓
Provider realtime API
```

DVK and a Voice Gateway are independent projects. DVK does not require a specific Provider, server framework, deployment platform, or gateway implementation.

## Host application requirement

A host application must choose one of these integration models:

1. implement a compatible `DVKTransport` that owns connect, send, receive, and disconnect; or
2. keep its existing WebSocket lifecycle and implement `DVKOutboundTransport` for the serial DVK upload pipeline; or
3. connect to a compatible Voice Gateway that translates the DVK protocol into a Provider-specific realtime API.

The current repository contains no built-in backend and no production Provider adapter.

## Gateway responsibilities

A compatible Voice Gateway normally owns:

- client authentication and authorization;
- secure Provider credential storage;
- Provider connection establishment and renewal;
- Provider-specific event and payload mapping;
- server-push audio delivery;
- session and server sequence continuity;
- rate limits, timeout policy, and error classification;
- privacy-safe operational diagnostics.

Provider API keys and signing secrets should remain on the server. They should not be embedded in, downloaded to, or logged by an iOS application.

## Independence and compatibility

Developers may implement their own Gateway as long as it preserves the message envelope and ordering semantics required by the host integration. A Gateway may also expose an application-specific protocol and use an adapter in the host application.

The planned related project name is `duplex-voice-gateway`. It has not been created or published, so this documentation intentionally does not include a repository link.
