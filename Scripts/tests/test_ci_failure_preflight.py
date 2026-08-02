from __future__ import annotations

import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from ci_failure_preflight import (  # noqa: E402
    ROOT as PREFLIGHT_ROOT,
    check_foreground_style_ternaries,
    check_ios_package_test_scheme,
    check_main_actor_store_defaults,
    check_showcase_info_plist,
    check_tab_view_bottom_accessory_availability,
    run_command,
)


class TemporaryRepositoryTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self._temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self._temporary_directory.name)

    def tearDown(self) -> None:
        self._temporary_directory.cleanup()

    def write(self, relative: str, content: str) -> Path:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return path


class TabViewBottomAccessoryAvailabilityTests(TemporaryRepositoryTestCase):
    def test_ios_26_1_availability_boundary_passes(self) -> None:
        self.write(
            "Sources/DuplexVoiceKitUI/Accessory.swift",
            """
            import SwiftUI

            func body() -> some View {
                if #available(iOS 26.1, *) {
                    ContentView()
                        .tabViewBottomAccessory(isEnabled: true) { Text("Voice") }
                } else {
                    ContentView()
                }
            }
            """,
        )

        self.assertEqual(
            check_tab_view_bottom_accessory_availability(self.root),
            [],
        )

    def test_ios_26_0_boundary_fails(self) -> None:
        self.write(
            "Sources/DuplexVoiceKitUI/Accessory.swift",
            """
            import SwiftUI

            func body() -> some View {
                if #available(iOS 26.0, *) {
                    ContentView()
                        .tabViewBottomAccessory(isEnabled: true) { Text("Voice") }
                } else {
                    ContentView()
                }
            }
            """,
        )

        failures = check_tab_view_bottom_accessory_availability(self.root)

        self.assertEqual(len(failures), 1)
        self.assertIn("tab-view-bottom-accessory-availability", failures[0])
        self.assertIn("Accessory.swift", failures[0])

    def test_unrelated_ios_26_1_boundary_does_not_satisfy_call(self) -> None:
        self.write(
            "Sources/DuplexVoiceKitUI/Accessory.swift",
            """
            import SwiftUI

            func unrelated() -> some View {
                if #available(iOS 26.1, *) {
                    Text("New")
                } else {
                    Text("Old")
                }
            }

            func accessory() -> some View {
                ContentView()
                    .tabViewBottomAccessory(isEnabled: true) { Text("Voice") }
            }
            """,
        )

        failures = check_tab_view_bottom_accessory_availability(self.root)

        self.assertEqual(len(failures), 1)
        self.assertIn("tab-view-bottom-accessory-availability", failures[0])

    def test_repository_without_api_is_silent(self) -> None:
        self.write(
            "Sources/DuplexVoiceKitUI/Accessory.swift",
            "import SwiftUI\nlet content = Text(\"Voice\")\n",
        )

        self.assertEqual(
            check_tab_view_bottom_accessory_availability(self.root),
            [],
        )


class ShowcaseInfoPlistTests(TemporaryRepositoryTestCase):
    def test_showcase_target_generated_info_plist_passes(self) -> None:
        self.write(
            "Examples/DVKCompanionShowcase/project.yml",
            """
            targets:
              DVKCompanionShowcase:
                settings:
                  GENERATE_INFOPLIST_FILE: YES
            """,
        )

        self.assertEqual(check_showcase_info_plist(self.root), [])

    def test_showcase_target_existing_explicit_info_plist_passes(self) -> None:
        self.write(
            "Examples/DVKCompanionShowcase/project.yml",
            """
            targets:
              DVKCompanionShowcase:
                settings:
                  INFOPLIST_FILE: Config/Info.plist
            """,
        )
        self.write(
            "Examples/DVKCompanionShowcase/Config/Info.plist",
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n",
        )

        self.assertEqual(check_showcase_info_plist(self.root), [])

    def test_showcase_target_missing_explicit_info_plist_fails(self) -> None:
        self.write(
            "Examples/DVKCompanionShowcase/project.yml",
            """
            targets:
              DVKCompanionShowcase:
                settings:
                  INFOPLIST_FILE: Config/Missing.plist
            """,
        )

        failures = check_showcase_info_plist(self.root)

        self.assertEqual(len(failures), 1)
        self.assertIn("does not resolve", failures[0])

    def test_showcase_target_explicit_path_outside_repository_fails(self) -> None:
        self.write(
            "Examples/DVKCompanionShowcase/project.yml",
            """
            targets:
              DVKCompanionShowcase:
                settings:
                  INFOPLIST_FILE: ../../../../outside/Info.plist
            """,
        )

        failures = check_showcase_info_plist(self.root)

        self.assertEqual(len(failures), 1)
        self.assertIn("does not resolve", failures[0])

    def test_other_target_generated_info_plist_does_not_satisfy_showcase(self) -> None:
        self.write(
            "Examples/DVKCompanionShowcase/project.yml",
            """
            targets:
              HelperApp:
                settings:
                  GENERATE_INFOPLIST_FILE: YES
              DVKCompanionShowcase:
                settings:
                  PRODUCT_BUNDLE_IDENTIFIER: org.example.Showcase
            """,
        )

        failures = check_showcase_info_plist(self.root)

        self.assertEqual(len(failures), 1)
        self.assertIn("showcase-info-plist", failures[0])

    def test_showcase_target_without_info_plist_configuration_fails(self) -> None:
        self.write(
            "Examples/DVKCompanionShowcase/project.yml",
            """
            targets:
              DVKCompanionShowcase:
                settings:
                  PRODUCT_BUNDLE_IDENTIFIER: org.example.Showcase
            """,
        )

        failures = check_showcase_info_plist(self.root)

        self.assertEqual(len(failures), 1)
        self.assertIn("showcase-info-plist", failures[0])


