# CI preflight history audit

Audit date: 2026-08-03

## Scope and method

The audit queried the most recent 100 runs of the public `CI` workflow and received 23 runs. Eight runs had conclusion `failure`; three additional runs were cancelled and were not classified as failures. Each failed run was inspected with its run summary and failed-step log. Only the minimum compiler or build error needed to identify the root cause is recorded below.

Historical run identifiers and commit identifiers are documentation only. Daily preflight scripts do not call GitHub, do not contain historical identifiers, and do not make network requests.

## Tool position and local use

`Scripts/ci_failure_preflight.py` is a Push-before-local preflight and a lightweight recovery tool for deterministic failure patterns observed in historical CI. It supplements Swift and Xcode compilation; it does not replace them.

The tool is not a GitHub Actions automatic gate, a Swift compiler replacement, a general Swift linter, or a complete YAML or Swift parser.

Run the following from the repository root before pushing repository changes:

```bash
python3 Scripts/ci_failure_preflight.py
python3 -m unittest discover \
  -s Scripts/tests \
  -p 'test_*.py' \
  -v
python3 Scripts/static_check.py
```

This order runs the historical failure preflight, its unit tests, and then the repository's original static checks. GitHub Actions does not currently execute `ci_failure_preflight.py`; developers and execution roles must invoke it locally before Push. A pull request still triggers the repository's existing CI normally, but that workflow does not call this tool.

## Failed run matrix

