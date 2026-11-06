// Offline WKWebView runtime; Node is needed only on the developer's machine.
import * as esbuild from 'esbuild';
import { mkdirSync, existsSync, readFileSync, writeFileSync, copyFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = dirname(fileURLToPath(import.meta.url)), dist = join(root, 'dist');
mkdirSync(dist, { recursive: true });
const result = await esbuild.build({
  entryPoints: [join(root, 'src/editor.js')],
  bundle: true, format: 'iife', platform: 'browser', target: 'safari16',
  outfile: join(dist, 'milkdown.js'),
  mainFields: ['module', 'main'], conditions: ['import', 'browser', 'default'],
  minify: true, metafile: true, sourcemap: false, legalComments: 'none',
  loader: { '.css': 'css', '.woff2': 'file', '.woff': 'file', '.ttf': 'file' },
  assetNames: 'fonts/[name]',
});
copyFileSync(join(root, 'index.html'), join(dist, 'index.html'));

const packages = new Set();
for (const input of Object.keys(result.metafile.inputs)) {
  const match = input.match(/node_modules\/((?:@[^/]+\/)?[^/]+)/);
  if (match) packages.add(match[1]);
}
const notices = [];
for (const name of [...packages].sort()) {
  const directory = join(root, 'node_modules', name);
  const manifest = JSON.parse(readFileSync(join(directory, 'package.json'), 'utf8'));
  const file = ['LICENSE', 'LICENSE.md', 'LICENSE.txt', 'license', 'license.md', 'LICENSE-MIT']
    .find(file => existsSync(join(directory, file)));
  notices.push(`${name} ${manifest.version}\n${file ? readFileSync(join(directory, file), 'utf8') : `License: ${manifest.license}\n${manifest.repository?.url || manifest.repository || ''}`}`);
}
writeFileSync(join(dist, 'THIRD_PARTY_NOTICES.txt'), notices.join('\n\n' + '='.repeat(72) + '\n\n'));
console.log('Milkdown 离线 JS、CSS、字体与依赖许可已构建。');
