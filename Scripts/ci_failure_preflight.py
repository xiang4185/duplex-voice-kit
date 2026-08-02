#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import TextIO

ROOT = Path(__file__).resolve().parents[1]
RULE_PREFIX = "ci-preflight"

_TAB_ACCESSORY_CALL = "tabViewBottomAccessory(isEnabled:"
_AVAILABLE_HEADER = re.compile(
    r"if\s+#available\s*\(\s*iOS\s+(\d+)(?:\.(\d+))?[^)]*\)\s*$",
    re.DOTALL,
)
_GENERATED_INFOPLIST = re.compile(
    r"^\s*GENERATE_INFOPLIST_FILE\s*:\s*['\"]?YES['\"]?\s*(?:#.*)?$",
    re.MULTILINE,
)
_EXPLICIT_INFOPLIST = re.compile(
    r"^\s*INFOPLIST_FILE\s*:\s*(?P<value>[^#\n]+?)\s*(?:#.*)?$",
    re.MULTILINE,
)
_MAIN_ACTOR_STORE_DEFAULT = re.compile(
    r"\bstore\s*:\s*DVKCompanionStore\s*=\s*DVKCompanionStore\s*\(\s*\)"
)
_HIERARCHICAL_STYLES = {"primary", "secondary", "tertiary", "quaternary"}
_CONCRETE_COLORS = {
    "accentColor",
    "black",
    "blue",
    "brown",
    "clear",
    "cyan",
    "gray",
    "green",
    "indigo",
    "mint",
    "orange",
    "pink",
    "purple",
    "red",
    "teal",
    "white",
    "yellow",
}
_FOREGROUND_STYLE_TERNARY = re.compile(
    r"\.foregroundStyle\s*\(\s*"
    r"(?P<condition>[^?()]{1,240}?)\?\s*"
    r"\.(?P<left>[A-Za-z_][A-Za-z0-9_]*)\s*:\s*"
    r"\.(?P<right>[A-Za-z_][A-Za-z0-9_]*)\s*\)",
    re.DOTALL,
)


