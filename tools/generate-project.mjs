import { createHash } from 'node:crypto';
import { readdirSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

export const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const id = label => createHash('sha1').update(label).digest('hex').slice(0, 24).toUpperCase();
export function filesUnder(directory) {
  return readdirSync(resolve(root, directory), { withFileTypes: true }).flatMap(entry => {
    const path = `${directory}/${entry.name}`;
    return entry.isDirectory() ? filesUnder(path) : [path];
  }).sort();
}
export function makeProject() {
  const appSources = [...filesUnder('App'), ...filesUnder('Core/Sources')].filter(f => f.endsWith('.swift')).sort();
  const testSources = filesUnder('Core/Tests').filter(f => f.endsWith('.swift'));
  const resources = ['App/PrivacyInfo.xcprivacy'];
  const objects = {};
  const add = (name, value) => { const key = id(name); objects[key] = value; return key; };
  const ref = f => id(`ref:${f}`);
  for (const f of [...appSources, ...testSources, ...resources, 'App/Info.plist']) {
    add(`ref:${f}`, { isa: 'PBXFileReference', lastKnownFileType: f.endsWith('.swift') ? 'sourcecode.swift' : 'text.xml', path: f, sourceTree: '<group>' });
  }
  const app = add('app-product', { isa: 'PBXFileReference', explicitFileType: 'wrapper.application', path: 'FrameGuide.app', sourceTree: 'BUILT_PRODUCTS_DIR' });
  const tests = add('test-product', { isa: 'PBXFileReference', explicitFileType: 'wrapper.cfbundle', path: 'FrameGuideTests.xctest', sourceTree: 'BUILT_PRODUCTS_DIR' });
  const products = add('products', { isa: 'PBXGroup', children: [app, tests], name: 'Products', sourceTree: '<group>' });
  const group = add('group', { isa: 'PBXGroup', children: [...appSources, ...testSources, ...resources, 'App/Info.plist'].map(ref).concat(products), sourceTree: '<group>' });
  const phase = (name, isa, paths) => add(name, {
    isa, buildActionMask: '2147483647', files: paths.map(path => add(`build:${path}`, { isa: 'PBXBuildFile', fileRef: ref(path) })), runOnlyForDeploymentPostprocessing: '0'
  });
  const appPhases = [phase('app-sources', 'PBXSourcesBuildPhase', appSources), phase('app-frameworks', 'PBXFrameworksBuildPhase', []), phase('app-resources', 'PBXResourcesBuildPhase', resources)];
  const testPhases = [phase('test-sources', 'PBXSourcesBuildPhase', testSources), phase('test-frameworks', 'PBXFrameworksBuildPhase', [])];
  const configurations = (name, base, extras = {}) => {
    const values = ['Debug', 'Release'].map(configuration => add(`${name}-${configuration}`, {
      isa: 'XCBuildConfiguration', name: configuration, buildSettings: { ...base,
        SWIFT_OPTIMIZATION_LEVEL: configuration === 'Debug' ? '-Onone' : '-O',
        DEBUG_INFORMATION_FORMAT: configuration === 'Debug' ? 'dwarf' : 'dwarf-with-dsym',
        ...(configuration === 'Debug' ? { ENABLE_TESTABILITY: 'YES', SWIFT_ACTIVE_COMPILATION_CONDITIONS: 'DEBUG' } : {}), ...extras }
    }));
    return add(`${name}-configs`, { isa: 'XCConfigurationList', buildConfigurations: values, defaultConfigurationIsVisible: '0', defaultConfigurationName: 'Release' });
  };
  const common = { SDKROOT: 'iphoneos', IPHONEOS_DEPLOYMENT_TARGET: '18.5', SWIFT_VERSION: '5.0',
    SWIFT_STRICT_CONCURRENCY: 'targeted', CLANG_ENABLE_MODULES: 'YES', CLANG_ENABLE_OBJC_ARC: 'YES',
    TARGETED_DEVICE_FAMILY: '1', SUPPORTED_PLATFORMS: 'iphoneos iphonesimulator', SUPPORTS_MACCATALYST: 'NO' };
  const projectConfigs = configurations('project', common);
  const appConfigs = configurations('app', { ...common, PRODUCT_NAME: 'FrameGuide', PRODUCT_BUNDLE_IDENTIFIER: 'local.personal.FrameGuide',
    INFOPLIST_FILE: 'App/Info.plist', GENERATE_INFOPLIST_FILE: 'NO', CODE_SIGN_STYLE: 'Automatic', DEVELOPMENT_TEAM: '',
    LD_RUNPATH_SEARCH_PATHS: ['$(inherited)', '@executable_path/Frameworks'], ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS: 'NO' });
  const testConfigs = configurations('tests', { ...common, PRODUCT_NAME: 'FrameGuideTests', PRODUCT_BUNDLE_IDENTIFIER: 'local.personal.FrameGuideTests',
    GENERATE_INFOPLIST_FILE: 'YES', CODE_SIGN_STYLE: 'Automatic', DEVELOPMENT_TEAM: '',
    TEST_HOST: '$(BUILT_PRODUCTS_DIR)/FrameGuide.app/FrameGuide', BUNDLE_LOADER: '$(TEST_HOST)',
    LD_RUNPATH_SEARCH_PATHS: ['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks'] });
  add('app-target', { isa: 'PBXNativeTarget', name: 'FrameGuide', productName: 'FrameGuide', productReference: app,
    productType: 'com.apple.product-type.application', buildConfigurationList: appConfigs, buildPhases: appPhases, buildRules: [], dependencies: [] });
  const proxy = add('test-proxy', { isa: 'PBXContainerItemProxy', containerPortal: id('project'), proxyType: '1', remoteGlobalIDString: id('app-target'), remoteInfo: 'FrameGuide' });
  const dependency = add('test-dependency', { isa: 'PBXTargetDependency', target: id('app-target'), targetProxy: proxy });
  add('test-target', { isa: 'PBXNativeTarget', name: 'FrameGuideTests', productName: 'FrameGuideTests', productReference: tests,
    productType: 'com.apple.product-type.bundle.unit-test', buildConfigurationList: testConfigs, buildPhases: testPhases, buildRules: [], dependencies: [dependency] });
  add('project', { isa: 'PBXProject', attributes: { BuildIndependentTargetsInParallel: 'YES', LastUpgradeCheck: '1640',
    TargetAttributes: { [id('app-target')]: { CreatedOnToolsVersion: '16.4' }, [id('test-target')]: { CreatedOnToolsVersion: '16.4', TestTargetID: id('app-target') } } },
    buildConfigurationList: projectConfigs, compatibilityVersion: 'Xcode 14.0', developmentRegion: 'zh-Hans', knownRegions: ['en', 'Base', 'zh-Hans'],
    mainGroup: group, productRefGroup: products, projectDirPath: '', projectRoot: '', targets: [id('app-target'), id('test-target')] });
  return { archiveVersion: '1', classes: {}, objectVersion: '56', objects, rootObject: id('project') };
}
export function serialize(value, depth = 0) {
  const pad = '\t'.repeat(depth);
  if (Array.isArray(value)) return `(\n${value.map(v => `${pad}\t${serialize(v, depth + 1)},`).join('\n')}\n${pad})`;
  if (typeof value === 'object') return `{\n${Object.entries(value).map(([k, v]) => `${pad}\t${JSON.stringify(k)} = ${serialize(v, depth + 1)};`).join('\n')}\n${pad}}`;
  return JSON.stringify(String(value));
}
export function outputs() {
  const project = `// !$*UTF8*$!\n${serialize(makeProject())}\n`;
  const scheme = `<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1640" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
   <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${id('app-target')}" BuildableName="FrameGuide.app" BlueprintName="FrameGuide" ReferencedContainer="container:FrameGuide.xcodeproj"/>
  </BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables>
  <TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${id('test-target')}" BuildableName="FrameGuideTests.xctest" BlueprintName="FrameGuideTests" ReferencedContainer="container:FrameGuide.xcodeproj"/></TestableReference>
 </Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO">
  <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${id('app-target')}" BuildableName="FrameGuide.app" BlueprintName="FrameGuide" ReferencedContainer="container:FrameGuide.xcodeproj"/></BuildableProductRunnable>
 </LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${id('app-target')}" BuildableName="FrameGuide.app" BlueprintName="FrameGuide" ReferencedContainer="container:FrameGuide.xcodeproj"/></BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
`;
  return { 'FrameGuide.xcodeproj/project.pbxproj': project, 'FrameGuide.xcodeproj/xcshareddata/xcschemes/FrameGuide.xcscheme': scheme };
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const check = process.argv.includes('--check');
  for (const [path, content] of Object.entries(outputs())) {
    const full = resolve(root, path);
    if (check) {
      if (readFileSync(full, 'utf8') !== content) throw new Error(`${relative(root, full)} is stale; run node tools/generate-project.mjs`);
    } else { mkdirSync(dirname(full), { recursive: true }); writeFileSync(full, content); }
  }
  console.log(check ? 'Xcode project matches source manifest.' : 'Generated local Xcode project and shared scheme.');
}
