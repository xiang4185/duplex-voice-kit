#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DVK_PATH = "../.."

REQUIRED = [
    "project.yml",
    "Config/Debug.xcconfig",
    "Config/Release.xcconfig",
    "Config/Secrets.example.xcconfig",
    "XiaomaoApp/App/XiaomaoApp.swift",
    "XiaomaoApp/Integration/HostAdapters.swift",
    "XiaomaoApp/Models/VoiceEvent.swift",
    "XiaomaoApp/Models/VoiceSessionState.swift",
    "XiaomaoApp/Networking/WebSocketClient.swift",
    "XiaomaoApp/Networking/VoiceWebSocketLifecycle.swift",
    "XiaomaoApp/Voice/VoiceSessionController.swift",
    "XiaomaoApp/Voice/AudioUploadActor.swift",
    "XiaomaoApp/Voice/XiaomaoDVKOutboundTransport.swift",
    "XiaomaoApp/Voice/VoiceDiagnostics.swift",
    "XiaomaoApp/Voice/VoiceLog.swift",
    "XiaomaoApp/Voice/VoiceReconnectController.swift",
    "XiaomaoApp/Audio/AudioCaptureEngine.swift",
    "XiaomaoApp/Audio/AudioPlaybackEngine.swift",
    "XiaomaoApp/Audio/AudioSessionController.swift",
    "XiaomaoApp/Audio/RealtimeAudioIOEngine.swift",
    "XiaomaoApp/Audio/VoiceActivityDetector.swift",
    "XiaomaoApp/Resources/Info.plist",
    "XiaomaoApp/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json",
    "XiaomaoApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon1024.png",
    "XiaomaoAppTests/VoiceSessionControllerTests.swift",
    "XiaomaoAppTests/AudioUploadActorTests.swift",
    "XiaomaoAppTests/VoiceActivityDetectorTests.swift",
    "XiaomaoAppTests/DuplexVoiceKitAdapterTests.swift",
    "XiaomaoAppTests/HandsFreeInteractionContractTests.swift",
    "XiaomaoAppTests/ChatViewModelTests.swift",
    "XiaomaoAppTests/HostAdapterTests.swift",
]

SENSITIVE_NAMES = {".env", "Secrets.xcconfig"}
SENSITIVE_SUFFIXES = {
    ".p12", ".pfx", ".pem", ".key", ".cer", ".crt", ".mobileprovision",
    ".db", ".sqlite", ".sqlite3", ".db-wal", ".db-shm",
    ".wav", ".mp3", ".m4a", ".pcm",
}