| Run ID | Time (UTC) | Branch | Commit | Job / Step | Error summary | Root cause | Fix commit | Locally discoverable | Proposed rule | False-positive risk | Final handling |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 30761082634 | 2026-08-02 18:25:34 | `codex/v70-r3a1-ios26-liquid-glass` | `fbdfa6fb4d19f31b912623a4c90f4a251d7902e4` | iOS Simulator tests / Build and test on iOS Simulator | `String` could not convert to `PrimitiveButtonStyleConfiguration` in two UI contract tests. | `Button("Title")` was used without an action closure, and SwiftUI overload resolution selected an incompatible construction path. | `5f8115c49dae347a401f449376a10ffff5a29e2c` | Partial | None; keep Swift compiler validation | Medium to high for text-only matching because `Button` may be shadowed or have context-dependent overloads | Documentation only |
| 30760797951 | 2026-08-02 18:17:54 | `codex/v70-r3a1-ios26-liquid-glass` | `125683a0c5ed70d17ae480e3f34d2e346f56ef0a` | iOS Simulator tests / Build and test on iOS Simulator | `tabViewBottomAccessory(isEnabled:content:)` is available only on iOS 26.1 or newer. | The call was enclosed by `#available(iOS 26.0, *)`, which was too weak for the exact overload. | `fbdfa6fb4d19f31b912623a4c90f4a251d7902e4` | Yes | `tab-view-bottom-accessory-availability` | Low | Automatic gate |
| 30757800393 | 2026-08-02 16:57:36 | `codex/v70-r3a-multicat-showcase` | `763ea1f60d3e159533f56988aecc8a1ed2bbbc09` | iOS Simulator tests / Build and test on iOS Simulator | Two functions declared `some View` but had no explicit return from which to infer the opaque type. | Multi-statement helpers declared local values before their final SwiftUI expression and omitted `return`. | `c8fe89d0acc24ae435f82d140fc9087fdbf95d53` | Partial | Candidate rejected; keep Swift compiler validation | High for a lightweight regex because `@ViewBuilder`, single-expression helpers, nested closures, and conditional builders are valid counterexamples | Documentation only |
| 30757588578 | 2026-08-02 16:51:48 | `codex/v70-r3a-multicat-showcase` | `b48e36240290f0296f1b69749e2915bf13fe45ae` | iOS Simulator tests / Build and test on iOS Simulator | `.red` could not satisfy a `HierarchicalShapeStyle` context; two `some View` helpers also lacked return statements. | One ternary mixed implicit `.secondary` with implicit `.red`; separate multi-statement helpers omitted `return`. | `763ea1f60d3e159533f56988aecc8a1ed2bbbc09` for ShapeStyle, then `c8fe89d0acc24ae435f82d140fc9087fdbf95d53` for opaque returns | Yes for the known ShapeStyle form; partial for opaque returns | `foreground-style-ternary`; opaque-return candidate rejected | Low for the narrow ShapeStyle rule; high for a generic opaque-return regex | Automatic gate for ShapeStyle; opaque return documented only |
| 30752841522 | 2026-08-02 14:46:11 | `codex/v70-dvk-public-showcase-r2` | `75482ba53be0ec153045da8ba46afabf43686846` | iOS Simulator tests / Build and test on iOS Simulator | Call to a main-actor-isolated initializer occurred in a synchronous nonisolated default-argument context. | `DVKCompanionStore()` was constructed as the default value of a `store` parameter in UI initializers. | `fabb3db0b80024d88aa2976c489555b0907e150b` | Yes for the known form | `main-actor-store-default` | Low because the rule is limited to the exact `DVKCompanionStore` default parameter under `Sources/DuplexVoiceKitUI` | Automatic gate |
| 30752478421 | 2026-08-02 14:36:30 | `codex/v70-dvk-public-showcase-r2` | `93c053e31f533718065f3ffc875dc738d29703c5` | iOS Simulator tests / Build and test on iOS Simulator | Scheme `DuplexVoiceKit` was not configured for the test action. | The iOS Simulator package test command used a product scheme instead of the Swift package test scheme. | `75482ba53be0ec153045da8ba46afabf43686846` | Yes | `ios-package-test-scheme` | Low | Automatic gate |
| 30748976223 | 2026-08-02 12:59:30 | `codex/v70-dvk-public-showcase` | `a8fa15f25fbda152dc2f3818c27ee906af081fa9` | iOS Simulator Showcase build / Build Showcase on iOS Simulator | Build input `DVKCompanionShowcase.app/Info.plist` could not be found. | The generated Showcase project neither generated an Info.plist nor pointed to an existing explicit plist file. | `63b7b1428127e9486b166dd10d3576ad5f90f257` | Yes | `showcase-info-plist` | Low | Automatic gate |
| 30748698687 | 2026-08-02 12:51:17 | `codex/v70-dvk-public-showcase` | `79d6ad2fea34422838c84f3d10ade5e862b86257` | iOS Simulator tests / Build and test on iOS Simulator | Scheme `DuplexVoiceKit` was not configured for the test action. | The iOS Simulator command attempted `test` with a non-testable product scheme. | `aa8ad90e2f2416ebbb0dde47eea52b4051f5ae63` removed that invalid test command; the later durable package-test form uses `DuplexVoiceKit-Package` | Yes | `ios-package-test-scheme` | Low | Automatic gate |

## Independent root causes and decisions

The eight failed runs contain seven independent root causes.

