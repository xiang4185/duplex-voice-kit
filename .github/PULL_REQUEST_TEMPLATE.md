## Summary

Describe the problem and the focused change.

## Boundary check

- [ ] The change remains Provider-neutral.
- [ ] No credentials, production endpoints, user audio, transcripts, signing assets, or private deployment details are included.
- [ ] Public API additions use a stable DVK-prefixed concept or explain why not.
- [ ] Upload ordering, generation semantics, VAD behavior, reconnect policy, and audio graph recovery are preserved or explicitly tested.

## Validation

- [ ] `python3 Scripts/static_check.py`
- [ ] `swift test`
- [ ] `swift test -c release`
- [ ] iOS Simulator validation, when the change affects iOS audio behavior

## Public API / documentation

List public API changes and documentation updates, or write `None`.
