import test from 'node:test';
import assert from 'node:assert/strict';
import { isImeCommitEnter, IME_COMMIT_WINDOW } from '../src/ime.js';

const enter = (extra = {}) => ({ key: 'Enter', keyCode: 13, shiftKey: false, ...extra });

test('IME keyCode 229 is blocked regardless of composition state', () => {
  assert.equal(isImeCommitEnter(enter({ keyCode: 229 }), 0, 100000), true);
  assert.equal(isImeCommitEnter(enter({ keyCode: 229, isComposing: false }), 0, 100000), true);
});

test('Enter right after compositionend is blocked, later Enter is not', () => {
  const now = 100000;
  assert.equal(isImeCommitEnter(enter(), now - 5, now), true);
  assert.equal(isImeCommitEnter(enter(), now - IME_COMMIT_WINDOW + 1, now), true);
  assert.equal(isImeCommitEnter(enter(), now - IME_COMMIT_WINDOW, now), false);
  assert.equal(isImeCommitEnter(enter(), 0, now), false);
});

test('shift+Enter, other keys and negative windows never count as IME commit', () => {
  const now = 100000;
  assert.equal(isImeCommitEnter(enter({ shiftKey: true, keyCode: 229 }), now, now), false);
  assert.equal(isImeCommitEnter(enter({ key: 'a', keyCode: 229 }), now, now), false);
  assert.equal(isImeCommitEnter(enter(), now + 1000, now), false);
});