| Root cause | Runs | Static rule decision | Reason |
| --- | --- | --- | --- |
| Exact iOS 26.1 availability for `tabViewBottomAccessory(isEnabled:)` | 30760797951 | Automatic | The API spelling and minimum version are exact. The implementation proves that each call is inside an enclosing `if #available(iOS 26.1, *)` or newer block; an unrelated repository-wide `26.1` string cannot satisfy the rule. |
| Invalid action-less SwiftUI `Button` construction | 30761082634 | Documentation only | A text rule cannot reliably prove which `Button` symbol or overload Swift resolves. The Swift compiler remains the authoritative gate. |
| Multi-statement `some View` helper missing explicit return | 30757588578, 30757800393 | Documentation only | A safe lightweight rule would need to distinguish result builders, single-expression functions, nested closures, conditionals, and declarations. A simple “all `some View` functions need return” rule would be wrong. |
| Conditional ShapeStyle type inference mixes hierarchical style and Color | 30757588578 | Automatic | The rule only rejects direct `foregroundStyle` ternaries where one branch is an implicit hierarchical style and the other is an implicit concrete Color. Explicit `Color.secondary` and `Color.red` pass. |
| MainActor-isolated store construction in a default parameter | 30752841522 | Automatic | The rule is intentionally limited to `store: DVKCompanionStore = DVKCompanionStore()` under the UI source directory. Comments and string contents are masked before matching, while offsets remain aligned for source line reporting. It does not reject `public init()` or `public init(store: DVKCompanionStore)`. |
| Non-testable scheme used for iOS package tests | 30748698687, 30752478421 | Automatic | At least one logical iOS Simulator `xcodebuild test` command must use `DuplexVoiceKit-Package`, and an explicit Simulator test using `DuplexVoiceKit` is rejected. Other testable schemes may coexist and are not treated as package-scheme violations. |
| Missing Showcase Info.plist generation or input | 30748976223 | Automatic | `targets.DVKCompanionShowcase` must either set `GENERATE_INFOPLIST_FILE: YES` or set `INFOPLIST_FILE` to a file that actually exists inside the repository. Configuration under another target and merely containing the text `Info.plist` are insufficient. |

## Implemented preflight rules

`Scripts/ci_failure_preflight.py` contains five deterministic standard-library checks:

1. `tab-view-bottom-accessory-availability`
2. `showcase-info-plist`
3. `ios-package-test-scheme`
4. `main-actor-store-default`
5. `foreground-style-ternary`

The module has an independent command-line entry point. `python3 Scripts/ci_failure_preflight.py` resolves the repository root from the script location, prints one deterministic JSON line, and exits with status 0 when no failures are found or status 1 when rules fail. Each failure includes the repository-relative file, a rule name, and a line number when the source match has one.

`Scripts/static_check.py` and the GitHub Actions workflow do not import, call, or otherwise run this module. The module performs no network access, does not invoke `gh`, Xcode, Swift, or XcodeGen, does not inspect paths outside the repository, and does not depend on a branch or commit identifier.

## Positive and negative examples

| Rule | Passing example | Failing example |
| --- | --- | --- |
| Availability | The call is inside `if #available(iOS 26.1, *) { ... }`. | The same call is inside only `if #available(iOS 26.0, *) { ... }`. |
| Availability silence | Source does not use `tabViewBottomAccessory(isEnabled:)`. | Not applicable; absence is intentionally silent. |
| Showcase Info.plist | `targets.DVKCompanionShowcase` contains `GENERATE_INFOPLIST_FILE: YES`, or an explicit existing repository-local plist path. | Showcase has no valid configuration, even when another target generates its plist. |
| iOS package scheme | Simulator Package tests use `DuplexVoiceKit-Package`; unrelated testable schemes may coexist. | `DuplexVoiceKit` is used for a Simulator test, or no `DuplexVoiceKit-Package` Simulator test exists. |
| MainActor store default | Separate `init(store:)` and no-argument initializer; matching text in comments or strings is ignored. | A real declaration contains `store: DVKCompanionStore = DVKCompanionStore()`. |
| ShapeStyle ternary | `.foregroundStyle(condition ? Color.secondary : Color.red)`. | `.foregroundStyle(condition ? .secondary : .red)`. |

The unittest suite uses temporary directories and source fixtures. It does not modify repository source files and does not use constant-true assertions.

## Compiler-only verification retained

The following failures remain intentionally delegated to Swift/Xcode validation:

- Opaque `some View` return inference across result-builder and multi-statement function bodies.
- SwiftUI symbol and overload resolution, including action-less `Button` construction.
- API availability expressed through forms not covered by the exact runtime `if #available` rule, such as future language or annotation patterns.
- General actor isolation beyond the exact `DVKCompanionStore` default-parameter pattern.
- General ShapeStyle inference beyond the direct, known-dangerous `foregroundStyle` ternary.
- Xcode project generation semantics and build-system inputs beyond the two accepted Info.plist configurations.

These boundaries keep the preflight small and predictable rather than approximating a Swift parser or compiler.
