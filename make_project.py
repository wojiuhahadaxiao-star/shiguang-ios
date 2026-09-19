#!/usr/bin/env python3
"""Generate the dependency-free Xcode project. Python 3 standard library only."""
from pathlib import Path
import plistlib
import json

root = Path(__file__).resolve().parent
objects = {}
def obj(key, value):
    objects[key] = value
    return key
def ident(n): return f'{n:024X}'
project, group, products, target, product, source, build, sources, frameworks, resources, asset, assetbuild, plist = [ident(n) for n in range(1,14)]
obj(source, {'isa':'PBXFileReference','lastKnownFileType':'sourcecode.swift','path':'Shiguang/App.swift','sourceTree':'<group>'})
obj(asset, {'isa':'PBXFileReference','lastKnownFileType':'folder.assetcatalog','path':'Shiguang/Assets.xcassets','sourceTree':'<group>'})
obj(plist, {'isa':'PBXFileReference','lastKnownFileType':'text.plist.xml','path':'Shiguang/Info.plist','sourceTree':'<group>'})
obj(product, {'isa':'PBXFileReference','explicitFileType':'wrapper.application','path':'Shiguang.app','sourceTree':'BUILT_PRODUCTS_DIR'})
obj(build, {'isa':'PBXBuildFile','fileRef':source})
obj(assetbuild, {'isa':'PBXBuildFile','fileRef':asset})
privacy, privacybuild = ident(14), ident(15)
obj(privacy, {'isa':'PBXFileReference','lastKnownFileType':'text.xml','path':'Shiguang/PrivacyInfo.xcprivacy','sourceTree':'<group>'})
obj(privacybuild, {'isa':'PBXBuildFile','fileRef':privacy})
obj(group, {'isa':'PBXGroup','children':[source,asset,plist,privacy,products],'sourceTree':'<group>'})
obj(products, {'isa':'PBXGroup','children':[product],'name':'Products','sourceTree':'<group>'})
for key, kind, files in [(sources,'PBXSourcesBuildPhase',[build]),(frameworks,'PBXFrameworksBuildPhase',[]),(resources,'PBXResourcesBuildPhase',[assetbuild,privacybuild])]:
    obj(key, {'isa':kind,'buildActionMask':2147483647,'files':files,'runOnlyForDeploymentPostprocessing':0})
projectConfigs, targetConfigs = ident(20), ident(21)
for configID, base, settings in [
    (projectConfigs,30,{'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'15.0','CLANG_ENABLE_MODULES':'YES','SWIFT_VERSION':'5.0'}),
    (targetConfigs,40,{'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'cn.shiguang.photos.ios','INFOPLIST_FILE':'Shiguang/Info.plist','CODE_SIGN_STYLE':'Automatic','TARGETED_DEVICE_FAMILY':'1,2','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','SWIFT_VERSION':'5.0','IPHONEOS_DEPLOYMENT_TARGET':'15.0','CURRENT_PROJECT_VERSION':'2','MARKETING_VERSION':'1.7.0','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks'],'SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SWIFT_EMIT_LOC_STRINGS':'YES'})]:
    configs=[]
    for i,name in enumerate(['Debug','Release']):
        s=dict(settings);s['SWIFT_OPTIMIZATION_LEVEL']='-Onone' if name=='Debug' else '-O'
        if configID == targetConfigs:
            s['MARKETING_VERSION'] = '1.8.1'
            s['CURRENT_PROJECT_VERSION'] = '6'
        if name=='Debug':s['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
        configs.append(obj(ident(base+i),{'isa':'XCBuildConfiguration','name':name,'buildSettings':s}))
    obj(configID,{'isa':'XCConfigurationList','buildConfigurations':configs,'defaultConfigurationIsVisible':0,'defaultConfigurationName':'Release'})
obj(target, {'isa':'PBXNativeTarget','buildConfigurationList':targetConfigs,'buildPhases':[sources,frameworks,resources],'buildRules':[],'dependencies':[],'name':'Shiguang','productName':'Shiguang','productReference':product,'productType':'com.apple.product-type.application'})
obj(project, {'isa':'PBXProject','attributes':{'LastUpgradeCheck':'1600','TargetAttributes':{target:{'CreatedOnToolsVersion':'16.0'}}},'buildConfigurationList':projectConfigs,'compatibilityVersion':'Xcode 14.0','developmentRegion':'zh-Hans','hasScannedForEncodings':0,'knownRegions':['zh-Hans','en','Base'],'mainGroup':group,'productRefGroup':products,'projectDirPath':'','projectRoot':'','targets':[target]})
def serialize(value, level=0):
    if isinstance(value,dict): return '{\n'+''.join('\t'*(level+1)+json.dumps(str(k))+ ' = '+serialize(v,level+1)+';\n' for k,v in value.items())+'\t'*level+'}'
    if isinstance(value,list): return '('+', '.join(serialize(x,level+1) for x in value)+')'
    if isinstance(value,int): return str(value)
    return json.dumps(value,ensure_ascii=False)
pbx = {'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':project}
(root/'Shiguang.xcodeproj').mkdir(exist_ok=True)
(root/'Shiguang.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n'+serialize(pbx)+'\n')
info = {'CFBundleDevelopmentRegion':'zh-Hans','CFBundleDisplayName':'拾光','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'$(PRODUCT_NAME)','CFBundlePackageType':'APPL','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)','LSRequiresIPhoneOS':True,'UILaunchScreen':{},'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],'UISupportedInterfaceOrientations~ipad':['UIInterfaceOrientationPortrait','UIInterfaceOrientationPortraitUpsideDown','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],'NSPhotoLibraryUsageDescription':'拾光需要读取照片，以随机浏览、按拍摄日期整理，并在您确认后删除选中的照片。','UIUserInterfaceStyle':'Dark'}
info['UIApplicationSceneManifest'] = {
    'UIApplicationSupportsMultipleScenes': False,
    'UISceneConfigurations': {'UIWindowSceneSessionRoleApplication': [
        {'UISceneConfigurationName': 'Main', 'UISceneDelegateClassName': '$(PRODUCT_MODULE_NAME).SceneDelegate'}
    ]}
}
(root/'Shiguang/Info.plist').write_bytes(plistlib.dumps(info))
print('Generated Shiguang.xcodeproj and Info.plist')
