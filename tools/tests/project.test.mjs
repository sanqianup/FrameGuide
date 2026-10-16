import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { root, makeProject, outputs, filesUnder, id } from '../generate-project.mjs';

// Independent syntax parser for the deliberately restricted OpenStep plist we emit.
function parseOpenStep(text) {
  const tokens = text.replace(/^\/\/[^\n]*\n/, '').match(/"(?:\\.|[^"\\])*"|[{}()=;,]/g) ?? [];
  let i = 0;
  function take(token) { assert.equal(tokens[i++], token); }
  function value() {
    if (tokens[i] === '{') {
      i++; const object = {};
      while (tokens[i] !== '}') {
        const key = JSON.parse(tokens[i++]); assert.equal(Object.hasOwn(object, key), false, `duplicate ${key}`);
        take('='); object[key] = value(); take(';');
      }
      i++; return object;
    }
    if (tokens[i] === '(') {
      i++; const array = [];
      while (tokens[i] !== ')') { array.push(value()); take(','); }
      i++; return array;
    }
    assert.ok(tokens[i]?.startsWith('"'), `invalid token ${tokens[i]}`);
    return JSON.parse(tokens[i++]);
  }
  const result = value(); assert.equal(i, tokens.length); return result;
}
const generated = outputs();
const project = parseOpenStep(generated['FrameGuide.xcodeproj/project.pbxproj']);
const objects = project.objects;
const byType = type => Object.values(objects).filter(object => object.isa === type);
const contents = path => readFileSync(resolve(root, path), 'utf8');