def _relative(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def _line_number(text: str, position: int) -> int:
    return text.count("\n", 0, position) + 1


def _mask_comments_and_strings(text: str) -> str:
    """Mask Swift comments and string contents while preserving offsets and newlines."""
    chars = list(text)
    index = 0
    block_depth = 0
    state = "code"

    def mask(position: int) -> None:
        if chars[position] != "\n":
            chars[position] = " "

    while index < len(chars):
        if state == "line_comment":
            if chars[index] == "\n":
                state = "code"
            else:
                mask(index)
            index += 1
            continue

        if state == "block_comment":
            if index + 1 < len(chars) and chars[index] == "/" and chars[index + 1] == "*":
                mask(index)
                mask(index + 1)
                block_depth += 1
                index += 2
                continue
            if index + 1 < len(chars) and chars[index] == "*" and chars[index + 1] == "/":
                mask(index)
                mask(index + 1)
                block_depth -= 1
                index += 2
                if block_depth == 0:
                    state = "code"
                continue
            mask(index)
            index += 1
            continue

        if state == "string":
            if chars[index] == "\\" and index + 1 < len(chars):
                mask(index)
                mask(index + 1)
                index += 2
                continue
            if chars[index] == '"':
                mask(index)
                state = "code"
                index += 1
                continue
            mask(index)
            index += 1
            continue

        if state == "multiline_string":
            if text.startswith('"""', index):
                for offset in range(3):
                    mask(index + offset)
                state = "code"
                index += 3
                continue
            mask(index)
            index += 1
            continue

        if index + 1 < len(chars) and chars[index] == "/" and chars[index + 1] == "/":
            mask(index)
            mask(index + 1)
            state = "line_comment"
            index += 2
            continue
        if index + 1 < len(chars) and chars[index] == "/" and chars[index + 1] == "*":
            mask(index)
            mask(index + 1)
            block_depth = 1
            state = "block_comment"
            index += 2
            continue
        if text.startswith('"""', index):
            for offset in range(3):
                mask(index + offset)
            state = "multiline_string"
            index += 3
            continue
        if chars[index] == '"':
            mask(index)
            state = "string"
            index += 1
            continue
        index += 1

    return "".join(chars)


def _enclosing_braces_for_positions(
    text: str,
    target_positions: set[int],
) -> dict[int, tuple[int, ...]]:
    stack: list[int] = []
    positions: dict[int, tuple[int, ...]] = {}
    for index, character in enumerate(text):
        if character == "{":
            stack.append(index)
        elif character == "}" and stack:
            stack.pop()
        if index in target_positions:
            positions[index] = tuple(stack)
    return positions


def _brace_has_ios_26_1_boundary(masked_text: str, opening_brace: int) -> bool:
    header = masked_text[max(0, opening_brace - 320):opening_brace]
    match = _AVAILABLE_HEADER.search(header)
    if not match:
        return False
    major = int(match.group(1))
    minor = int(match.group(2) or 0)
    return (major, minor) >= (26, 1)


def check_tab_view_bottom_accessory_availability(root: Path) -> list[str]:
    failures: list[str] = []
    sources = root / "Sources"
    if not sources.is_dir():
        return failures

    for path in sorted(sources.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        masked = _mask_comments_and_strings(text)
        if _TAB_ACCESSORY_CALL not in masked:
            continue
        call_positions: list[int] = []
        search_from = 0
        while True:
            call_position = masked.find(_TAB_ACCESSORY_CALL, search_from)
            if call_position < 0:
                break
            call_positions.append(call_position)
            search_from = call_position + len(_TAB_ACCESSORY_CALL)

        brace_positions = _enclosing_braces_for_positions(masked, set(call_positions))
        for call_position in call_positions:
            enclosing_braces = brace_positions.get(call_position, ())
            guarded = any(
                _brace_has_ios_26_1_boundary(masked, opening)
                for opening in reversed(enclosing_braces)
            )
            if not guarded:
                failures.append(
                    f"{_relative(path, root)}:{_line_number(text, call_position)}: "
                    f"{RULE_PREFIX}/tab-view-bottom-accessory-availability: "
                    "tabViewBottomAccessory(isEnabled:) requires an enclosing "
                    "#available(iOS 26.1, *) branch"
                )
    return failures


def _resolved_infoplist_path(root: Path, project_path: Path, raw_value: str) -> Path | None:
    value = raw_value.strip().strip('"\'')
    value = value.replace("$(SRCROOT)", str(project_path.parent))
    value = value.replace("${SRCROOT}", str(project_path.parent))
    if "$" in value:
        return None
    candidate = Path(value)
    if not candidate.is_absolute():
        candidate = project_path.parent / candidate
    resolved_root = root.resolve()
    resolved_candidate = candidate.resolve()
    try:
        resolved_candidate.relative_to(resolved_root)
    except ValueError:
        return None
    return resolved_candidate


def _yaml_mapping_block(
    text: str,
    key: str,
    *,
    start: int = 0,
    end: int | None = None,
    required_indent: int | None = None,
) -> tuple[str, int] | None:
    lines = text.splitlines(keepends=True)
    end = len(lines) if end is None else end
    key_pattern = re.compile(rf"^{re.escape(key)}\s*:\s*(?:#.*)?$")

    for index in range(start, end):
        line = lines[index]
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(line) - len(line.lstrip(" "))
        if required_indent is not None and indent != required_indent:
            continue
        if not key_pattern.match(line[indent:].rstrip("\r\n")):
            continue

        block_end = index + 1
        while block_end < end:
            candidate = lines[block_end]
            candidate_stripped = candidate.strip()
            if candidate_stripped and not candidate_stripped.startswith("#"):
                candidate_indent = len(candidate) - len(candidate.lstrip(" "))
                if candidate_indent <= indent:
                    break
            block_end += 1
        return "".join(lines[index:block_end]), index
    return None


def _showcase_target_block(text: str) -> str | None:
    lines = text.splitlines(keepends=True)
    root_indents = [
        len(line) - len(line.lstrip(" "))
        for line in lines
        if line.strip() and not line.strip().startswith("#")
    ]
    if not root_indents:
        return None
    targets = _yaml_mapping_block(
        text,
        "targets",
        required_indent=min(root_indents),
    )
    if targets is None:
        return None
    targets_text, targets_line = targets
    targets_lines = targets_text.splitlines(keepends=True)

    child_indents = []
    for line in targets_lines[1:]:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(line) - len(line.lstrip(" "))
        if re.match(r"^[^:#][^:]*:\s*(?:#.*)?$", line[indent:].rstrip("\r\n")):
            child_indents.append(indent)
    if not child_indents:
        return None

    target_indent = min(child_indents)
    target = _yaml_mapping_block(
        text,
        "DVKCompanionShowcase",
        start=targets_line + 1,
        end=targets_line + len(targets_lines),
        required_indent=target_indent,
    )
    return target[0] if target is not None else None


def check_showcase_info_plist(root: Path) -> list[str]:
    project_path = root / "Examples" / "DVKCompanionShowcase" / "project.yml"
    relative = project_path.relative_to(root).as_posix()
    if not project_path.is_file():
        return [
            f"{relative}: {RULE_PREFIX}/showcase-info-plist: project.yml is missing"
        ]

    text = project_path.read_text(encoding="utf-8")
    target_text = _showcase_target_block(text)
    if target_text is None:
        return [
            f"{relative}: {RULE_PREFIX}/showcase-info-plist: "
            "targets.DVKCompanionShowcase is missing"
        ]
    if _GENERATED_INFOPLIST.search(target_text):
        return []

    explicit_values = [
        match.group("value") for match in _EXPLICIT_INFOPLIST.finditer(target_text)
    ]
    for value in explicit_values:
        resolved = _resolved_infoplist_path(root, project_path, value)
        if resolved is not None and resolved.is_file():
            return []

    detail = "no generated or explicit Info.plist setting"
    if explicit_values:
        detail = "configured INFOPLIST_FILE does not resolve to an existing file inside the repository"
    return [
        f"{relative}: {RULE_PREFIX}/showcase-info-plist: {detail}"
    ]


def _xcodebuild_commands(workflow_text: str) -> list[str]:
    lines = workflow_text.splitlines()
    commands: list[str] = []
    index = 0
    while index < len(lines):
        stripped = lines[index].strip()
        if "xcodebuild" not in stripped:
            index += 1
            continue
        command_parts = [stripped]
        while command_parts[-1].rstrip().endswith("\\") and index + 1 < len(lines):
            index += 1
            command_parts.append(lines[index].strip())
        commands.append(" ".join(part.rstrip("\\").strip() for part in command_parts))
        index += 1
    return commands


def check_ios_package_test_scheme(root: Path) -> list[str]:
    workflow_path = root / ".github" / "workflows" / "ci.yml"
    relative = workflow_path.relative_to(root).as_posix()
    if not workflow_path.is_file():
        return [
            f"{relative}: {RULE_PREFIX}/ios-package-test-scheme: workflow is missing"
        ]

    text = workflow_path.read_text(encoding="utf-8")
    commands = _xcodebuild_commands(text)
    simulator_variable = bool(
        re.search(r"\b[A-Za-z_][A-Za-z0-9_]*\s*=\s*['\"]platform=iOS Simulator", text)
    )
    test_commands: list[str] = []
    for command in commands:
        is_test = bool(re.search(r"(?:^|\s)test(?:\s|$)", command))
        is_simulator = "platform=iOS Simulator" in command or (
            simulator_variable and re.search(r"-destination\s+['\"]?\$[A-Za-z_]", command)
        )
        if is_test and is_simulator:
            test_commands.append(command)

    schemes: list[str] = []
    for command in test_commands:
        scheme_match = re.search(r"-scheme\s+['\"]?([^\s'\"\\]+)", command)
        schemes.append(scheme_match.group(1) if scheme_match else "<missing>")

    if "DuplexVoiceKit" in schemes:
        return [
            f"{relative}: {RULE_PREFIX}/ios-package-test-scheme: "
            "DuplexVoiceKit is not a testable iOS Simulator package scheme; "
            "use DuplexVoiceKit-Package"
        ]
    if "DuplexVoiceKit-Package" not in schemes:
        return [
            f"{relative}: {RULE_PREFIX}/ios-package-test-scheme: "
            "no DuplexVoiceKit-Package iOS Simulator test command was found"
        ]
    return []


def check_main_actor_store_defaults(root: Path) -> list[str]:
    failures: list[str] = []
    ui_root = root / "Sources" / "DuplexVoiceKitUI"
    if not ui_root.is_dir():
        return failures
    for path in sorted(ui_root.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        masked = _mask_comments_and_strings(text)
        for match in _MAIN_ACTOR_STORE_DEFAULT.finditer(masked):
            failures.append(
                f"{_relative(path, root)}:{_line_number(text, match.start())}: "
                f"{RULE_PREFIX}/main-actor-store-default: "
                "do not construct DVKCompanionStore() in a default parameter; "
                "provide a separate no-argument initializer"
            )
    return failures


def check_foreground_style_ternaries(root: Path) -> list[str]:
    failures: list[str] = []
    ui_root = root / "Sources" / "DuplexVoiceKitUI"
    if not ui_root.is_dir():
        return failures
    for path in sorted(ui_root.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        masked = _mask_comments_and_strings(text)
        for match in _FOREGROUND_STYLE_TERNARY.finditer(masked):
            left = match.group("left")
            right = match.group("right")
            mixes_types = (
                left in _HIERARCHICAL_STYLES and right in _CONCRETE_COLORS
            ) or (
                right in _HIERARCHICAL_STYLES and left in _CONCRETE_COLORS
            )
            if mixes_types:
                failures.append(
                    f"{_relative(path, root)}:{_line_number(text, match.start())}: "
                    f"{RULE_PREFIX}/foreground-style-ternary: "
                    "conditional foregroundStyle mixes an implicit hierarchical style "
                    "with an implicit Color; use explicit Color values"
                )
    return failures


def run_preflight(root: Path) -> list[str]:
    checks = (
        check_tab_view_bottom_accessory_availability,
        check_showcase_info_plist,
        check_ios_package_test_scheme,
        check_main_actor_store_defaults,
        check_foreground_style_ternaries,
    )
    failures: list[str] = []
    for check in checks:
        failures.extend(check(root))
    return sorted(set(failures))


def run_command(root: Path, output: TextIO | None = None) -> int:
    failures = run_preflight(root)
    result = {
        "check_type": "ci-failure-preflight",
        "status": "failed" if failures else "ok",
        "failure_count": len(failures),
        "failures": failures,
    }
    if output is None:
        output = sys.stdout
    print(
        json.dumps(
            result,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ),
        file=output,
    )
    return 1 if failures else 0


def main() -> None:
    raise SystemExit(run_command(ROOT))


if __name__ == "__main__":
    main()
