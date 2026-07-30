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
    ".wav", ".mp3", ".m4a", ".pcm", ".ipa",
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
            for forbidden in FORBIDDEN_REPOSITORY_TERMS:
                if forbidden in text:
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

    result = {
        "status": "failed" if failures else "ok",
        "swift_files": len(swift_files),
        "test_files": len(test_files),
        "test_methods": test_method_count,
        "check_type": "static",
        "failures": sorted(set(failures)),
    }
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
