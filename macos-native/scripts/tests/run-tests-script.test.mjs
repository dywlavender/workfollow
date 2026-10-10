import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

const script = fileURLToPath(new URL('../run-tests.sh', import.meta.url));

function run(mode) {
  const root = mkdtempSync(join(tmpdir(), 'wf-test-entry-'));
  const bin = join(root, 'bin');
  const derived = join(root, 'derived');
  const developer = join(root, 'developer');
  mkdirSync(bin);
  mkdirSync(join(derived, 'Build/Products/Debug/WorkFollow.app/Contents/PlugIns/WorkFollowTests.xctest/Contents'), { recursive: true });
  writeFileSync(join(derived, 'Build/Products/Debug/WorkFollow.app/Contents/Info.plist'), '<?xml version="1.0"?><plist version="1.0"><dict></dict></plist>');
  mkdirSync(join(developer, 'Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework'), { recursive: true });
  mkdirSync(join(developer, 'Platforms/MacOSX.platform/Developer/usr/lib'), { recursive: true });
  writeFileSync(join(developer, 'Platforms/MacOSX.platform/Developer/usr/lib/libXCTestSwiftSupport.dylib'), '');
  function executable(name, body) {
    const path = join(bin, name);
    writeFileSync(path, '#!/bin/bash\n' + body, { mode: 0o755 });
    return path;
  }
  const runner = executable('fixture-xctest', `
touch "$MOCK_ROOT/runner-called"
case "$MOCK_MODE" in
  zero) echo 'Executed 0 tests, with 0 failures'; exit 0 ;;
  mixed-skip) echo 'Executed 2 tests, with 1 test skipped and 0 failures'; exit 0 ;;
  all-skip) echo 'Executed 2 tests, with 2 tests skipped and 0 failures'; exit 0 ;;
  tests-fail) echo 'Executed 2 tests, with 1 failure'; exit 7 ;;
  *) echo 'Executed 2 tests, with 0 failures'; exit 0 ;;
esac
`);
  executable('xcodebuild', `
if [[ "$MOCK_MODE" == build-fail ]]; then echo 'fixture compilation error'; exit 21; fi
echo '** TEST BUILD SUCCEEDED **'
`);
  executable('xcode-select', 'echo "$MOCK_DEVELOPER"\n');
  executable('xcrun', 'echo "$MOCK_RUNNER"\n');
  try {
    const result = spawnSync('/bin/bash', [script, 'FixtureTests'], {
      encoding: 'utf8', env: { ...process.env, PATH: bin + ':' + process.env.PATH,
        MOCK_ROOT: root, MOCK_MODE: mode, MOCK_DEVELOPER: developer, MOCK_RUNNER: runner,
        WORKFOLLOW_DERIVED_DATA: derived },
    });
    return { status: result.status, output: result.stdout + result.stderr,
      runnerCalled: existsSync(join(root, 'runner-called')) };
  } finally { rmSync(root, { recursive: true, force: true }); }
}

test('failed build never executes an existing stale test bundle', () => {
  const result = run('build-fail');
  assert.equal(result.status, 21);
  assert.equal(result.runnerCalled, false);
});
test('zero tests cannot pass', () => {
  const result = run('zero');
  assert.equal(result.status, 1);
  assert.match(result.output, /没有执行任何测试/);
});
test('test process failure is propagated', () => assert.equal(run('tests-fail').status, 7));
test('a nonempty successful run passes', () => assert.equal(run('pass').status, 0));

test('a passed test and a skipped test still count as a nonempty run', () => assert.equal(run('mixed-skip').status, 0));
test('an entirely skipped run cannot pass', () => assert.equal(run('all-skip').status, 1));
