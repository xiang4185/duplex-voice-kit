#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "Sources" / "DuplexVoiceKit"
TESTS = ROOT / "Tests" / "DuplexVoiceKitTests"

REQUIRED = [
    "Package.swift",
    "README.md",
    "LICENSE",
    "SECURITY.md",
    "CONTRIBUTING.md",
    "CODE_OF_CONDUCT.md",
    "CHANGELOG.md",
    ".gitignore",
    ".github/workflows/ci.yml",
    "Examples/README.md",
    "docs/architecture.md",
    "docs/provider-integration.md",
    "docs/backend-requirements.md",
    "docs/security-and-privacy.md",
    "docs/live2d-boundary.md",
    "Sources/DuplexVoiceKit/DVKModels.swift",
    "Sources/DuplexVoiceKit/DVKProtocolCore.swift",
    "Sources/DuplexVoiceKit/DVKAudioConfiguration.swift",
    "Sources/DuplexVoiceKit/DVKAudioSession.swift",
    "Sources/DuplexVoiceKit/DVKRealtimeAudioIO.swift",
    "Sources/DuplexVoiceKit/DVKAudioUploadActor.swift",
    "Sources/DuplexVoiceKit/DVKAudioUploadPipeline.swift",
    "Sources/DuplexVoiceKit/DVKDiagnostics.swift",
    "Tests/DuplexVoiceKitTests/DVKAudioUploadActorTests.swift",
    "Tests/DuplexVoiceKitTests/DVKAudioUploadPipelinePublicTests.swift",
    "Tests/DuplexVoiceKitTests/DVKVoiceActivityDetectorTests.swift",
    "Tests/DuplexVoiceKitTests/DVKProtocolTests.swift",
    "Tests/DuplexVoiceKitTests/DVKReconnectPolicyTests.swift",
    "Tests/DuplexVoiceKitTests/DVKDiagnosticsTests.swift",
]

SENSITIVE_NAMES = {".env", "Secrets.xcconfig"}
SENSITIVE_SUFFIXES = {
    ".p12", ".pfx", ".pem", ".key", ".cer", ".crt", ".mobileprovision",
    ".db", ".sqlite", ".sqlite3", ".db-wal", ".db-shm",
    ".wav", ".mp3", ".m4a", ".pcm", ".ipa", ".env",
}

FORBIDDEN_SOURCE_TERMS = (
    "Xiaomao",
    "xiaomao",
    "SwiftUI",
    "AppCoordinator",
    "DeviceBinding",
    "VoiceCallView",
    "ChatView",
    "VOLC_",
    "SpeakerID",
    "SC2.0",
    "api.openai",
    "wss://",
    "systemd",
    "cloudflared",
)

FORBIDDEN_REPOSITORY_TERMS = (
    "/srv/yusuan",
    "memory-v2.db",
    "wechat-52-ledger",
    "Xiaomao",
    "xiaomao",
    "VOLC_",
    "SpeakerID=",
    "api.openai",
    "wss://",
)

SECRET_ASSIGNMENT_PATTERN = re.compile(
    r"(?i)(?:api[_-]?key|access[_-]?token|refresh[_-]?token|secret|authorization)"
    r"\s*[:=]\s*[\"'][^\"']{8,}[\"']"
)

REQUIRED_PUBLIC_SYMBOLS = (
    "DVKSessionState",
    "DVKAudioConfiguration",
    "DVKInboundEvent",
    "DVKOutboundMessage",
    "DVKOutboundTransport",
    "DVKTransport",
    "DVKTransportFactory",
    "DVKAudioUploadPipeline",
    "DVKAudioUploadIntent",
    "DVKAudioUploadNotification",
    "DVKAudioUploadError",
    "DVKAudioUploadDiagnosticsSnapshot",
    "DVKVoiceActivityMode",
    "DVKVoiceActivityState",
    "DVKVoiceActivityCommitReason",
    "DVKVoiceActivityConfiguration",
    "DVKVoiceActivityAction",
    "DVKVoiceActivityAnalysis",
    "DVKVoiceActivityDetector",
    "DVKDiagnosticsSnapshot",
    "DVKAudioCaptureSink",
    "DVKPlaybackAmplitudeSink",
)


def repository_files() -> list[Path]:
    ignored_parts = {".git", ".build", ".swiftpm", "DerivedData", "__pycache__"}
    return [
        path for path in ROOT.rglob("*")
        if path.is_file()
        and not ignored_parts.intersection(path.relative_to(ROOT).parts)
    ]


