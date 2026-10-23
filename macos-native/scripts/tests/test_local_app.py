import importlib.util
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("local_app", Path(__file__).parents[1] / "local-app.py")
local_app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(local_app)


class LocalAppTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="workfollow-installer-test-")
        self.root = Path(self.temp.name)
        self.destination = self.root / "Applications/WorkFollow.app"
        self.backup = self.root / "previous"

    def tearDown(self):
        self.temp.cleanup()

    def app(self, name, version, qa=False, legacy=False):
        app = self.root / (name + ".app")
        contents = app / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        shutil.copyfile("/usr/bin/true", contents / "MacOS/WorkFollow")
        (contents / "MacOS/WorkFollow").chmod(0o755)
        value = {"CFBundleIdentifier": local_app.BUNDLE_ID, "CFBundleExecutable": "WorkFollow",
                 "CFBundleName": "WorkFollow", "CFBundlePackageType": "APPL",
                 "CFBundleVersion": str(version), "CFBundleShortVersionString": "0.2.0"}
        if qa:
            value["WorkFollowAcceptanceStorageRoot"] = "/private/tmp/qa"
        elif legacy:
            value["WorkFollowAcceptanceStorageRoot"] = ""
        with (contents / "Info.plist").open("wb") as stream:
            plistlib.dump(value, stream)
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(app)],
                       capture_output=True, check=True)
        return app

    def test_install_update_and_rollback_keep_one_previous_app(self):
        first = self.app("first", 1, legacy=True)
        second = self.app("second", 2)
        local_app.install(first, self.destination, self.backup)
        self.assertFalse((self.backup / "WorkFollow.app").exists())
        local_app.install(second, self.destination, self.backup)
        self.assertEqual(local_app.validate(self.destination)["CFBundleVersion"], "2")
        self.assertEqual(local_app.info(self.backup / "WorkFollow.app")["CFBundleVersion"], "1")
        local_app.install(self.backup / "WorkFollow.app", self.destination, self.backup)
        self.assertEqual(local_app.validate(self.destination)["CFBundleVersion"], "1")
        self.assertEqual(local_app.validate(self.backup / "WorkFollow.app")["CFBundleVersion"], "2")
        self.assertEqual(list(self.destination.parent.iterdir()), [self.destination])

    def test_qa_package_cannot_replace_the_daily_app(self):
        local_app.install(self.app("daily", 1), self.destination, self.backup)
        with self.assertRaisesRegex(local_app.AppError, "验收配置"):
            local_app.install(self.app("qa", 2, qa=True), self.destination, self.backup)
        self.assertEqual(local_app.validate(self.destination)["CFBundleVersion"], "1")

    def test_widget_extension_is_allowed_but_test_plugins_remain_rejected(self):
        app = self.app("widget", 3)
        widget = app / "Contents/PlugIns/WorkFollowWidgets.appex"
        (widget / "Contents/MacOS").mkdir(parents=True)
        shutil.copyfile("/usr/bin/true", widget / "Contents/MacOS/WorkFollowWidgets")
        with (widget / "Contents/Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleIdentifier": local_app.BUNDLE_ID + ".widgets",
                          "CFBundleExecutable": "WorkFollowWidgets", "CFBundlePackageType": "XPC!",
                          "NSExtension": {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"}}, stream)
        for bundle in [widget, app]:
            subprocess.run(["codesign", "--force", "--sign", "-", str(bundle)], capture_output=True, check=True)
        self.assertEqual(local_app.validate(app)["CFBundleVersion"], "3")
        (app / "Contents/PlugIns/WorkFollowTests.xctest").mkdir()
        with self.assertRaisesRegex(local_app.AppError, "测试插件"):
            local_app.validate(app)

    def test_local_widget_packaging_selects_matching_own_container_without_group_entitlements(self):
        app = self.app("local-widget", 4)
        widget = app / "Contents/PlugIns/WorkFollowWidgets.appex"
        (widget / "Contents").mkdir(parents=True)
        (widget / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": local_app.BUNDLE_ID + ".widgets", "WorkFollowWidgetTransport": "appGroup"}))
        host_entitlements, widget_entitlements = local_app.configure_local_widgets(app, self.root)
        self.assertEqual(local_app.info(app)["WorkFollowWidgetTransport"], "widgetContainer")
        self.assertEqual(local_app.info(widget)["WorkFollowWidgetTransport"], "widgetContainer")
        self.assertEqual(plistlib.loads(host_entitlements.read_bytes()), {})
        self.assertEqual(plistlib.loads(widget_entitlements.read_bytes()), {"com.apple.security.app-sandbox": True})

    def test_update_restarts_only_previous_installed_widget_after_package_replacement(self):
        first, second = self.app("widget-first", 1), self.app("widget-second", 2)
        for app in [first, second]:
            widget = app / "Contents/PlugIns/WorkFollowWidgets.appex"
            (widget / "Contents/MacOS").mkdir(parents=True)
            shutil.copyfile("/usr/bin/true", widget / "Contents/MacOS/WorkFollowWidgets")
            (widget / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": local_app.BUNDLE_ID + ".widgets",
                "CFBundleExecutable": "WorkFollowWidgets", "CFBundlePackageType": "XPC!",
                "NSExtension": {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"}}))
            for bundle in [widget, app]:
                subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(bundle)],
                               capture_output=True, check=True)
        extension = self.destination / "Contents/PlugIns/WorkFollowWidgets.appex"
        previous_executable = str(extension / "Contents/MacOS/WorkFollowWidgets")
        run = subprocess.run
        registrations, stopped = [], []

        def command(args, **kwargs):
            if args[:2] == ["/bin/ps", "-axo"]:
                output = (f"12345 {previous_executable}\n"
                          "23456 /Applications/WorkFollow Widget Action QA.app/Contents/PlugIns/WorkFollowWidgets.appex/Contents/MacOS/WorkFollowWidgets\n"
                          f"34567 {self.destination}/Contents/MacOS/WorkFollow\n") if args[2] == "pid=,comm=" else ""
                return subprocess.CompletedProcess(args, 0, stdout=output, stderr="")
            if args[:2] == ["/usr/bin/pluginkit", "-a"]:
                registrations.append(args[2])
                return subprocess.CompletedProcess(args, 0, stdout="", stderr="")
            return run(args, **kwargs)

        def stop(pid, action):
            self.assertEqual(local_app.info(self.destination)["CFBundleVersion"], "2")
            self.assertEqual(local_app.info(self.backup / "WorkFollow.app")["CFBundleVersion"], "1")
            stopped.append((pid, action))

        with patch.object(local_app.subprocess, "run", side_effect=command), patch.object(local_app.os, "kill", side_effect=stop):
            local_app.install(first, self.destination, self.backup)
            local_app.install(second, self.destination, self.backup)
        self.assertEqual(stopped, [(12345, local_app.signal.SIGTERM)])
        self.assertEqual(registrations, [str(extension), str(extension)])


if __name__ == "__main__":
    unittest.main()
