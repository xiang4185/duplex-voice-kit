# Live2D Boundary

## Status

Live2D is not integrated into DuplexVoiceKit. The package contains no Live2D SDK dependency, renderer, model asset, motion file, UI layer, or character-specific behavior.

## Intended integration

A host application may translate neutral DVK outputs into character presentation:

```text
DVK session state / inbound events / playback amplitude
                         │
Host presentation adapter
                         │
Live2D state, lip sync, motions, expressions, and rendering
```

`DVKPlaybackAmplitudeSink` is the intended low-level boundary for playback amplitude. Session state and inbound events can drive higher-level states such as listening, processing, speaking, interrupted, reconnecting, or failed.

## Host responsibilities

The host application or a separate presentation package owns:

- Live2D SDK initialization and licensing;
- model, texture, motion, expression, and physics assets;
- renderer lifecycle and frame timing;
- amplitude smoothing and lip-sync parameter mapping;
- state-to-motion and state-to-expression mapping;
- SwiftUI/UIKit integration and accessibility;
- memory pressure, foreground/background, and GPU recovery behavior.

## Core restrictions

Live2D integration must not:

- move rendering work onto the audio capture callback;
- block upload ordering or transport receive loops;
- expose character assets or product-specific state through DVK public API;
- require DVK to know model names, motion identifiers, UI routes, or Provider details;
- treat amplitude callbacks as guaranteed audio-content delivery.

## Future extension rule

A future DVK API may expose a neutral presentation signal only when it is reusable without Live2D and does not introduce UI or asset dependencies. Concrete Live2D code should remain in a downstream adapter package or application target.
## Showcase visual boundary

The existing visual boundary above remains in force. The public Showcase uses SwiftUI, system shapes, gradients, materials, and deterministic procedural bars only. It contains no external image, font, character, or animation asset.
