#!/usr/bin/env python3
"""Generate the dependency-free Xcode project. No third-party project tooling required."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess

def development_team():
    """Use an explicit team or the sole installed Apple Development certificate's team."""
    if team := os.environ.get('DUO_DEVELOPMENT_TEAM'):
        if not re.fullmatch(r'[A-Z0-9]{10}', team):
            raise SystemExit('DUO_DEVELOPMENT_TEAM must be a 10-character Apple team identifier.')
        return team
    try:
        identities = subprocess.run(['/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning'], check=True, capture_output=True, text=True).stdout
        names = re.findall(r'"(Apple Development:[^"]+)"', identities)
        if len(names) != 1:
            return None
        certificate = subprocess.run(['/usr/bin/security', 'find-certificate', '-c', names[0], '-p'], check=True, capture_output=True).stdout
        subject = subprocess.run(['/usr/bin/openssl', 'x509', '-noout', '-subject', '-nameopt', 'RFC2253'], input=certificate, check=True, capture_output=True).stdout.decode()
        match = re.search(r'(?:^|,)OU=([A-Z0-9]{10})(?:,|$)', subject)
        return match.group(1) if match else None
    except (OSError, subprocess.CalledProcessError):
        return None

root = Path(__file__).resolve().parent.parent
receiver = json.loads((root/'release/receiver.json').read_text())
if not re.fullmatch(r'0|[1-9][0-9]*', str(receiver['build'])) or int(receiver['build']) < 1:
    raise SystemExit('Receiver build must be a positive integer.')
if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', receiver['version']):
    raise SystemExit('Receiver version must use MAJOR.MINOR.PATCH.')
objects = {}
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(name, value):
    key = uid(name); objects[key] = value; return key

