import importlib.util
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest


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

    def app(self, name, version, qa=False):
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
        with (contents / "Info.plist").open("wb") as stream:
            plistlib.dump(value, stream)
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(app)],
                       capture_output=True, check=True)
        return app

    def test_install_update_and_rollback_keep_one_previous_app(self):
        first = self.app("first", 1)
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


if __name__ == "__main__":
    unittest.main()