class IOSPackageSchemeTests(TemporaryRepositoryTestCase):
    def test_only_package_test_scheme_passes(self) -> None:
        self.write(
            ".github/workflows/ci.yml",
            """
            jobs:
              ios-simulator:
                steps:
                  - name: Test package
                    run: |
                      xcodebuild \\
                        -scheme DuplexVoiceKit-Package \\
                        -destination "platform=iOS Simulator,name=iPhone 17" \\
                        test
            """,
        )

        self.assertEqual(check_ios_package_test_scheme(self.root), [])

    def test_only_non_testable_duplex_voice_kit_scheme_fails(self) -> None:
        self.write(
            ".github/workflows/ci.yml",
            """
            jobs:
              ios-simulator:
                steps:
                  - name: Test package
                    run: |
                      xcodebuild \\
                        -scheme DuplexVoiceKit \\
                        -destination "platform=iOS Simulator,name=iPhone 17" \\
                        test
            """,
        )

        failures = check_ios_package_test_scheme(self.root)

        self.assertEqual(len(failures), 1)
        self.assertIn("ios-package-test-scheme", failures[0])
        self.assertIn("DuplexVoiceKit is not a testable", failures[0])

    def test_package_and_showcase_ui_test_schemes_pass(self) -> None:
        self.write(
            ".github/workflows/ci.yml",
            """
            jobs:
              ios-simulator:
                steps:
                  - run: |
                      xcodebuild -scheme DuplexVoiceKit-Package -destination "platform=iOS Simulator,name=iPhone 17" test
                      xcodebuild -scheme ShowcaseUITests -destination "platform=iOS Simulator,name=iPhone 17" test
            """,
        )

        self.assertEqual(check_ios_package_test_scheme(self.root), [])

    def test_only_showcase_ui_tests_without_package_scheme_fails(self) -> None:
        self.write(
            ".github/workflows/ci.yml",
            """
            jobs:
              ios-simulator:
                steps:
                  - run: |
                      xcodebuild \\
                        -scheme ShowcaseUITests \\
                        -destination "platform=iOS Simulator,name=iPhone 17" \\
                        test
            """,
        )

        failures = check_ios_package_test_scheme(self.root)

        self.assertEqual(len(failures), 1)
        self.assertIn("no DuplexVoiceKit-Package", failures[0])


class MainActorStoreDefaultTests(TemporaryRepositoryTestCase):
    def test_real_default_store_construction_fails(self) -> None:
        self.write(
            "Sources/DuplexVoiceKitUI/View.swift",
            """
            public struct CompanionView {
                public init(store: DVKCompanionStore = DVKCompanionStore()) {}
            }
            """,
        )

        failures = check_main_actor_store_defaults(self.root)

        self.assertEqual(len(failures), 1)
        self.assertIn("main-actor-store-default", failures[0])

    def test_matching_text_in_comment_passes(self) -> None:
        self.write(
            "Sources/DuplexVoiceKitUI/View.swift",
            "// store: DVKCompanionStore = DVKCompanionStore()\npublic init() {}\n",
        )

        self.assertEqual(check_main_actor_store_defaults(self.root), [])

    def test_matching_text_in_regular_string_passes(self) -> None:
        self.write(
            "Sources/DuplexVoiceKitUI/View.swift",
            'let example = "store: DVKCompanionStore = DVKCompanionStore()"\n',
        )

        self.assertEqual(check_main_actor_store_defaults(self.root), [])

    def test_matching_text_in_multiline_string_passes(self) -> None:
        self.write(
            "Sources/DuplexVoiceKitUI/View.swift",
            'let example = """\nstore: DVKCompanionStore = DVKCompanionStore()\n"""\n',
        )

        self.assertEqual(check_main_actor_store_defaults(self.root), [])

    def test_separate_store_and_no_argument_initializers_pass(self) -> None:
        self.write(
            "Sources/DuplexVoiceKitUI/View.swift",
            """
            public final class CompanionView {
                public init(store: DVKCompanionStore) {}

                public convenience init() {
                    self.init(store: DVKCompanionStore())
                }
            }
            """,
        )

        self.assertEqual(check_main_actor_store_defaults(self.root), [])