def repository_files() -> list[Path]:
    ignored = {".git", ".build", ".swiftpm", "DerivedData", "__pycache__"}
    return [
        path for path in ROOT.rglob("*")
        if path.is_file() and not ignored.intersection(path.relative_to(ROOT).parts)
    ]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def main() -> None:
    failures: list[str] = [
        "missing required file: " + path
        for path in REQUIRED
        if not (ROOT / path).is_file()
    ]
    files = repository_files()
    swift_files = [path for path in files if path.suffix == ".swift"]

    for path in files:
        relative = path.relative_to(ROOT)
        if path.name in SENSITIVE_NAMES or path.suffix.lower() in SENSITIVE_SUFFIXES:
            failures.append("sensitive file path: " + str(relative))
        if path.is_symlink():
            failures.append("symlink is not allowed: " + str(relative))

    for path in swift_files:
        text = path.read_text(encoding="utf-8")
        if "VOLC_" in text or "SpeakerID=" in text or "API_KEY=" in text:
            failures.append("supplier credential reference in " + str(path.relative_to(ROOT)))
        if text.count("{") != text.count("}"):
            failures.append("brace mismatch in " + str(path.relative_to(ROOT)))

    project = read("project.yml")
    for expected in (
        "DuplexVoiceKit:",
        "path: " + DVK_PATH,
        "- package: DuplexVoiceKit",
    ):
        if expected not in project:
            failures.append("project.yml missing local DVK dependency: " + expected)
    for forbidden in (
        "branch: main",
        "url: https://github.com/xiang4185/duplex-voice-kit.git",
        "revision:",
        "git@github.com:xiang4185/duplex-voice-kit",
        "ssh://git@github.com/xiang4185/duplex-voice-kit",
    ):
        if forbidden in project:
            failures.append("forbidden DVK dependency form: " + forbidden)
    if re.search(r"(?m)^\s*path:\s*/", project):
        failures.append("forbidden absolute local DVK dependency path")
    if project.count("- package: DuplexVoiceKit") < 2:
        failures.append("App and Test targets must both link DuplexVoiceKit")
    if "ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon" not in project:
        failures.append("XiaomaoApp target must bind the AppIcon asset catalog")

    debug_config = read("Config/Debug.xcconfig")
    release_config = read("Config/Release.xcconfig")
    example_config = read("Config/Secrets.example.xcconfig")
    for expected in (
        "API_BASE_URL = http://127.0.0.1:18080",
        "VOICE_WS_URL = ws://127.0.0.1:18881/v1/voice/ws",
        "DEVICE_ID =\n",
        "ENABLE_MOCK_VOICE = YES",
    ):
        if expected not in debug_config:
            failures.append("Debug configuration boundary missing: " + expected.strip())
    for expected in (
        "API_BASE_URL =\n",
        "VOICE_WS_URL =\n",
        "DEVICE_ID =\n",
        "ENABLE_MOCK_VOICE = NO",
    ):
        if expected not in release_config:
            failures.append("Release fail-closed boundary missing: " + expected.strip())
    for expected in ("API_BASE_URL =\n", "VOICE_WS_URL =\n", "DEVICE_ID =\n"):
        if expected not in example_config:
            failures.append("Secrets example must keep empty key: " + expected.strip())

    scanned_text = "\n".join(
        path.read_text(encoding="utf-8", errors="ignore")
        for path in files
        if path.suffix.lower() in {".swift", ".md", ".yml", ".yaml", ".xcconfig", ".py"}
        and path.name != Path(__file__).name
    )
    for forbidden in ("xiaomao-api.xiangpt.ltd", "xiaomao-voice.xiangpt.ltd", "dvk-local-device"):
        if forbidden in scanned_text:
            failures.append("forbidden production-like literal: " + forbidden)

    app_icon_contents = read(
        "XiaomaoApp/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json"
    )
    if '"filename": "AppIcon1024.png"' not in app_icon_contents:
        failures.append("AppIcon asset must reference AppIcon1024.png")
    icon_path = ROOT / "XiaomaoApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon1024.png"
    if icon_path.is_file():
        icon_header = icon_path.read_bytes()[:24]
        if len(icon_header) != 24 or icon_header[:8] != b"\x89PNG\r\n\x1a\n":
            failures.append("AppIcon1024.png must be a PNG file")
        else:
            width, height = struct.unpack(">II", icon_header[16:24])
            if (width, height) != (1024, 1024):
                failures.append(
                    f"AppIcon1024.png must be 1024x1024, found {width}x{height}"
                )

    websocket = read("XiaomaoApp/Networking/WebSocketClient.swift")
    if "task.send(.data" in websocket:
        failures.append("voice JSON envelope must use a WebSocket text frame")
    timeout_match = re.search(
        r"resourceTimeoutSeconds:\s*TimeInterval\s*=\s*([0-9_]+)", websocket
    )
    if not timeout_match or int(timeout_match.group(1).replace("_", "")) < 3_600:
        failures.append("WebSocket resource timeout must be at least 3600 seconds")

    controller = read("XiaomaoApp/Voice/VoiceSessionController.swift")
    uploader = read("XiaomaoApp/Voice/AudioUploadActor.swift")
    adapter = read("XiaomaoApp/Voice/XiaomaoDVKOutboundTransport.swift")
    realtime = read("XiaomaoApp/Audio/RealtimeAudioIOEngine.swift")
    audio_session = read("XiaomaoApp/Audio/AudioSessionController.swift")
    vad = read("XiaomaoApp/Audio/VoiceActivityDetector.swift")
    reconnect = read("XiaomaoApp/Voice/VoiceReconnectController.swift")

    if "socket.send" in controller:
        failures.append("VoiceSessionController must not call socket.send directly")
    if "VoiceProtocolCodec" in controller or re.search(r"private\s+var\s+chunkIndex\b", controller):
        failures.append("VoiceSessionController must not own outbound sequence or chunk index")
    callback_match = re.search(r"capture\.onPacket\s*=\s*\{(.{0,240})\}", controller, re.S)
    if callback_match and "Task" in callback_match.group(1):
        failures.append("capture callback must not create per-frame Task")

    if "DVKAudioUploadPipeline" not in uploader:
        failures.append("AudioUploadActor must delegate to DVKAudioUploadPipeline")
    for forbidden in (
        "AudioUploadIngress",
        "DispatchSemaphore",
        "drainTask",
        "pendingPCM16",
        "nextChunkIndex",
        "activeConnectionGeneration",
        '"chunk_index": .int',
    ):
        if forbidden in uploader:
            failures.append("duplicate private upload core remains: " + forbidden)
    if uploader.count("XiaomaoDVKOutboundTransport") != 1:
        failures.append("AudioUploadActor must create exactly one DVK outbound adapter")

    production_root = ROOT / "XiaomaoApp"
    socket_send_files: list[str] = []
    for path in production_root.rglob("*.swift"):
        relative = path.relative_to(ROOT).as_posix()
        text = path.read_text(encoding="utf-8")
        if "socket.send" in text:
            socket_send_files.append(relative)
        if '"chunk_index": .int' in text:
            failures.append("App must not allocate upload chunk_index: " + relative)
    if socket_send_files != ["XiaomaoApp/Voice/XiaomaoDVKOutboundTransport.swift"]:
        failures.append("expected one socket.send outlet in DVK adapter, found: " + ",".join(socket_send_files))
    if adapter.count("socket.send") != 1:
        failures.append("DVK outbound adapter must contain exactly one socket.send")
    for forbidden in ("connect(", "disconnect(", "makeEventStream", "Authorization", "token"):
        if forbidden in adapter:
            failures.append("send-only adapter contains lifecycle or credential behavior: " + forbidden)

    if "DVKRealtimeAudioIO" not in realtime:
        failures.append("Route B realtime adapter must delegate to DVKRealtimeAudioIO")
    for forbidden in (
        "AVAudioEngine",
        "AVAudioPlayerNode",
        "installTap",
        "mediaServicesWereResetNotification",
        "AVAudioEngineConfigurationChange",
    ):
        if forbidden in realtime:
            failures.append("duplicate Route B realtime audio core remains: " + forbidden)

    if "DVKAudioSessionController" not in audio_session:
        failures.append("AudioSessionController must delegate to DVKAudioSessionController")
    for forbidden in ("setCategory(", "setPreferredSampleRate(", "setActive("):
        if forbidden in audio_session:
            failures.append("duplicate audio session configuration remains: " + forbidden)

    for expected in (
        "typealias VoiceActivityConfiguration = DVKVoiceActivityConfiguration",
        "typealias VoiceActivityDetector = DVKVoiceActivityDetector",
    ):
        if expected not in vad:
            failures.append("VAD must delegate to DVK: " + expected)
    for forbidden in ("speechRMSThreshold", "bargeInRMSThreshold", "normalizedRMS("):
        if forbidden in vad:
            failures.append("duplicate VAD algorithm remains: " + forbidden)

    if "typealias VoiceReconnectPolicy = DVKReconnectPolicy" not in reconnect:
        failures.append("reconnect policy must use DVKReconnectPolicy")
    if "1 <<" in reconnect or "400 *" in reconnect:
        failures.append("duplicate reconnect delay calculation remains")

    coordinator = read("XiaomaoApp/App/AppCoordinator.swift")
    if "AudioCaptureEngine()" in coordinator or "AudioPlaybackEngine()" in coordinator:
        failures.append("production coordinator must not create separate Route B capture/playback engines")
    if coordinator.count("RealtimeAudioIOEngine()") != 1:
        failures.append("production coordinator must create exactly one Route B realtime adapter")

    host_adapters = read("XiaomaoApp/Integration/HostAdapters.swift")
    for expected in (
        "protocol BackendAdapter",
        "protocol VoiceAdapter",
        "protocol CredentialProviderAdapter",
        "protocol DeviceBindingProviderAdapter",
        "struct EmptyBackendAdapter",
        "struct EmptyVoiceAdapter",
        "actor MockBackendAdapter",
        "actor MockVoiceAdapter",
        "struct HostAdapterDependencies",
    ):
        if expected not in host_adapters:
            failures.append("host adapter boundary missing: " + expected)
    for forbidden in (
        "URLSession",
        "NWConnection",
        "Network.framework",
        "http://",
        "https://",
        "ws://",
        "wss://",
        "Authorization",
        "Bearer ",
    ):
        if forbidden in host_adapters:
            failures.append("host adapter shell contains network or credential implementation: " + forbidden)
    if host_adapters.count("networkRequestCount: 0") < 2:
        failures.append("backend Empty and Mock adapters must report zero network requests")
    if host_adapters.count("networkConnectionCount: 0") < 2:
        failures.append("voice Empty and Mock adapters must report zero network connections")

    environment = read("XiaomaoApp/App/AppEnvironment.swift")
    if "hostAdapters: HostAdapterDependencies = .empty" not in environment:
        failures.append("AppEnvironment must default host adapters to Empty implementations")
    if "self.hostAdapters = environment.hostAdapters" not in coordinator:
        failures.append("AppCoordinator must receive host adapters through AppEnvironment")

    call_view = read("XiaomaoApp/Call/VoiceCallView.swift")
    for forbidden_control in ("按住说话", "结束本轮", "Picker(\"路线"):
        if forbidden_control in call_view:
            failures.append("hands-free voice UI contains prohibited control: " + forbidden_control)
    if "SC2.0 · 路线 B" not in call_view:
        failures.append("foreground voice route must remain fixed to Route B")

    diagnostics = read("XiaomaoApp/Voice/VoiceDiagnostics.swift").lower()
    for forbidden in ("token=", "authorization=", "speaker_id=", "transcript=", "audio_base64="):
        if forbidden in diagnostics:
            failures.append("diagnostics contains prohibited field: " + forbidden)

    test_method_count = sum(
        len(re.findall(r"\bfunc\s+test[A-Za-z0-9_]+\s*\(", path.read_text(encoding="utf-8")))
        for path in (ROOT / "XiaomaoAppTests").glob("*.swift")
    )
    if test_method_count < 117:
        failures.append(f"private test count dropped below integration baseline: {test_method_count}")

    result = {
        "status": "failed" if failures else "ok",
        "swift_files": len(swift_files),
        "test_methods": test_method_count,
        "dvk_dependency": "local",
        "compiled_on_linux": False,
        "failures": sorted(set(failures)),
    }
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