test('generated Xcode OpenStep document parses independently and preserves the full graph', () => {
  assert.deepEqual(project, makeProject());
  assert.equal(objects[project.rootObject].isa, 'PBXProject');
  assert.equal(Object.keys(objects).every(key => /^[A-F0-9]{24}$/.test(key)), true);
});
test('committed project and shared scheme are deterministic and up to date', () => {
  for (const [path, expected] of Object.entries(generated)) assert.equal(contents(path), expected, path);
  assert.deepEqual(outputs(), generated);
});
test('every app and core Swift source is listed exactly once in the app build phase', () => {
  const expected = [...filesUnder('App'), ...filesUnder('Core/Sources')].filter(p => p.endsWith('.swift')).sort();
  const actual = objects[id('app-sources')].files.map(build => objects[objects[build].fileRef].path).sort();
  assert.deepEqual(actual, expected); assert.equal(new Set(actual).size, expected.length);
  assert.equal(actual.some(p => p.endsWith('Tests.swift')), false);
});
test('all XCTest files belong to the test target, with an app host and dependency', () => {
  const expected = filesUnder('Core/Tests').filter(p => p.endsWith('.swift'));
  assert.deepEqual(objects[id('test-sources')].files.map(build => objects[objects[build].fileRef].path).sort(), expected);
  assert.equal(objects[id('test-dependency')].target, id('app-target'));
  assert.ok(byType('XCBuildConfiguration').filter(c => c.buildSettings.PRODUCT_NAME === 'FrameGuideTests').every(c => c.buildSettings.TEST_HOST.includes('FrameGuide.app')));
});
test('file references exist and stay within this independent project', () => {
  for (const object of byType('PBXFileReference').filter(o => o.sourceTree === '<group>')) {
    assert.ok(!object.path.includes('..') && !/^[A-Z]:/i.test(object.path));
    assert.ok(existsSync(resolve(root, object.path)), object.path);
  }
});
test('all build references, configurations and product references resolve', () => {
  for (const object of Object.values(objects)) {
    for (const field of ['fileRef', 'mainGroup', 'productRefGroup', 'productReference', 'buildConfigurationList', 'containerPortal', 'target', 'targetProxy', 'remoteGlobalIDString']) {
      if (object[field]) assert.ok(objects[object[field]], `${object.isa}.${field}`);
    }
    for (const field of ['children', 'files', 'buildConfigurations', 'buildPhases', 'dependencies', 'targets']) {
      for (const key of object[field] ?? []) assert.ok(objects[key], `${object.isa}.${field}`);
    }
  }
});
test('shared scheme names real app and test targets', () => {
  const xml = generated['FrameGuide.xcodeproj/xcshareddata/xcschemes/FrameGuide.xcscheme'];
  const targets = [...xml.matchAll(/BlueprintIdentifier="([A-F0-9]+)"/g)].map(m => m[1]);
  assert.ok(targets.length >= 3);
  for (const target of targets) assert.equal(objects[target].isa, 'PBXNativeTarget');
  assert.ok(targets.includes(id('test-target')));
});
test('deployment baseline is 18.5, signing has no account or paid capabilities', () => {
  for (const config of byType('XCBuildConfiguration')) {
    assert.equal(config.buildSettings.IPHONEOS_DEPLOYMENT_TARGET, '18.5');
    assert.equal(config.buildSettings.SWIFT_VERSION, '5.0');
    assert.equal(config.buildSettings.CODE_SIGN_ENTITLEMENTS, undefined);
    if (config.buildSettings.DEVELOPMENT_TEAM !== undefined) assert.equal(config.buildSettings.DEVELOPMENT_TEAM, '');
  }
  assert.equal(byType('XCRemoteSwiftPackageReference').length, 0);
  assert.equal(byType('PBXShellScriptBuildPhase').length, 0);
});
test('privacy manifest is bundled; camera and add-only photo permission descriptions exist', () => {
  assert.deepEqual(objects[id('app-resources')].files.map(key => objects[objects[key].fileRef].path), ['App/PrivacyInfo.xcprivacy']);
  const plist = contents('App/Info.plist');
  assert.match(plist, /NSCameraUsageDescription/); assert.match(plist, /NSPhotoLibraryAddUsageDescription/);
  assert.doesNotMatch(plist, /NSPhotoLibraryUsageDescription|NSMicrophoneUsageDescription|NSAllowsArbitraryLoads|UIBackgroundModes/);
});
test('CI templates are inert, unsigned, with explicit guards for optional artifacts', () => {
  if (existsSync(resolve(root, '.github/workflows'))) {
    assert.deepEqual(filesUnder('.github/workflows'), ['.github/workflows/unsigned-device.yml']);
    const active = contents('.github/workflows/unsigned-device.yml');
    assert.match(active, /workflow_dispatch:/); assert.match(active, /free_budget_checked/);
    assert.doesNotMatch(active, /pull_request:|push:|schedule:|secrets\.|allowProvisioningUpdates/);
    assert.match(active, /runs-on: macos-15/); assert.match(active, /timeout-minutes: 20/);
  }
  const template = contents('ci/macos-build.yml.disabled');
  assert.match(template, /workflow_dispatch:/); assert.doesNotMatch(template, /pull_request:|push:|schedule:|secrets\.|upload-artifact|allowProvisioningUpdates/);
  assert.equal((template.match(/CODE_SIGNING_ALLOWED=NO/g) ?? []).length, 2);
  const artifact = contents('ci/windows-install-artifact.yml.disabled');
  assert.match(artifact, /free_budget_checked:/); assert.match(artifact, /default: false/);
  assert.match(artifact, /inputs\.free_budget_checked == true/);
  assert.match(artifact, /retention-days: 1/);
  assert.doesNotMatch(artifact, /pull_request:|push:|schedule:|secrets\.|allowProvisioningUpdates/);
  assert.match(contents('tools/prepare-unsigned-ipa.sh'), /CODE_SIGNING_ALLOWED=NO build/);
});
test('capture and analysis sources have no remote or analytics clients', () => {
  for (const path of filesUnder('App/Camera').filter(p => p.endsWith('.swift'))) {
    assert.doesNotMatch(contents(path), /URLSession|RemoteClient|Firebase|StoreKit|http[s]?:\/\//, path);
  }
});
test('source privacy and concurrency boundaries remain explicit', () => {
  const camera = contents('App/Camera/CameraEngine.swift');
  assert.match(camera, /alwaysDiscardsLateVideoFrames = true/);
  assert.match(camera, /sessionQueue\.async/);
  assert.match(camera, /if case \.analysis\(let result\).*isCurrent/);
  const remote = contents('App/Cloud/RemoteClient.swift');
  assert.match(remote, /guard !busy/); assert.match(remote, /completionHandler\(nil\)/);
  assert.match(remote, /ephemeral/); assert.doesNotMatch(remote, /print\(|NSLog\(|debugPrint\(/);
  assert.match(contents('App/Cloud/CloudSettings.swift'), /kSecAttrAccessibleWhenUnlockedThisDeviceOnly/);
  assert.match(contents('App/UI/SettingsScreen.swift'), /@AppStorage\("cloud.uploadAllowed"\).*false/);
});
test('original storage is byte-preserving and checksum guarded', () => {
  const store = contents('App/Storage/PhotoStore.swift');
  assert.match(store, /data\.write\(to: record.originalURL, options: \[\.atomic, \.completeFileProtection\]\)/);
  assert.match(store, /SHA256\.hash\(data: data\)/);
  assert.doesNotMatch(store, /UIImage|jpegData|pngData|URLSession/);
});
test('Swift unit tests include synthetic envelopes and stale-response cases, without API calls', () => {
  const tests = filesUnder('Core/Tests').map(contents).join('\n');
  assert.ok((tests.match(/func test/g) ?? []).length >= 18);
  assert.match(tests, /testSingleRequestAndStaleResponseRejection/);
  assert.match(tests, /testSyntheticRejectsOutOfRange/);
  assert.doesNotMatch(tests, /URLSession|SecretStore|RemoteClient/);
});
test('manual live UI exposes a frozen-frame confirmation and a stop action, never timer uploads', () => {
  const panel = contents('App/UI/LiveAdvicePanel.swift');
  assert.match(panel, /live\.prepare\(\)/);
  assert.match(panel, /live\.confirm\(item\)/);
  assert.match(panel, /Button\("停止"\).*live\.cancel/);
  assert.match(panel, /\.onReceive\(ticker\) \{ _ in live\.tick\(\) \}/);
  const model = contents('App/Cloud/LiveAdviceModel.swift');
  const prepare = model.slice(model.indexOf('func prepare()'), model.indexOf('func receive('));
  const receive = model.slice(model.indexOf('func receive('), model.indexOf('func confirm('));
  assert.doesNotMatch(prepare + receive, /RemoteClient|URLSession/);
  assert.match(model, /gate\.confirm\(item\.ticket/);
  assert.match(model, /gate\.accepts\(item\.ticket, now:/);
});
test('live preview sampling is one-shot, metadata-free and generation-checked', () => {
  const analyzer = contents('App/Camera/FrameAnalyzer.swift');
  assert.match(analyzer, /pendingPreview = \(id, revision,/);
  assert.match(analyzer, /let pending = pendingPreview; pendingPreview = nil/);
  assert.match(analyzer, /CGImageDestinationAddImage\(target, cg,/);
  assert.doesNotMatch(analyzer, /CGImageSourceCopyProperties|CGImageDestinationAddImageFromSource/);
  assert.match(contents('App/Camera/CameraEngine.swift'), /\.preview\(let id, \.success\(let sample\)\).*isCurrent\(sample.revision\)/);
});
test('permission lifecycle uses the tested intent and selected-lens taps cannot disable readiness', () => {
  const camera = contents('App/Camera/CameraEngine.swift');
  assert.match(camera, /private var startIntent = CameraStartIntent\(\)/);
  assert.match(camera, /startIntent\.resolved\(granted: granted\)/);
  assert.match(camera, /permissionDeniedOnQueue/);
  assert.match(contents('App/CameraModel.swift'), /guard screenActive, canCapture, id != selectedLens/);
  assert.match(contents('Core/Tests/CompositionCoreTests/CameraLifecycleTests.swift'), /testLatePermissionGrantDoesNotStartInBackground/);
});
test('motion invalidation is wired through frame completion, UI handoff and immediate display clearing', () => {
  const analyzer = contents('App/Camera/FrameAnalyzer.swift');
  assert.match(analyzer, /private var validity = AnalysisEpoch\(\)/);
  assert.match(analyzer, /let changed = validity\.setStable\(value\)/);
  assert.match(analyzer, /let ticket = validity\.ticket/);
  assert.match(analyzer, /guard isCurrent\(revision\) else \{ return \}/);
  assert.match(analyzer, /let valid = validity\.accepts\(revision\)/);
  const model = contents('App/CameraModel.swift');
  assert.match(model, /if !value \{ self\.analysis = nil; self\.clearGuideUI/);
  assert.match(model, /guard screenActive, motion\.stable, engine\.analyzer\.isCurrent\(result\.revision\)/);
  assert.match(contents('App/Camera/CameraEngine.swift'), /if case \.analysis\(let result\).*isCurrent\(result\.revision\)/);
});

test('selected-region tracking is local, throttled separately and clears stale targets', () => {
  const analyzer = contents('App/Camera/FrameAnalyzer.swift');
  assert.match(analyzer, /VNTrackObjectRequest\(detectedObjectObservation:/);
  assert.match(analyzer, /trackingLevel = \.fast/);
  assert.match(analyzer, /interval: p\.trackingInterval/);
  assert.match(analyzer, /decisionGate\.admit\(now: now, interval: policy\.interval\)/);
  assert.match(analyzer, /observation\.confidence >= 0\.65/);
  assert.match(analyzer, /if changed \{ selection = nil \}/);
  const model = contents('App/CameraModel.swift');
  assert.match(model, /freshness\.accept\(captured: result\.capturedAt/);
  assert.match(model, /freshness\.expired/);
  assert.match(model, /guard result\.guided != nil else/);
  assert.match(model, /case \.trackingLost/);
  assert.match(model, /已选择新主体，旧云端建议已清除/);
  assert.match(model, /主体追踪丢失，旧云端建议已清除/);
});
test('target overlay uses displayed sensor bounds and ignores letterbox taps', () => {
  const preview = contents('App/Camera/CameraPreview.swift');
  assert.match(preview, /imageRect\.contains\(point\)/);
  assert.match(preview, /target\.path = nil/);
  assert.match(preview, /guided\.aligned \? UIColor\.systemGreen : UIColor\.systemCyan/);
  assert.match(preview, /if selecting/);
  assert.match(contents('App/UI/CameraScreen.swift'), /Button\("退出引导"\)/);
});
test('zoom requires explicit user action and local looks reuse reversible renderer', () => {
  const camera = contents('App/Camera/CameraEngine.swift');
  assert.match(camera, /DigitalZoom\.requested/);
  const model = contents('App/CameraModel.swift');
  assert.match(model, /func applySuggestedZoom\(\)/);
  assert.match(model, /engine\.zoom\(by: factor\)/);
  assert.doesNotMatch(contents('App/Camera/FrameAnalyzer.swift'), /videoZoomFactor|\.zoom\(/);
  assert.match(contents('App/UI/LibraryScreen.swift'), /model\.apply\(look\.recipe\)/);
});
