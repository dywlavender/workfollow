import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("ai_bundle", Path(__file__).parents[1] / "bundle-ai-backend.py")
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)


class AIBackendBundleTests(unittest.TestCase):
    def test_embed_omits_intel_from_older_universal_cache(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            cache, app = root / "cache", root / "WorkFollow.app"
            for arch in ("arm64", "x86_64"):
                for name in ("python/bin/python3", "node/bin/node"):
                    path = cache / "runtime" / arch / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text("test runtime")
            cli = cache / "pi/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js"
            cli.parent.mkdir(parents=True)
            cli.write_text("test engine")
            for arch in ("darwin-arm64", "darwin-x64"):
                (cache / "pi/node_modules/@esbuild" / arch).mkdir(parents=True)
            (cache / "runtime.json").write_text(json.dumps({"protocol": 1, "architectures": ["arm64", "x86_64"]}))
            (app / "Contents").mkdir(parents=True)
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleName": "WorkFollow"}))
            bundle.embed(app, cache)
            bundle.validate_layout(app)
            bundle.validate_arm64_only(app)
            runtime = app / "Contents/Resources/AIBackend"
            self.assertEqual(json.loads((runtime / "runtime.json").read_text())["architectures"], ["arm64"])
            self.assertEqual(json.loads((runtime / "runtime.json").read_text())["node"], "external")
            self.assertFalse((runtime / "runtime/arm64/node").exists())
            self.assertEqual(json.loads((runtime / "runtime.json").read_text())["pi"], "external")
            self.assertFalse((runtime / "pi").exists())
            self.assertFalse((runtime / "runtime/x86_64").exists())
            self.assertFalse((runtime / "pi/node_modules/@esbuild/darwin-x64").exists())
            self.assertFalse((runtime / "pi/node_modules/@esbuild/darwin-arm64").exists())
            backend = app / "Contents/Resources/AIBackend/backend"
            self.assertTrue((backend / "app/services/ai_service.py").exists())
            self.assertTrue((backend / "app/ai_runtime/prompts.py").exists())
            self.assertFalse((backend / "app/main.py").exists())
            self.assertFalse((backend / "app/db").exists())
            self.assertFalse((backend / "app/core/config.py").exists())
            self.assertEqual(plistlib.loads((app / "Contents/Info.plist").read_bytes())["WorkFollowAIBackendProtocol"], 1)
            self.assertTrue(plistlib.loads((app / "Contents/Info.plist").read_bytes())["WorkFollowAppleSiliconOnly"])
            (runtime / "runtime/arm64/python/bin/python3").unlink()
            with self.assertRaisesRegex(RuntimeError, "arm64"):
                bundle.validate_layout(app)

    def test_older_bundled_pi_packages_remain_valid_for_backup(self):
        with tempfile.TemporaryDirectory() as folder:
            app = Path(folder) / "WorkFollow.app"
            root = app / "Contents/Resources/AIBackend"
            names = ["backend/ai_entry.py", "resources/wf-meeting-stream.mjs", "resources/wf-meeting-audio.mjs",
                     "pi/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js"]
            for arch in ("arm64", "x86_64"):
                names += [f"runtime/{arch}/python/bin/python3", f"runtime/{arch}/node/bin/node"]
            for name in names:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("old component")
            (root / "runtime.json").write_text(json.dumps({"protocol": 1, "architectures": ["arm64", "x86_64"], "node": "22.23.4", "pi": "0.86.1"}))
            bundle.validate_layout(app)
            (root / names[3]).unlink()
            with self.assertRaisesRegex(RuntimeError, "pi/"):
                bundle.validate_layout(app)


if __name__ == "__main__":
    unittest.main()
