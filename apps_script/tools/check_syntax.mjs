import { readdirSync, readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { Script } from 'node:vm';

const source = new URL('../src/', import.meta.url);
const files = readdirSync(source).filter(file => file.endsWith('.js'));
const code = files.map(file => readFileSync(new URL(file, source), 'utf8')).join('\n');
new Script(code);
if (/\b(?:require|fetch|setTimeout|setInterval)\s*\(|\b(?:Buffer|process)\./.test(code.replace(/\bUrlFetchApp\.fetch\(/g, ''))) {
  throw new Error('A src/ mappában Node.js- és böngésző-API nem használható.');
}
for (const dir of ['tools', 'test']) {
  const url = new URL('../' + dir + '/', import.meta.url);
  for (const name of readdirSync(url).filter(file => file.endsWith('.mjs'))) {
    execFileSync(process.execPath, ['--check', fileURLToPath(new URL(name, url))], { stdio: 'inherit' });
  }
}
console.log('Az Apps Script és a helyi eszközök szintaxisa rendben.');