def config(name, settings): return add(name, {'isa': 'XCBuildConfiguration', 'buildSettings': settings, 'name': name.rsplit('-', 1)[-1]})
def configs(name, settings):
    ids = []
    for mode in ['Debug', 'Release']:
        values = dict(settings)
        values['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone' if mode == 'Debug' else '-O'
        values['DEBUG_INFORMATION_FORMAT'] = 'dwarf' if mode == 'Debug' else 'dwarf-with-dsym'
        if mode == 'Debug': values['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
        if mode == 'Release' and values.get('SDKROOT') == 'macosx':
            values['CODE_SIGN_INJECT_BASE_ENTITLEMENTS'] = 'NO'
        ids.append(config(f'{name}-{mode}', values))
    return add(name+'-configs', {'isa': 'XCConfigurationList', 'buildConfigurations': ids, 'defaultConfigurationIsVisible': 0, 'defaultConfigurationName': 'Release'})

shared = sorted((root/'Shared').glob('*.swift'))
products = []
targets = []
groups = []
mac_team = development_team()
for platform, name, bundle in [('iOS', 'DuoTrackpad', 'app.duotrackpad.ios'), ('macOS', 'DuoReceiver', 'app.duotrackpad.receiver')]:
    refs, builds = [], []
    for path in sorted((root/platform).glob('*.swift')) + shared:
        relative = str(path.relative_to(root))
        ref = add(name+'-file-'+relative, {'isa': 'PBXFileReference', 'lastKnownFileType': 'sourcecode.swift', 'path': relative, 'sourceTree': '<group>'})
        refs.append(ref)
        builds.append(add(name+'-'+relative, {'isa': 'PBXBuildFile', 'fileRef': ref}))
    groups.append(add(platform+'-group', {'isa': 'PBXGroup', 'children': refs, 'name': platform, 'sourceTree': '<group>'}))
    source = add(name+'-sources', {'isa': 'PBXSourcesBuildPhase', 'buildActionMask': 2147483647, 'files': builds, 'runOnlyForDeploymentPostprocessing': 0})
    asset = add(name+'-assets', {'isa': 'PBXFileReference', 'lastKnownFileType': 'folder.assetcatalog', 'path': platform+'/Assets.xcassets', 'sourceTree': '<group>'})
    objects[uid(platform+'-group')]['children'].append(asset)
    resource_build = add(name+'-resource-build', {'isa': 'PBXBuildFile', 'fileRef': asset})
    resources = add(name+'-resources', {'isa': 'PBXResourcesBuildPhase', 'buildActionMask': 2147483647, 'files': [resource_build], 'runOnlyForDeploymentPostprocessing': 0})
    privacy = root/platform/'PrivacyInfo.xcprivacy'
    if privacy.exists():
        privacy_ref = add(name+'-privacy', {'isa': 'PBXFileReference', 'lastKnownFileType': 'text.xml', 'path': str(privacy.relative_to(root)), 'sourceTree': '<group>'})
        objects[uid(platform+'-group')]['children'].append(privacy_ref)
        objects[resources]['files'].append(add(name+'-privacy-build', {'isa': 'PBXBuildFile', 'fileRef': privacy_ref}))
    frameworks = add(name+'-frameworks', {'isa': 'PBXFrameworksBuildPhase', 'buildActionMask': 2147483647, 'files': [], 'runOnlyForDeploymentPostprocessing': 0})
    product = add(name+'-product', {'isa': 'PBXFileReference', 'explicitFileType': 'wrapper.application', 'path': name+'.app', 'sourceTree': 'BUILT_PRODUCTS_DIR'})
    products.append(product)
    settings = {'PRODUCT_NAME': name, 'PRODUCT_BUNDLE_IDENTIFIER': bundle, 'SWIFT_VERSION': '5.0', 'GENERATE_INFOPLIST_FILE': 'YES', 'INFOPLIST_FILE': platform+'/Info.plist', 'CURRENT_PROJECT_VERSION': '1', 'MARKETING_VERSION': '1.0', 'CODE_SIGN_STYLE': 'Automatic', 'ENABLE_USER_SCRIPT_SANDBOXING': 'YES', 'SWIFT_STRICT_CONCURRENCY': 'targeted'}
    settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
    if platform == 'iOS': settings.update({'SDKROOT': 'iphoneos', 'IPHONEOS_DEPLOYMENT_TARGET': '27.1', 'TARGETED_DEVICE_FAMILY': '1,2', 'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator', 'SUPPORTS_MACCATALYST': 'NO'})
    else: settings.update({'SDKROOT': 'macosx', 'MACOSX_DEPLOYMENT_TARGET': receiver['minimumMacOS'], 'ARCHS': receiver['architecture'], 'ENABLE_APP_SANDBOX': 'NO', 'ENABLE_HARDENED_RUNTIME': 'YES', 'COMBINE_HIDPI_IMAGES': 'YES', 'CODE_SIGN_STYLE': 'Manual', 'CODE_SIGN_IDENTITY': 'Apple Development', 'MARKETING_VERSION': receiver['version'], 'CURRENT_PROJECT_VERSION': str(receiver['build']), 'PRODUCT_BUNDLE_IDENTIFIER': receiver['bundleId']})
    if mac_team:
        settings['DEVELOPMENT_TEAM'] = mac_team
    targets.append(add(name+'-target', {'isa': 'PBXNativeTarget', 'buildConfigurationList': configs(name, settings), 'buildPhases': [source, frameworks, resources], 'buildRules': [], 'dependencies': [], 'name': name, 'productName': name, 'productReference': product, 'productType': 'com.apple.product-type.application'}))
product_group = add('products', {'isa': 'PBXGroup', 'children': products, 'name': 'Products', 'sourceTree': '<group>'})
main = add('main', {'isa': 'PBXGroup', 'children': groups+[product_group], 'sourceTree': '<group>'})
project = add('project', {'isa': 'PBXProject', 'attributes': {'BuildIndependentTargetsInParallel': 'NO', 'LastUpgradeCheck': '2710'}, 'buildConfigurationList': configs('project', {'CLANG_ENABLE_MODULES': 'YES', 'CLANG_ENABLE_OBJC_ARC': 'YES'}), 'compatibilityVersion': 'Xcode 14.0', 'developmentRegion': 'en', 'hasScannedForEncodings': 0, 'knownRegions': ['en', 'Base'], 'mainGroup': main, 'productRefGroup': product_group, 'projectDirPath': '', 'projectRoot': '', 'targets': targets})
def render(value, indent=0):
    if isinstance(value, dict): return '{\n' + ''.join('\t'*(indent+1)+json.dumps(k)+' = '+render(v, indent+1)+';\n' for k,v in value.items()) + '\t'*indent+'}'
    if isinstance(value, list): return '(' + ', '.join(render(x, indent) for x in value) + ')'
    if isinstance(value, int): return str(value)
    return json.dumps(value)
project_dir = root/'DuoTrackpad.xcodeproj'
project_dir.mkdir(exist_ok=True)
(project_dir/'project.pbxproj').write_text('// !$*UTF8*$!\n'+render({'archiveVersion': 1, 'classes': {}, 'objectVersion': 56, 'objects': objects, 'rootObject': project})+'\n')
schemes = project_dir/'xcshareddata'/'xcschemes'; schemes.mkdir(parents=True, exist_ok=True)
for name in ['DuoTrackpad', 'DuoReceiver']:
    ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(name+"-target")}" BuildableName="{name}.app" BlueprintName="{name}" ReferencedContainer="container:DuoTrackpad.xcodeproj"/>'
    (schemes/(name+'.xcscheme')).write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2710" version="1.3"><BuildAction parallelizeBuildables="NO" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug"/><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print('Generated DuoTrackpad.xcodeproj')
