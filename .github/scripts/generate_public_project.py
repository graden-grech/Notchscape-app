#!/usr/bin/env python3
"""Create an isolated Xcode project copy without the local-only Face Vault service."""

import argparse
import json
import pathlib
import plistlib
import subprocess
import sys

FACE_TARGET_NAME = "NotchscapeFaceVault"
MAIN_TARGET_NAME = "Notchscape"
FACE_PRODUCT = "NotchscapeFaceVault.xpc"
MODEL_RESOURCE = "Notchscape/Resources/FaceModels"
FACE_FLAG = "NotchFaceUnlockEnabled"


def require(value, message):
    if not value:
        raise ValueError(message)


def load_project(path):
    result = subprocess.run(
        ["/usr/bin/plutil", "-convert", "json", "-o", "-", str(path)],
        capture_output=True,
        check=False,
    )
    require(result.returncode == 0, "cannot parse Xcode project")
    project = json.loads(result.stdout)
    require(isinstance(project.get("objects"), dict), "Xcode project object table is missing")
    return project


def write_public_project(source_project, source_info, output_dir):
    """Write a fail-closed stripped project and public Info.plist in output_dir."""
    source_project = pathlib.Path(source_project)
    source_info = pathlib.Path(source_info)
    output_dir = pathlib.Path(output_dir)
    require(source_project.is_dir() and source_project.suffix == ".xcodeproj", "invalid source Xcode project")
    require(source_info.is_file(), "source Info.plist is missing")

    project = load_project(source_project / "project.pbxproj")
    objects = project["objects"]
    targets = [(identifier, obj) for identifier, obj in objects.items()
               if obj.get("isa") == "PBXNativeTarget"]
    face_targets = [(identifier, obj) for identifier, obj in targets if obj.get("name") == FACE_TARGET_NAME]
    main_targets = [(identifier, obj) for identifier, obj in targets if obj.get("name") == MAIN_TARGET_NAME]
    require(len(face_targets) == 1 and len(main_targets) == 1,
            "expected exactly one main target and one local Face Vault target")
    face_id, face_target = face_targets[0]
    main_id, main_target = main_targets[0]
    product_id = face_target.get("productReference")
    require(product_id in objects and objects[product_id].get("path") == FACE_PRODUCT,
            "Face Vault target product reference does not match expected XPC")

    removed = {face_id, product_id}
    # The service's private build phases, build files and configurations are
    # target-only. Face protocol/client source references are shared with the
    # main app and deliberately remain.
    for phase_id in face_target.get("buildPhases", []):
        phase = objects.get(phase_id, {})
        removed.add(phase_id)
        removed.update(phase.get("files", []))
    config_list_id = face_target.get("buildConfigurationList")
    if config_list_id:
        config_list = objects.get(config_list_id, {})
        removed.add(config_list_id)
        removed.update(config_list.get("buildConfigurations", []))

    # Remove the main target's build dependency and its embed-copy entry.
    dependencies_to_remove = []
    for dependency_id in main_target.get("dependencies", []):
        dependency = objects.get(dependency_id, {})
        if dependency.get("target") == face_id:
            dependencies_to_remove.append(dependency_id)
            proxy_id = dependency.get("targetProxy")
            if proxy_id:
                removed.add(proxy_id)
    removed.update(dependencies_to_remove)
    for phase_id in main_target.get("buildPhases", []):
        phase = objects.get(phase_id, {})
        for build_file_id in phase.get("files", []):
            file_ref = objects.get(build_file_id, {}).get("fileRef")
            if file_ref == product_id:
                removed.add(build_file_id)

    # Keep the MIT notice bundled, but exclude the local model weights.
    model_refs = {identifier for identifier, obj in objects.items()
                  if obj.get("isa") == "PBXFileReference" and obj.get("path") == MODEL_RESOURCE}
    require(len(model_refs) == 1, "expected exactly one FaceModels resource reference")
    model_ref = next(iter(model_refs))
    model_build_files = {identifier for identifier, obj in objects.items()
                         if obj.get("isa") == "PBXBuildFile" and obj.get("fileRef") == model_ref}
    require(len(model_build_files) == 1, "expected exactly one FaceModels resource build entry")
    removed.update(model_refs)
    removed.update(model_build_files)

    project_id = project.get("rootObject")
    require(project_id in objects and objects[project_id].get("isa") == "PBXProject",
            "project root is invalid")
    root = objects[project_id]
    require(face_id in root.get("targets", []), "Face Vault target is not registered with the project")
    # Xcode resolves PBXFileReference paths from the generated project folder,
    # even when the SRCROOT build setting is overridden. Point the project
    # directory at the real checkout so shared source groups still compile.
    repo_root = source_project.parent.resolve()
    root["projectDirPath"] = str(repo_root)
    root["targets"] = [value for value in root["targets"] if value != face_id]
    main_target["dependencies"] = [value for value in main_target.get("dependencies", [])
                                   if value not in dependencies_to_remove]

    # Remove all explicit references to deleted objects from project groups,
    # phases, and lists, without touching shared source file references.
    for obj in objects.values():
        for key, value in list(obj.items()):
            if isinstance(value, list):
                obj[key] = [item for item in value if item not in removed]
    for identifier in removed:
        objects.pop(identifier, None)

    # Validate the remaining graph's principal boundaries before writing.
    remaining_targets = {obj.get("name") for obj in objects.values() if obj.get("isa") == "PBXNativeTarget"}
    require(FACE_TARGET_NAME not in remaining_targets, "Face Vault target survived project stripping")
    require({MAIN_TARGET_NAME, "NotchscapeDockWidget", "NotchscapeHelper"} <= remaining_targets,
            "main app, Dock widget or original helper target was removed")
    require(not any(obj.get("path") == FACE_PRODUCT for obj in objects.values()),
            "Face Vault XPC product survived project stripping")
    require(not any(obj.get("path") == MODEL_RESOURCE for obj in objects.values()),
            "FaceModels resource survived project stripping")
    require(any(obj.get("path") == "Notchscape/Resources/FacePreviewNotices.txt" for obj in objects.values()),
            "MIT Face Preview notices must remain bundled")
    for obj in objects.values():
        for value in obj.values():
            if isinstance(value, list):
                require(not any(item in removed for item in value), "dangling Face Vault project reference remains")

    info = plistlib.loads(source_info.read_bytes())
    require(FACE_FLAG in info, "source Info.plist is missing the Face Unlock runtime gate")
    require(info.get("NotchAccountsEnabled") is False, "public build must keep accounts disabled")
    info[FACE_FLAG] = False

    output_dir.mkdir(parents=True, exist_ok=True)
    output_dir = output_dir.resolve()
    project_copy = output_dir / source_project.name
    subprocess.run(["/bin/cp", "-R", str(source_project), str(project_copy)], check=True)
    project_file = project_copy / "project.pbxproj"
    main_config_list_id = main_target.get("buildConfigurationList")
    require(main_config_list_id in objects, "main app build configuration list is missing")
    main_config_ids = objects[main_config_list_id].get("buildConfigurations", [])
    require(len(main_config_ids) >= 2, "main app Debug/Release configurations are missing")
    for configuration_id in main_config_ids:
        configuration = objects.get(configuration_id, {})
        require(configuration.get("isa") == "XCBuildConfiguration", "invalid main app build configuration")
        settings = configuration.setdefault("buildSettings", {})
        settings["INFOPLIST_FILE"] = str(output_dir / "Notchscape-Public-Info.plist")
        entitlement = settings.get("CODE_SIGN_ENTITLEMENTS")
        if isinstance(entitlement, str) and entitlement and not pathlib.Path(entitlement).is_absolute():
            settings["CODE_SIGN_ENTITLEMENTS"] = str(repo_root / entitlement)
    # The copied .xcodeproj lives under a temporary build directory. Signing
    # and plist inputs are resolved relative to PROJECT_DIR, so pin each
    # remaining product's files to the real checkout instead of letting Xcode
    # look for helper entitlements/plists beside the generated project.
    for _, target in objects.items():
        if target.get("isa") != "PBXNativeTarget" or target.get("name") == MAIN_TARGET_NAME:
            continue
        config_list = objects.get(target.get("buildConfigurationList"), {})
        for configuration_id in config_list.get("buildConfigurations", []):
            configuration = objects.get(configuration_id, {})
            settings = configuration.get("buildSettings", {})
            for key in ("INFOPLIST_FILE", "CODE_SIGN_ENTITLEMENTS"):
                value = settings.get(key)
                if isinstance(value, str) and value and not pathlib.Path(value).is_absolute():
                    settings[key] = str(repo_root / value)
    project_file.write_bytes(plistlib.dumps(project, fmt=plistlib.FMT_XML, sort_keys=False))
    info_path = output_dir / "Notchscape-Public-Info.plist"
    info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_XML, sort_keys=False))
    return project_copy, info_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_project", type=pathlib.Path)
    parser.add_argument("source_info", type=pathlib.Path)
    parser.add_argument("output_dir", type=pathlib.Path)
    args = parser.parse_args()
    try:
        project, info = write_public_project(args.source_project, args.source_info, args.output_dir)
    except (OSError, ValueError, KeyError, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
        print("FAIL: public project generation: " + str(error), file=sys.stderr)
        return 1
    print(json.dumps({"project": str(project), "info_plist": str(info)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
