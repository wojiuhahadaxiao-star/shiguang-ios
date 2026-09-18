#!/usr/bin/env python3
"""Resource/reference checks only. Does not replace xcodebuild or iOS tests."""
from pathlib import Path
import json
import plistlib
import runpy
import struct
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent
project = runpy.run_path(str(root / 'make_project.py'))
objects = project['objects']
for item in objects.values():
    for key in ['fileRef', 'buildConfigurationList', 'productReference', 'mainGroup', 'productRefGroup']:
        if key in item: assert item[key] in objects, (key,item[key])
    for key in ['children','files','buildConfigurations','buildPhases','targets']:
        for ref in item.get(key,[]): assert ref in objects, (key,ref)
    if item['isa'] == 'PBXFileReference' and item.get('sourceTree') == '<group>':
        assert (root/item['path']).exists(), item['path']
with (root/'Shiguang/Info.plist').open('rb') as f:
    info = plistlib.load(f)
assert info['NSPhotoLibraryUsageDescription']
with (root/'Shiguang/PrivacyInfo.xcprivacy').open('rb') as f: plistlib.load(f)
scheme = ET.parse(root/'Shiguang.xcodeproj/xcshareddata/xcschemes/Shiguang.xcscheme')
for element in scheme.findall('.//BuildableReference'):
    assert objects[element.attrib['BlueprintIdentifier']]['isa'] == 'PBXNativeTarget'
for catalog in (root/'Shiguang/Assets.xcassets').rglob('Contents.json'):
    contents=json.loads(catalog.read_text())
    for image in contents.get('images',[]): assert (catalog.parent/image['filename']).is_file()
icon=(root/'Shiguang/Assets.xcassets/AppIcon.appiconset/AppIcon.png').read_bytes()
assert icon[:8] == b'\x89PNG\r\n\x1a\n'
assert struct.unpack('>II',icon[16:24]) == (1024,1024)
assert icon[25] == 2, 'App icon must be opaque RGB'
print('PASS: project references, file resources, scheme target, permission plist, privacy plist, opaque 1024px icon.')
print('NOT RUN: Swift compiler, Xcode build, simulator, physical iPhone.')