def main() -> None:
    failures: list[str] = []
    for relative in REQUIRED:
        if not (ROOT / relative).is_file():
            failures.append("missing required file: " + relative)

    files = repository_files()
    swift_files = [path for path in files if path.suffix == ".swift"]
    test_files = [path for path in swift_files if TESTS in path.parents]

    for path in files:
        relative = path.relative_to(ROOT)
        if path.name in SENSITIVE_NAMES or path.suffix.lower() in SENSITIVE_SUFFIXES:
            failures.append("sensitive file path: " + str(relative))
        if path.is_symlink():
            failures.append("symlink is not allowed: " + str(relative))
        scans_as_text = (
            path.suffix.lower() in {".md", ".py", ".swift", ".yml", ".yaml"}
            or path.name in {"LICENSE", "Package.swift"}
        )
        if scans_as_text and relative.as_posix() != "Scripts/static_check.py":
            text = path.read_text(encoding="utf-8")
            allowed_reference_doc = (
                relative.as_posix() in {
                    "README.md",
                    "Examples/README.md",
                    "Examples/DVKCompanionShowcase/README.md",
                    "CHANGELOG.md",
                    "docs/architecture.md",
                    "docs/security-and-privacy.md",
                    "docs/live2d-boundary.md",
                    "docs/profile-routing.md",
                }
            )
            for forbidden in FORBIDDEN_REPOSITORY_TERMS:
                if forbidden in text and not (
                    allowed_reference_doc and forbidden in {"Xiaomao", "xiaomao"}
                ):
                    failures.append(
                        f"forbidden private/provider term {forbidden!r}: {relative}"
                    )
            is_negative_test_fixture = TESTS in path.parents
            if (
                not is_negative_test_fixture
                and (SECRET_ASSIGNMENT_PATTERN.search(text) or "-----BEGIN PRIVATE KEY-----" in text)
            ):
                failures.append("possible embedded secret: " + str(relative))

    package_text = (ROOT / "Package.swift").read_text(encoding="utf-8")
    for expected in (
        "// swift-tools-version: 5.10",
        'name: "DuplexVoiceKit"',
        '.iOS(.v17)',
        'name: "DuplexVoiceKitTests"',
        'swiftLanguageVersions: [.v5]',
    ):
        if expected not in package_text:
            failures.append("Package.swift missing: " + expected)

    readme_text = (ROOT / "README.md").read_text(encoding="utf-8")
    for expected in (
        "# DuplexVoiceKit",
        "A provider-neutral realtime voice framework for iOS.",
        "面向 iOS 的实时双向语音交互核心。",
        "https://github.com/xiang4185/duplex-voice-kit.git",
        "iOS 17+",
        "Swift 5.10+",
    ):
        if expected not in readme_text:
            failures.append("README.md missing: " + expected)

    license_text = (ROOT / "LICENSE").read_text(encoding="utf-8")
    if "Apache License" not in license_text or "Version 2.0, January 2004" not in license_text:
        failures.append("LICENSE is not Apache-2.0 text")

    workflow_text = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
    for expected in (
        "runs-on: macos-latest",
        "xcrun simctl list devices available -j",
        "platform=iOS Simulator",
        "xcodebuild",
        "swift test -c release",
        "xcodegen generate",
        "DVKCompanionShowcase.xcodeproj",
        "scheme DVKCompanionShowcase",
    ):
        if expected not in workflow_text:
            failures.append("CI workflow missing: " + expected)

    test_method_count = 0
    for test_path in TESTS.glob("*.swift"):
        test_method_count += len(re.findall(r"\bfunc\s+test[A-Za-z0-9_]+\s*\(", test_path.read_text(encoding="utf-8")))
    if test_method_count < 22:
        failures.append(f"expected at least 22 test methods, found {test_method_count}")

    source_texts: dict[Path, str] = {}
    for path in SOURCES.glob("*.swift"):
        text = path.read_text(encoding="utf-8")
        source_texts[path] = text
        if text.count("{") != text.count("}"):
            failures.append("brace mismatch: " + str(path.relative_to(ROOT)))
        for forbidden in FORBIDDEN_SOURCE_TERMS:
            if forbidden in text:
                failures.append(
                    f"forbidden product/provider term {forbidden!r}: {path.relative_to(ROOT)}"
                )

    combined_source = "\n".join(source_texts.values())
    for symbol in REQUIRED_PUBLIC_SYMBOLS:
        if not re.search(rf"public\s+(?:final\s+)?(?:struct|enum|protocol|class)\s+{symbol}\b", combined_source):
            failures.append("missing public symbol: " + symbol)

    uploader_path = SOURCES / "DVKAudioUploadActor.swift"
    uploader = source_texts.get(uploader_path, "")
    pipeline = source_texts.get(SOURCES / "DVKAudioUploadPipeline.swift", "")
    models = source_texts.get(SOURCES / "DVKModels.swift", "")
    if "public protocol DVKTransport: DVKOutboundTransport" not in models:
        failures.append("DVKTransport must inherit the send-only transport boundary")
    if "private let transport: any DVKOutboundTransport" not in uploader:
        failures.append("upload actor must depend only on DVKOutboundTransport")
    if re.search(r"public\s+actor\s+DVKAudioUploadActor\b", uploader):
        failures.append("internal upload actor must not be public")
    if "public final class DVKAudioUploadPipeline" not in pipeline:
        failures.append("public upload pipeline facade is missing")
    for forbidden in ("DispatchSemaphore", "CheckedContinuation", "drainTask", "NSLock"):
        if forbidden in pipeline:
            failures.append("public upload facade exposes internal mechanism: " + forbidden)
    if uploader.count("drainTask = Task") != 1:
        failures.append("upload actor must own exactly one long-running drain task")
    if "DispatchSemaphore" not in uploader or ".wait(timeout: .now())" not in uploader:
        failures.append("upload ingress must use bounded nonblocking admission")
    if "ingress.remove(generation: generation)" not in uploader:
        failures.append("upload cleanup must remain generation-scoped")
    if "packet.captureGeneration < captureGeneration" not in uploader:
        failures.append("stale capture generation rejection is missing")
    if "pendingPCM16.removeAll" not in uploader:
        failures.append("partial PCM cleanup is missing")
    if '"chunk_index": .int(index)' not in uploader:
        failures.append("chunk_index allocation is missing from upload actor")
    for path, text in source_texts.items():
        if path == uploader_path:
            continue
        if '"chunk_index": .int' in text:
            failures.append("chunk_index allocation outside upload actor: " + str(path.relative_to(ROOT)))

    realtime = source_texts.get(SOURCES / "DVKRealtimeAudioIO.swift", "")
    tap_start = realtime.find("input.installTap")
    tap_end = realtime.find("tapInstalled = true", tap_start)
    handler_start = realtime.find("private func handleCaptureBuffer")
    handler_end = realtime.find("private func copyCapturedPacket", handler_start)
    if min(tap_start, tap_end, handler_start, handler_end) < 0:
        failures.append("realtime capture tap path could not be inspected")
    else:
        realtime_tap_path = realtime[tap_start:tap_end] + realtime[handler_start:handler_end]
        for forbidden in (
            "Task", "await", ".send(", "chunkIndex", "JSONEncoder",
            "base64EncodedString", ".lock()",
        ):
            if forbidden in realtime_tap_path:
                failures.append("realtime capture tap contains prohibited work: " + forbidden)
        if "copyCapturedPacket" not in realtime_tap_path or "sink?.offer" not in realtime_tap_path:
            failures.append("realtime capture tap must copy owned data and offer to a sink")

    backend_text = (ROOT / "docs/backend-requirements.md").read_text(encoding="utf-8")
    for expected in (
        "iOS App",
        "Compatible Voice Gateway",
        "Provider realtime API",
        "duplex-voice-gateway",
        "has not been created or published",
    ):
        if expected not in backend_text:
            failures.append("backend requirements missing: " + expected)
    if "docs/backend-requirements.md" not in readme_text:
        failures.append("README must link backend requirements")

    diagnostics = source_texts.get(SOURCES / "DVKDiagnostics.swift", "").lower()
    for forbidden in ("authorization=", "speaker_id=", "transcript=", "audio_base64="):
        if forbidden in diagnostics:
            failures.append("diagnostics contains prohibited field: " + forbidden)

    r2_required = (
        "Sources/DuplexVoiceKitCompanion/DVKCompanionModels.swift",
        "Sources/DuplexVoiceKitCompanion/DVKCompanionStore.swift",
        "Sources/DuplexVoiceKitUI/DVKCompanionViews.swift",
        "Sources/DuplexVoiceKitUI/DVKPlaybackAmplitudeView.swift",
        "Tests/DuplexVoiceKitCompanionTests/DVKCompanionBehaviorTests.swift",
        "Tests/DuplexVoiceKitUITests/DVKCompanionUIContractTests.swift",
        "Examples/DVKCompanionShowcase/project.yml",
        "Examples/DVKCompanionShowcase/DVKCompanionShowcase/App.swift",
    )
    for relative in r2_required:
        if not (ROOT / relative).is_file():
            failures.append("missing R2 required file: " + relative)

    companion_root = ROOT / "Sources" / "DuplexVoiceKitCompanion"
    ui_root = ROOT / "Sources" / "DuplexVoiceKitUI"
    companion_text = "\n".join(p.read_text(encoding="utf-8") for p in companion_root.glob("*.swift"))
    for forbidden in ("SwiftUI", "UIKit", "AppKit", "AVFoundation", "ActivityKit", "Combine"):
        if forbidden in companion_text:
            failures.append("Companion must remain Foundation-only: " + forbidden)
    ui_text = "\n".join(p.read_text(encoding="utf-8") for p in ui_root.glob("*.swift"))
    if "DVKCompanionStore" not in ui_text:
        failures.append("UI must consume DVKCompanionStore")
    if "@State private var draft" in ui_text or "@State private var messages" in ui_text:
        failures.append("UI must not duplicate Store business state")
    r2_tests = [
        p for p in repository_files()
        if p.suffix == ".swift"
        and ("DuplexVoiceKitCompanionTests" in p.parts or "DuplexVoiceKitUITests" in p.parts)
    ]
    r2_test_text = "\n".join(p.read_text(encoding="utf-8") for p in r2_tests)
    if "XCTAssertTrue(true)" in r2_test_text:
        failures.append("恒真测试 is forbidden")
    r2_test_methods = sum(
        len(re.findall(r"\bfunc\s+test[A-Za-z0-9_]+\s*\(", p.read_text(encoding="utf-8")))
        for p in r2_tests
    )
    if r2_test_methods < 24:
        failures.append(f"expected at least 24 R2 test methods, found {r2_test_methods}")
    for p in list(companion_root.glob("*.swift")) + list(ui_root.glob("*.swift")):
        source = p.read_text(encoding="utf-8")
        if source.count("{") != source.count("}"):
            failures.append("R2 brace mismatch: " + str(p.relative_to(ROOT)))

    r3_required = (
        "Sources/DuplexVoiceKitUI/DVKCompanionTheme.swift",
        "Sources/DuplexVoiceKitUI/DVKCharacterViews.swift",
        "Examples/DVKCompanionShowcase/README.md",
        "docs/profile-routing.md",
    )
    for relative in r3_required:
        if not (ROOT / relative).is_file():
            failures.append("missing R3 required file: " + relative)
    companion_tests = [
        p for p in repository_files()
        if p.suffix == ".swift" and "DuplexVoiceKitCompanionTests" in p.parts
    ]
    ui_tests = [
        p for p in repository_files()
        if p.suffix == ".swift" and "DuplexVoiceKitUITests" in p.parts
    ]
    companion_test_methods = sum(
        len(re.findall(r"\bfunc\s+test[A-Za-z0-9_]+\s*\(", p.read_text(encoding="utf-8")))
        for p in companion_tests
    )
    ui_test_methods = sum(
        len(re.findall(r"\bfunc\s+test[A-Za-z0-9_]+\s*\(", p.read_text(encoding="utf-8")))
        for p in ui_tests
    )
    if companion_test_methods < 60:
        failures.append(f"expected at least 60 Companion tests, found {companion_test_methods}")
    if ui_test_methods < 14:
        failures.append(f"expected at least 14 UI tests, found {ui_test_methods}")
    all_r3_tests = "\n".join(
        p.read_text(encoding="utf-8") for p in companion_tests + ui_tests
    )
    if "XCTAssertTrue(true)" in all_r3_tests:
        failures.append("恒真测试 is forbidden")
    public_text = "\n".join(
        p.read_text(encoding="utf-8")
        for p in repository_files()
        if p.suffix in {".swift", ".md", ".py", ".yml", ".yaml"}
        and p.name != "static_check.py"
    )
    for forbidden in ("persona_id", "system prompt", ".moc3", ".model3.json"):
        if forbidden in public_text:
            failures.append("R3 forbidden public/private boundary term: " + forbidden)
    review_text = (companion_root / "DVKCompanionModels.swift").read_text(encoding="utf-8")
    review_start = review_text.find("public struct DVKCompanionReview")
    if review_start >= 0 and "routeToken" in review_text[review_start:]:
        failures.append("route token must not be stored in review model")
    if "DVKCompanionProfileCatalog" not in companion_text:
        failures.append("public profile catalog is missing")
    if "DVKCompanionSessionContext" not in companion_text:
        failures.append("shared session context is missing")
    if "DVKCompanionView" not in ui_text:
        failures.append("R2 public DVKCompanionView API is missing")
    if "makeView(" in r2_test_text:
        failures.append("UI tests call removed makeView API")
    if "warmRose" in ui_text:
        failures.append("UI pages must not hardcode warmRose")
    theme_text = (ui_root / "DVKCompanionTheme.swift").read_text(encoding="utf-8")
    for expected in ("pageBackground", "backgroundGradient", "navigationSurface", "tabSurface", "followProfile", "warmCreamRose", "coralGold", "mistBlue", "lavenderNight"):
        if expected not in theme_text:
            failures.append("theme contract missing: " + expected)
    if ".scrollPosition(id:" not in ui_text:
        failures.append("carousel must bind scroll position")
    store_text = (companion_root / "DVKCompanionStore.swift").read_text(encoding="utf-8")
    voice_start = store_text.find("public func beginVoiceDemo")
    voice_block = store_text[voice_start:] if voice_start >= 0 else ""
    if "routeResolver.resolve" not in voice_block:
        failures.append("voice must use injected routeResolver")
    if 'opaqueValue:"mock-route-' in voice_block or 'opaqueValue: "mock-route-' in voice_block:
        failures.append("voice must not construct mock route tokens directly")
    if "public struct DVKEasterEggCard" not in ui_text:
        failures.append("public easter egg card compatibility must remain")
    if "DVKCompanionEasterEgg.allCases" not in all_r3_tests:
        failures.append("all five public easter eggs must remain covered")
    for expected in ("presentEasterEgg", "dismissEasterEgg"):
        if expected not in store_text:
            failures.append("easter egg store capability missing: " + expected)
    for expected in ("setMockCharacterState", "setMockPlaybackAmplitude", "presentationMode", "reduceMotionPreview"):
        if expected not in ui_text:
            failures.append("Mock Lab control missing: " + expected)
    if "public let routeToken" not in review_text and "public let routeToken" not in companion_text:
        failures.append("SessionContext route token must be publicly readable")
    for expected in ("preferredColorScheme", "toolbarBackground", "navigationBar", "tabBar", "foregroundStyle(theme.textPrimary)", "scrollContentBackground(.hidden)"):
        if expected not in ui_text:
            failures.append("global theme application missing: " + expected)
    if "listRowBackground(theme.surface)" not in ui_text:
        failures.append("Settings/Reviews must use themed row surfaces")
    carousel_start = ui_text.find("public struct DVKProfileCarousel")
    carousel_block = ui_text[carousel_start:] if carousel_start >= 0 else ""
    change_start = carousel_block.find(".onChange(of: scrollPosition)")
    change_block = carousel_block[change_start:change_start + 500] if change_start >= 0 else ""
    if "onPreview?()" in change_block:
        failures.append("Home compact carousel must not navigate from scroll position changes")
    character_text = (ui_root / "DVKCharacterViews.swift").read_text(encoding="utf-8")
    for expected in ("staticMode", "if !staticMode", "reduceMotion || staticMode", "if !reduceMotion"):
        if expected not in character_text:
            failures.append("static presentation contract missing: " + expected)
    failure_test_start = all_r3_tests.find("testNextTextFailureWorksWithoutManualPlan")
    failure_test_block = all_r3_tests[failure_test_start:failure_test_start + 900] if failure_test_start >= 0 else ""
    if "setScenario(.normalText)" in failure_test_block:
        failures.append("nextTextFailure test must verify automatic one-shot consumption")
    if "XCTAssertNotEqual(light.primaryAction" in all_r3_tests:
        failures.append("light/dark must preserve the profile accent color")
    if "activeScenario = .normalText" not in store_text:
        failures.append("nextTextFailure must be consumed automatically")
    package_text = (ROOT / "Package.swift").read_text(encoding="utf-8")
    showcase_project = (ROOT / "Examples" / "DVKCompanionShowcase" / "project.yml").read_text(encoding="utf-8")
    glass_path = ui_root / "DVKIOS26Glass.swift"
    glass_text = glass_path.read_text(encoding="utf-8") if glass_path.is_file() else ""
    if "platforms: [.iOS(.v17)]" not in package_text:
        failures.append("public Package minimum iOS deployment must remain 17")
    if 'deploymentTarget: "26.0"' not in showcase_project:
        failures.append("Showcase deployment target must be iOS 26")
    for expected in ("#if compiler(>=6.2)", "#available(iOS 26.0", "tabBarMinimizeBehavior", "glass", "glassProminent", "glassEffect", "GlassEffectContainer", "accessibilityReduceTransparency", "accessibilityReduceMotion"):
        if expected not in glass_text:
            failures.append("iOS 26 glass boundary missing: " + expected)
    if "toolbarBackground(.hidden, for: .tabBar)" in glass_text:
        failures.append("iOS 26 Tab Bar path must not force hidden toolbar background")
    if "tabBarMinimizeBehavior(.onScrollDown)" not in glass_text:
        failures.append("iOS 26 Tab Bar path must minimize on scroll down")
    if "DVKIOS26GlassEffectContainer" not in ui_text:
        failures.append("Home/Cats glass controls must use the shared GlassEffectContainer boundary")
    views_text = (ui_root / "DVKCompanionViews.swift").read_text(encoding="utf-8")
    if "INFOPLIST_KEY_UILaunchScreen_Generation: YES" not in showcase_project:
        failures.append("Showcase must use generated system Launch Screen metadata")
    if "private let dvkTabBarBottomContentPadding" not in views_text:
        failures.append("bottom Tab Bar content spacing must use a named private constant")
    if views_text.count("safeAreaPadding(.bottom, dvkTabBarBottomContentPadding)") != 4:
        failures.append("all four Tab roots must use the named bottom content spacing constant")
    if ".scrollClipDisabled()" not in views_text:
        failures.append("Cats Carousel must not clip scaled cards or shadows")
    if "ViewThatFits(in: .horizontal)" not in views_text or 'Button("Use this cat")' not in views_text:
        failures.append("Cats Preview Bar must provide a responsive confirmation layout")
    accessory_path = ui_root / "DVKActiveVoiceAccessory.swift"
    accessory_text = accessory_path.read_text(encoding="utf-8") if accessory_path.is_file() else ""
    if "tabViewBottomAccessory" not in accessory_text:
        failures.append("iOS 26 active voice accessory path is missing")
    if "tabViewBottomAccessory(isEnabled: presentation.isVisible)" not in accessory_text:
        failures.append("iOS 26 active voice accessory must bind isEnabled to presentation.isVisible")
    if "isEnabled" not in accessory_text or "presentation.isVisible" not in accessory_text:
        failures.append("active voice accessory visibility binding is incomplete")
    if "#if compiler(>=6.2)" not in accessory_text or "#available(iOS 26.0" not in accessory_text:
        failures.append("active voice accessory availability boundary is missing")
    if "hasActiveSession" not in accessory_text or "safeAreaInset" not in accessory_text:
        failures.append("active voice accessory must have session visibility and fallback")
    for expected in ("theme.elevatedSurface", "RoundedRectangle", "theme.textPrimary", "frame(minHeight: 44)", "theme.border"):
        if expected not in accessory_text:
            failures.append("legacy active voice accessory fallback missing: " + expected)
    if "glassEffect" in accessory_text:
        failures.append("active voice accessory must not add custom glass over iOS 26 Bottom Accessory")
    if "routeToken" in accessory_text or "sessionKey" in accessory_text:
        failures.append("active voice accessory must not expose internal session values")
    if "End" in accessory_text or "Mute" in accessory_text or "Advance" in accessory_text:
        failures.append("active voice accessory must expose only return-to-conversation behavior")
    if "setMode(.voice)" not in views_text or "conversation = true" not in views_text:
        failures.append("active voice accessory must reuse the existing Conversation Sheet")
    if "chevron.down" not in views_text or "收起语音会话" not in views_text:
        failures.append("active voice sheet collapse affordance is missing")
    if "phone.down.fill" not in views_text or "结束通话" not in views_text:
        failures.append("voice end control must remain a distinct destructive action")
    if "onEnded" not in views_text or "await store.endVoiceDemo()" not in views_text:
        failures.append("voice end control must close after existing end logic")
    views_text = (ui_root / "DVKCompanionViews.swift").read_text(encoding="utf-8")
    if ".toolbarBackground(theme.navigationSurface, for: .navigationBar)" in views_text:
        failures.append("Views must use the centralized Navigation Chrome helper")
    if views_text.count("NavigationStack") < 4:
        failures.append("each public Tab must have its own NavigationStack")
    if views_text.count("dvkIOS26NavigationChrome(theme: activeTheme)") < 4:
        failures.append("each Tab NavigationStack must use activeTheme Navigation Chrome")
    if "dvkIOS26TabBar(theme: activeTheme)" not in views_text:
        failures.append("TabView must delegate Tab Bar chrome to the shared helper")
    glass_test_methods = len(re.findall(r"\bfunc\s+test[^\(]*(?:Glass|glass|Transparency|Motion|TabBar)[^\(]*\(", all_r3_tests))
    if glass_test_methods < 8:
        failures.append(f"expected at least 8 iOS 26 glass UI tests, found {glass_test_methods}")
    if "DVKIOS26GlassConfiguration" in glass_text or "DVKIOS26GlassConfiguration" in all_r3_tests:
        failures.append("glass accessibility tests must use the runtime policy, not fixed booleans")
    if ui_text.count("NavigationStack") < 4:
        failures.append("each public Tab must have its own NavigationStack")
    voice_start = views_text.find("public struct DVKVoiceConversation")
    voice_block = views_text[voice_start:] if voice_start >= 0 else ""
    ripple_path = ui_root / "DVKCharacterVoiceRipple.swift"
    ripple_text = ripple_path.read_text(encoding="utf-8") if ripple_path.is_file() else ""
    if not ripple_path.is_file():
        failures.append("character voice ripple component is missing")
    if "DVKCharacterVoiceRipplePresentation" not in voice_block or "DVKCharacterVoiceRipple(" not in voice_block:
        failures.append("Voice Conversation must compose the character voice ripple")
    if "store.playbackAmplitude" not in voice_block:
        failures.append("character voice ripple must consume Store playbackAmplitude")
    if "DVKPlaybackAmplitudeView" in voice_block:
        failures.append("Voice Conversation must not construct the horizontal playback amplitude view")
    for forbidden in ("Timer", "random", "arc4random"):
        if forbidden.lower() in ripple_text.lower():
            failures.append("character voice ripple must not use " + forbidden)
    if ".glassEffect" in ripple_text or ".buttonStyle(.glass" in ripple_text:
        failures.append("character voice ripple must not be a glass control")
    for forbidden in ("Halo", "Spectrum", "Equalizer", "CircularWaveform", "rotationEffect", "Waveform"):
        if forbidden in ripple_text:
            failures.append("character voice ripple contains forbidden player-style token: " + forbidden)
    if "Circle()" in ripple_text:
        failures.append("character voice ripple must use soft Ellipse ripples, not a full Circle")
    if "ForEach" in ripple_text:
        failures.append("character voice ripple must not contain bar-style spectrum iteration")
    if "rippleOpacity" not in ripple_text or "rippleStrokeWidth" not in ripple_text or "rippleScale" not in ripple_text:
        failures.append("character voice ripple must expose bounded ripple parameters")
    if "outwardRipple" not in ripple_text:
        failures.append("character voice ripple must expose outwardRipple animation mode")
    if "case .listening, .speaking:" not in ripple_text or "animationMode = canAnimate && showsPrimaryRipple ? .outwardRipple" not in ripple_text:
        failures.append("listening and speaking must map to outwardRipple")
    if ".easeOut(duration: 2.8).repeatForever(autoreverses: false)" not in ripple_text:
        failures.append("outwardRipple must use a non-reversing repeat animation")
    if "frame(width: 268, height: 238)" not in ripple_text or "frame(width: 272, height: 248)" not in ripple_text:
        failures.append("primary and secondary ripples must use bounded non-square frames")
    if ".task(id: presentation.animationMode)" not in ripple_text:
        failures.append("ripple animation must restart from animationMode task identity")
    if "transaction.disablesAnimations = true" not in ripple_text or "phase = false" not in ripple_text:
        failures.append("ripple animation task must reset phase without animation")
    if "await Task.yield()" not in ripple_text:
        failures.append("ripple animation task must yield before restarting")
    if "Task.isCancelled" not in ripple_text:
        failures.append("ripple animation task must guard cancellation before restarting")
    if ".onChange(of: presentation.animationMode)" in ripple_text:
        failures.append("ripple animation must not use the old direct onChange lifecycle")
    if "1.06" in ripple_text or "1.06" in all_r3_tests:
        failures.append("ripple scale bound must not use the old 1.06 limit")
    if ".accessibilityHidden(true)" not in ripple_text:
        failures.append("character voice ripple must be accessibility hidden as decoration")
    if "repeatForever" in ripple_text and not all(token in ripple_text for token in ("case .none:", ".task(id: presentation.animationMode)", "phase = false", "canAnimate")):
        failures.append("ripple repeatForever must be gated by Reduce Motion and static mode policy")
    if voice_block.count(".dvkGlassControl") < 3:
        failures.append("Voice Start/Advance/End must each use an independent glass control")
    if "HStack(spacing: 10) {" in voice_block and "}.dvkGlassControl" in voice_block:
        failures.append("Voice HStack must not receive the glass control modifier directly")
    if "content.buttonStyle(.glassProminent)" not in glass_text or "content.glassEffect(.regular.interactive()" not in glass_text:
        failures.append("glass control helper must expose separate buttonStyle and glassEffect branches")
    if "if #available(iOS 26.0, *)" not in glass_text or "content\n        } else" not in glass_text:
        failures.append("iOS 26 navigation chrome must return automatic system content")

    # ------------------------------------------------------------------
    # V7.0 one-shot sanitized migration gates (lightweight, no DLP engine)
    # ------------------------------------------------------------------
    v70_required = (
        "Sources/DuplexVoiceKitCompanion/DVKRuntimeConfiguration.swift",
        "Sources/DuplexVoiceKitCompanion/DVKTokenStoring.swift",
        "Sources/DuplexVoiceKitCompanion/DVKBackendClient.swift",
        "Sources/DuplexVoiceKitCompanion/DVKChatService.swift",
        "Sources/DuplexVoiceKitUI/DVKVoiceTransport.swift",
        "Sources/DuplexVoiceKitUI/DVKCompanionVoiceSessionController.swift",
        "Sources/DuplexVoiceKitUI/DVKDeviceBindingView.swift",
        "Tests/DuplexVoiceKitCompanionTests/DVKRuntimeConfigurationTests.swift",
        "Tests/DuplexVoiceKitCompanionTests/DVKTokenStoreTests.swift",
        "Tests/DuplexVoiceKitCompanionTests/DVKChatServiceTests.swift",
        "Tests/DuplexVoiceKitUITests/DVKVoiceTransportTests.swift",
        "Tests/DuplexVoiceKitUITests/DVKCompanionVoiceSessionControllerTests.swift",
    )
    for relative in v70_required:
        if not (ROOT / relative).is_file():
            failures.append("missing V7.0 required file: " + relative)

    v70_private_terms = (
        "xiaomao-api.xiangpt.ltd",
        "xiaomao-voice.xiangpt.ltd",
        "xiang4185@gmail.com",
        "com.xiang4185",
        "ios-owner-01",
        "ios-owner-dev",
        "/srv/yusuan/",
        "owner-token.txt",
        "xiaomao-app-backend.service",
        "xiaomao-app-voice.service",
        "xiaomao-app-test-tunnel",
        "SC2.0",
        "路线 B",
        "sc2.0",
    )
    v70_text_extensions = {".md", ".py", ".swift", ".yml", ".yaml"}
    for path in files:
        relative = path.relative_to(ROOT)
        if path.suffix.lower() not in v70_text_extensions:
            continue
        if relative.as_posix() == "Scripts/static_check.py":
            continue
        text = path.read_text(encoding="utf-8")
        for term in v70_private_terms:
            if term in text:
                failures.append(f"V7.0 forbidden private term {term!r}: {relative}")

    v70_bearer_pattern = re.compile(
        r"Authorization:\s*Bearer\s+[A-Za-z0-9._\-]{12,}"
    )
    v70_token_assignment_pattern = re.compile(
        r"DEVELOPMENT_TOKEN\s*=\s*[\"'][^\"']+[\"']"
    )
    for path in files:
        relative = path.relative_to(ROOT)
        if path.suffix.lower() not in v70_text_extensions:
            continue
        if relative.as_posix() == "Scripts/static_check.py":
            continue
        text = path.read_text(encoding="utf-8")
        if v70_bearer_pattern.search(text):
            failures.append("V7.0 possible embedded live bearer credential: " + str(relative))
        if v70_token_assignment_pattern.search(text):
            failures.append("V7.0 possible embedded development token: " + str(relative))


    result = {
        "status": "failed" if failures else "ok",
        "swift_files": len(swift_files),
        "test_files": len(test_files),
        "test_methods": test_method_count,
        "companion_test_methods": companion_test_methods,
        "ui_test_methods": ui_test_methods,
        "check_type": "static",
        "failures": sorted(set(failures)),
    }
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
