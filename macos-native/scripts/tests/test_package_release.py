import importlib.util
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile


spec = importlib.util.spec_from_file_location("package_release", Path(__file__).parents[1] / "package-release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class PackageReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="workfollow-zip-test-")
        self.root = Path(self.temporary.name)
        self.app = self.root / "WorkFollow.app"
        contents = self.app / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "Resources").mkdir()
        shutil.copyfile("/usr/bin/true", contents / "MacOS/WorkFollow")
        (contents / "MacOS/WorkFollow").chmod(0o755)
        (contents / "Resources/example.txt").write_text("程序资源")
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": release.local_app.BUNDLE_ID, "CFBundleExecutable": "WorkFollow",
            "CFBundleName": "WorkFollow", "CFBundlePackageType": "APPL", "CFBundleVersion": "9",
            "CFBundleShortVersionString": "0.2.0", "LSMinimumSystemVersion": "14.0",
        }))
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(self.app)],
                       check=True, capture_output=True)

    def tearDown(self):
        self.temporary.cleanup()

    def test_zip_round_trip_keeps_signed_app_resources_and_installation_instructions(self):
        output = release.package(self.root / "安装包", source=self.app)
        folder = "WorkFollow-0.2.0-9-Mac"
        with zipfile.ZipFile(output) as archive:
            self.assertEqual(archive.read(folder + "/WorkFollow.app/Contents/Resources/example.txt").decode(), "程序资源")
        restored = release.verify_archive(output, self.root / "restored", folder)
        self.assertEqual(restored["CFBundleVersion"], "9")
        self.assertIn("0.2.0（9）", (self.root / "restored" / folder / "安装说明.txt").read_text())
        self.assertEqual(list(output.parent.iterdir()), [output], "临时应用与解压目录在完成后清理")

    def test_default_packages_a_fresh_source_build_instead_of_the_installed_app(self):
        def build(destination, number, identity):
            self.assertEqual(number, "9")
            self.assertEqual(identity, "-")
            shutil.copytree(self.app, destination)
            return destination
        with patch.object(release.local_app, "next_build", return_value="9"), \
             patch.object(release.local_app, "build", side_effect=build) as builder:
            output = release.package(self.root / "output")
        builder.assert_called_once()
        self.assertEqual(output.name, "WorkFollow-0.2.0-9-Mac.zip")
        self.assertTrue(output.is_file())


if __name__ == "__main__":
    unittest.main()
