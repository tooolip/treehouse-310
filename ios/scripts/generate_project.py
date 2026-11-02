#!/usr/bin/env python3
"""Generate a dependency-free Xcode project. Run after adding/removing Swift files."""
import hashlib
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
project = root / "Treehouse.xcodeproj"
project.mkdir(exist_ok=True)
existing_project = project / "project.pbxproj"
team = re.search(r'DEVELOPMENT_TEAM\s*=\s*"?([A-Z0-9]+)', existing_project.read_text()) if existing_project.exists() else None
local_config = root / "Local.xcconfig"
if team and not local_config.exists():
    local_config.write_text("// Personal signing settings; excluded from Git.\nDEVELOPMENT_TEAM = " + team.group(1) + "\n")
objects = {}

def ident(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def add(seed, isa, **values):
    key = ident(seed)
    objects[key] = {"isa": isa, **values}
    return key

def quote(value):
    if isinstance(value, dict):
        return "{ " + " ".join(f"{k} = {quote(v)};" for k, v in value.items()) + " }"
    if isinstance(value, list):
        return "(" + ", ".join(quote(v) for v in value) + ")"
    return json.dumps(str(value))

main_id = ident("project")
app_id = ident("app")
products = []
groups = []
targets = []
base = {"CLANG_ENABLE_MODULES": "YES", "SWIFT_VERSION": "5.0", "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
        "SDKROOT": "iphoneos", "TARGETED_DEVICE_FAMILY": "1", "CODE_SIGN_STYLE": "Automatic",
        "SWIFT_EMIT_LOC_STRINGS": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES"}
signing_config = add("signing_config", "PBXFileReference", lastKnownFileType="text.xcconfig", path="Signing.xcconfig", sourceTree="<group>")

def configs(name, settings):
    config_ids = []
    for mode in ["Debug", "Release"]:
        values = {**base, **settings}
        if mode == "Debug":
            values.update({"SWIFT_OPTIMIZATION_LEVEL": "-Onone", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
                           "DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES", "ONLY_ACTIVE_ARCH": "YES"})
        else:
            values.update({"SWIFT_OPTIMIZATION_LEVEL": "-O", "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
                           "SWIFT_COMPILATION_MODE": "wholemodule", "VALIDATE_PRODUCT": "YES"})
        configuration = {"name": mode, "buildSettings": values}
        if name == "project":
            configuration["baseConfigurationReference"] = signing_config
        config_ids.append(add(name + mode, "XCBuildConfiguration", **configuration))
    return add(name + "configs", "XCConfigurationList", buildConfigurations=config_ids,
               defaultConfigurationIsVisible="0", defaultConfigurationName="Release")

for name, directory, product_type, suffix in [
    ("Treehouse", "Treehouse", "com.apple.product-type.application", ".app"),
    ("TreehouseTests", "TreehouseTests", "com.apple.product-type.bundle.unit-test", ".xctest"),
    ("TreehouseUITests", "TreehouseUITests", "com.apple.product-type.bundle.ui-testing", ".xctest"),
]:
    is_app = name == "Treehouse"
    target_id = app_id if is_app else ident(name)
    refs, source_builds, resource_builds = [], [], []
    paths = sorted((root / directory).rglob("*.swift"))
    if is_app:
        paths += [root / directory / "Assets.xcassets", root / directory / "SampleSketch.png",
                  root / directory / "PrivacyInfo.xcprivacy", root / directory / "Info.plist"]
    for path in paths:
        relative = str(path.relative_to(root / directory))
        filetype = {".swift": "sourcecode.swift", ".xcassets": "folder.assetcatalog", ".png": "image.png",
                    ".xcprivacy": "text.xml", ".plist": "text.plist.xml"}[path.suffix]
        ref = add(directory + relative, "PBXFileReference", lastKnownFileType=filetype, path=relative, sourceTree="<group>")
        refs.append(ref)
        if path.name != "Info.plist":
            build = add(directory + relative + "build", "PBXBuildFile", fileRef=ref)
            (source_builds if path.suffix == ".swift" else resource_builds).append(build)
    groups.append(add(name + "group", "PBXGroup", children=refs, path=directory, sourceTree="<group>"))
    product = add(name + "product", "PBXFileReference", explicitFileType="wrapper.application" if is_app else "wrapper.cfbundle",
                  path=name + suffix, sourceTree="BUILT_PRODUCTS_DIR", includeInIndex="0")
    products.append(product)
    phases = [add(name + "sources", "PBXSourcesBuildPhase", buildActionMask="2147483647", files=source_builds, runOnlyForDeploymentPostprocessing="0"),
              add(name + "frameworks", "PBXFrameworksBuildPhase", buildActionMask="2147483647", files=[], runOnlyForDeploymentPostprocessing="0"),
              add(name + "resources", "PBXResourcesBuildPhase", buildActionMask="2147483647", files=resource_builds, runOnlyForDeploymentPostprocessing="0")]
    settings = {"PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "house.tree310." + name.lower(),
                "MARKETING_VERSION": "0.1", "CURRENT_PROJECT_VERSION": "1"}
    deps = []
    if is_app:
        settings.update({"INFOPLIST_FILE": "Treehouse/Info.plist", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                         "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks"})
    else:
        settings["GENERATE_INFOPLIST_FILE"] = "YES"
        if name == "TreehouseTests":
            settings["TEST_HOST"] = "$(BUILT_PRODUCTS_DIR)/Treehouse.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Treehouse"
            settings["BUNDLE_LOADER"] = "$(TEST_HOST)"
        else:
            settings["TEST_TARGET_NAME"] = "Treehouse"
        proxy = add(name + "proxy", "PBXContainerItemProxy", containerPortal=main_id, proxyType="1", remoteGlobalIDString=app_id, remoteInfo="Treehouse")
        deps.append(add(name + "dependency", "PBXTargetDependency", target=app_id, targetProxy=proxy))
    objects[target_id] = {"isa": "PBXNativeTarget", "buildConfigurationList": configs(name, settings), "buildPhases": phases,
                          "buildRules": [], "dependencies": deps, "name": name, "productName": name,
                          "productReference": product, "productType": product_type}
    targets.append(target_id)

product_group = add("products", "PBXGroup", children=products, name="Products", sourceTree="<group>")
main_group = add("main_group", "PBXGroup", children=groups + [signing_config, product_group], sourceTree="<group>")
objects[main_id] = {"isa": "PBXProject", "attributes": {"LastUpgradeCheck": "2700", "BuildIndependentTargetsInParallel": "YES",
                    "TargetAttributes": {app_id: {"CreatedOnToolsVersion": "27.1"}}},
                   "buildConfigurationList": configs("project", {}), "compatibilityVersion": "Xcode 14.0",
                   "developmentRegion": "en", "hasScannedForEncodings": "0", "knownRegions": ["en", "Base"],
                   "mainGroup": main_group, "productRefGroup": product_group, "projectDirPath": "", "projectRoot": "", "targets": targets}
contents = "// !$*UTF8*$!\n{\narchiveVersion = 1;\nclasses = {};\nobjectVersion = 56;\nobjects = {\n"
contents += "\n".join(f"{key} = {quote(value)};" for key, value in objects.items())
contents += f"\n}};\nrootObject = {main_id};\n}}\n"
(project / "project.pbxproj").write_text(contents)
scheme_dir = project / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)

def reference(target, product):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{product}" BlueprintName="{product.split(".")[0]}" ReferencedContainer="container:Treehouse.xcodeproj"/>'

(scheme_dir / "Treehouse.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.7">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference(app_id, "Treehouse.app")}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>
<TestableReference skipped="NO">{reference(ident("TreehouseTests"), "TreehouseTests.xctest")}</TestableReference>
<TestableReference skipped="NO">{reference(ident("TreehouseUITests"), "TreehouseUITests.xctest")}</TestableReference>
</Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(app_id, "Treehouse.app")}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(app_id, "Treehouse.app")}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(f"Generated {project}")
