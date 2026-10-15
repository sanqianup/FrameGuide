import { readdirSync, readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { resolve, dirname, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const destination = resolve(root, '..', 'FrameGuide-upload');
const excluded = new Set(['docs/environment-checkpoint.json', 'docs/FILE_MANIFEST.json']);
const skip = new Set(['.git', '.build', 'DerivedData', 'build', 'node_modules', '.github']);
const allowed = /(?:\.swift|\.mjs|\.json|\.plist|\.xcprivacy|\.xcscheme|\.pbxproj|\.md|\.ps1|\.sh|\.yml\.disabled|windows-checks\.txt|\.gitignore)$/;
const patterns = [
  ['private-key', /-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----/],
  ['github-token', /(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{25,})/],
  ['api-key-literal', /\bsk-[A-Za-z0-9_-]{20,}/],
  ['credential-in-url', /https?:\/\/[^\s/]+:[^\s/]+@/],
  ['local-user-path', /[A-Z]:[\\/]Users[\\/]/i]
];
function scan(directory = '') {
  return readdirSync(resolve(root, directory), { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name)).flatMap(entry => {
    const path = directory ? `${directory}/${entry.name}` : entry.name;
    if (skip.has(entry.name) || excluded.has(path)) return [];
    if (entry.isDirectory()) return scan(path);
    if (!entry.isFile() || !allowed.test(path)) throw new Error(`Unapproved source type: ${path}`);
    const data = readFileSync(resolve(root, path));
    const content = new TextDecoder('utf-8', { fatal: true }).decode(data);
    for (const [rule, regex] of patterns) {
      if (regex.test(content)) throw new Error(`Upload blocked by ${rule} in ${path}; matching data was NOT printed.`);
    }
    const encoded = Buffer.from(content, 'utf8');
    return [{ path, content, sha256: createHash('sha256').update(encoded).digest('hex'), bytes: encoded.length }];
  });
}
const entries = scan();
const manifest = { project: 'FrameGuide', scope: 'Source only; excludes local checkpoints, credentials, photos, binaries and active workflows.',
  excludes: ['docs/FILE_MANIFEST.json (self)', 'docs/environment-checkpoint.json', '.git', '.github', 'build', '.build', 'DerivedData', 'node_modules'],
  count: entries.length, files: entries.map(({ path, sha256, bytes }) => ({ path, sha256, bytes })) };
const publication = [...entries.map(({ path, content }) => ({ path, content })),
  { path: 'docs/FILE_MANIFEST.json', content: JSON.stringify(manifest, null, 2) + '\n' }];
if (process.argv.includes('--payload')) {
  const batchIndex = Number(process.argv[process.argv.indexOf('--batch') + 1]);
  const selected = process.argv.includes('--batch') ? publication.slice(batchIndex * 7, (batchIndex + 1) * 7) : publication;
  process.stdout.write(JSON.stringify(selected.map(({ path, content }) => ({ path, mode: '100644', type: 'blob', content }))));
} else {
  for (const entry of publication) {
    const target = resolve(destination, entry.path);
    if (!target.startsWith(destination + sep)) throw new Error('Path escaped publish root');
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, entry.content);
  }
  console.log(JSON.stringify({ stagedFiles: publication.length, sourceFiles: entries.length, batches: Math.ceil(publication.length / 7),
    stagedDirectory: relative(root, destination), secretScan: 'pass', photoFiles: 0, activeWorkflows: 0,
    excludedLocalFiles: [...excluded] }));
}