class ForegroundStyleTernaryTests(TemporaryRepositoryTestCase):
    def test_explicit_color_branches_pass(self) -> None:
        self.write(
            "Sources/DuplexVoiceKitUI/View.swift",
            """
            import SwiftUI

            let view = Text("Status")
                .foregroundStyle(hasError ? Color.red : Color.secondary)
            """,
        )

        self.assertEqual(check_foreground_style_ternaries(self.root), [])

    def test_implicit_hierarchical_and_color_mix_fails(self) -> None:
        self.write(
            "Sources/DuplexVoiceKitUI/View.swift",
            """
            import SwiftUI

            let view = Text("Status")
                .foregroundStyle(hasError ? .red : .secondary)
            """,
        )

        failures = check_foreground_style_ternaries(self.root)

        self.assertEqual(len(failures), 1)
        self.assertIn("foreground-style-ternary", failures[0])


class CommandLineEntryTests(TemporaryRepositoryTestCase):
    def write_valid_repository(self) -> None:
        self.write(
            "Examples/DVKCompanionShowcase/project.yml",
            """
            targets:
              DVKCompanionShowcase:
                settings:
                  GENERATE_INFOPLIST_FILE: YES
            """,
        )
        self.write(
            ".github/workflows/ci.yml",
            """
            jobs:
              ios-simulator:
                steps:
                  - run: |
                      xcodebuild \\
                        -scheme DuplexVoiceKit-Package \\
                        -destination "platform=iOS Simulator,name=iPhone 17" \\
                        test
            """,
        )
        self.write(
            "Sources/DuplexVoiceKitUI/Valid.swift",
            "public struct ValidView {}\n",
        )

    def run_entry(self) -> tuple[int, str, dict[str, object]]:
        output = io.StringIO()
        exit_code = run_command(self.root, output)
        raw_output = output.getvalue()
        payload = json.loads(raw_output)
        return exit_code, raw_output, payload

    def test_command_success_returns_zero_and_ok_json(self) -> None:
        self.write_valid_repository()

        exit_code, raw_output, payload = self.run_entry()

        self.assertEqual(exit_code, 0)
        self.assertEqual(raw_output.count("\n"), 1)
        self.assertEqual(payload["check_type"], "ci-failure-preflight")
        self.assertEqual(payload["status"], "ok")
        self.assertEqual(payload["failure_count"], 0)
        self.assertEqual(payload["failures"], [])

    def test_command_failure_returns_one_and_rule_json(self) -> None:
        self.write_valid_repository()
        self.write(
            "Sources/DuplexVoiceKitUI/Invalid.swift",
            "public init(store: DVKCompanionStore = DVKCompanionStore()) {}\n",
        )

        exit_code, raw_output, payload = self.run_entry()

        self.assertEqual(exit_code, 1)
        self.assertEqual(payload["status"], "failed")
        self.assertEqual(payload["failure_count"], len(payload["failures"]))
        self.assertEqual(payload["failure_count"], 1)
        self.assertIn("main-actor-store-default", payload["failures"][0])
        self.assertNotIn(str(self.root), raw_output)

    def test_command_output_is_stable_sorted_json_without_absolute_root(self) -> None:
        self.write_valid_repository()
        self.write(
            "Sources/DuplexVoiceKitUI/Invalid.swift",
            """
            public init(store: DVKCompanionStore = DVKCompanionStore()) {}
            let status = Text("Status")
                .foregroundStyle(hasError ? .red : .secondary)
            """,
        )

        first_code, first_output, first_payload = self.run_entry()
        second_code, second_output, second_payload = self.run_entry()

        self.assertEqual(first_code, 1)
        self.assertEqual(second_code, 1)
        self.assertEqual(first_output, second_output)
        self.assertEqual(first_payload, second_payload)
        self.assertEqual(first_payload["failures"], sorted(first_payload["failures"]))
        self.assertNotIn(str(self.root), first_output)

    def test_default_root_points_to_repository_root(self) -> None:
        self.assertEqual(PREFLIGHT_ROOT, Path(__file__).resolve().parents[2])
        self.assertEqual(
            PREFLIGHT_ROOT / "Scripts" / "ci_failure_preflight.py",
            Path(__file__).resolve().parents[1] / "ci_failure_preflight.py",
        )


if __name__ == "__main__":
    unittest.main()
