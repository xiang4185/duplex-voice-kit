# XiaomaoApp

This directory contains the complete runnable Xiaomao iOS application target.
It uses the repository's `DuplexVoiceKit` package through the local `../..`
path, so the app, package, tests, and IPA workflow build from one source tree.

## Public default

- Debug uses loopback endpoints and offline mock voice.
- Release contains no API endpoint, WebSocket endpoint, device identifier,
  credential, certificate, signing profile, chat record, or audio record.
- Live values may be supplied only at build time or entered at runtime and are
  never committed.

## Generate and build

```bash
cd Apps/XiaomaoApp
xcodegen generate
xcodebuild \
  -project XiaomaoApp.xcodeproj \
  -scheme XiaomaoApp \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Run `python3 Scripts/static_check.py` before generating the project.

## Asset provenance

The app icon and cat portrait/avatar PNG files were generated for this project
with an AI image-generation tool and are contributed by the repository owner
for use under this repository's license. They contain no third-party font,
model, SDK, user photo, or embedded metadata required by the application.
