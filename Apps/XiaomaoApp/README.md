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
- Mock Voice does not require a token, device identifier, or remote endpoint.
- Non-Mock networking fails closed until HTTPS Backend, WSS Voice, token, and
  device configuration are all present.
- `Config/Secrets.example.xcconfig` contains empty keys only. Any documentation
  example must use a reserved `.invalid` host and must be marked non-routable.
- Credential and device-binding providers are empty public shells. No real
  authentication or registration service is connected.

Public GitHub Actions and public IPA artifacts must use empty endpoint and
device configuration. Real service integration is performed only on a trusted
local Mac or in an access-controlled private build environment, using the
ignored `Config/Secrets.xcconfig` and runtime Keychain injection. Production
endpoints, credentials, device identifiers, private persona mappings, signing
materials, and private brand assets must not be supplied to public Actions.

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
