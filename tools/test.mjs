#!/usr/bin/env node
// Transpiles the UI-free protocol modules with the SDK's TypeScript and runs node:test on them.
import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, '..');
const sdk = process.env.OHOS_BASE_SDK_HOME ||
  (/^sdk\.dir=(.+)$/m.exec(fs.readFileSync(path.join(root, 'local.properties'), 'utf8')) ?? [])[1];
const api = fs.readdirSync(sdk).filter((d) => /^\d+(\.\d+)*$/.test(d)).sort((a, b) => parseFloat(b) - parseFloat(a))[0];
const require = createRequire(import.meta.url);
const ts = require(path.join(sdk, api, 'ets/build-tools/ets-loader/node_modules/typescript'));
const ets = path.join(root, 'entry/src/main/ets');
const out = fs.mkdtempSync(path.join(os.tmpdir(), 'harmonypods-test-'));
fs.writeFileSync(path.join(out, 'package.json'), '{"type":"commonjs"}');
for (const m of fs.readFileSync(path.join(here, 'test-modules.txt'), 'utf8').split('\n').map((s) => s.trim()).filter(Boolean)) {
  const js = ts.transpileModule(fs.readFileSync(path.join(ets, m + '.ets'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }, fileName: m + '.ts'
  }).outputText;
  fs.mkdirSync(path.join(out, path.dirname(m)), { recursive: true });
  fs.writeFileSync(path.join(out, m + '.js'), js);
}
const tests = fs.readdirSync(path.join(here, 'tests')).filter((f) => f.endsWith('.test.mjs'))
  .map((f) => path.join(here, 'tests', f));
const r = spawnSync(process.execPath, ['--test', ...tests], { stdio: 'inherit', env: { ...process.env, CV_OUT: out } });
fs.rmSync(out, { recursive: true, force: true });
process.exit(r.status ?? 1);
