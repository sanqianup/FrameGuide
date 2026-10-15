import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const manifestPath = 'docs/FILE_MANIFEST.json';
function scan(dir = '') {
  return readdirSync(resolve(root, dir), { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name)).flatMap(entry => {
    const path = dir ? `${dir}/${entry.name}` : entry.name;
    if (['.git', '.build', 'DerivedData', 'build', 'node_modules'].includes(entry.name)) return [];
    if (entry.isDirectory()) return scan(path);
    if (!entry.isFile() || path === manifestPath) return [];
    const bytes = readFileSync(resolve(root, path));
    return [{ path, bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') }];
  });
}
const files = scan();
writeFileSync(resolve(root, manifestPath), JSON.stringify({
  project: 'FrameGuide', createdUTC: new Date().toISOString(),
  scope: 'Local source delivery only; no Swift build or device validation performed.',
  excludes: [manifestPath, '.git', '.build', 'DerivedData', 'build', 'node_modules'],
  count: files.length, files
}, null, 2) + '\n');
console.log(`Wrote ${files.length} file entries (manifest excludes itself).`);
