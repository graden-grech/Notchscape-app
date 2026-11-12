import importlib.util
import pathlib
import plistlib
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[3]
GENERATOR_SPEC = importlib.util.spec_from_file_location(
    "public_project", ROOT / ".github/scripts/generate_public_project.py"
)
GENERATOR = importlib.util.module_from_spec(GENERATOR_SPEC)
GENERATOR_SPEC.loader.exec_module(GENERATOR)
SIGNING_SPEC = importlib.util.spec_from_file_location(
    "face_vault_signing", ROOT / ".github/scripts/face_vault_signing.py"
)
SIGNING = importlib.util.module_from_spec(SIGNING_SPEC)
SIGNING_SPEC.loader.exec_module(SIGNING)


def synthetic_project():
    objects = {
        "P": {"isa": "PBXProject", "targets": ["MAIN", "FACE", "DOCK", "HELPER"],
              "mainGroup": "ROOT", "productRefGroup": "PRODUCTS"},
        "ROOT": {"isa": "PBXGroup", "children": ["FACEGROUP", "MODELREF", "NOTICEREF"]},
        "PRODUCTS": {"isa": "PBXGroup", "children": ["FACEPRODUCT"]},
        "FACEGROUP": {"isa": "PBXGroup", "children": ["SHAREDSOURCE"], "path": "NotchscapeFaceVault"},
        "SHAREDSOURCE": {"isa": "PBXFileReference", "path": "FaceVaultXPCProtocol.swift"},
        "FACE": {"isa": "PBXNativeTarget", "name": "NotchscapeFaceVault", "productReference": "FACEPRODUCT",
                 "buildPhases": ["FACEPHASE"], "dependencies": [], "buildConfigurationList": "FACECONFIGLIST"},
        "MAIN": {"isa": "PBXNativeTarget", "name": "Notchscape", "productReference": "MAINPRODUCT",
                 "buildPhases": ["EMBED", "RESOURCES"], "dependencies": ["FACEDEP"],
                 "buildConfigurationList": "MAINCONFIGLIST"},
        "DOCK": {"isa": "PBXNativeTarget", "name": "NotchscapeDockWidget", "buildPhases": [], "dependencies": []},
        "HELPER": {"isa": "PBXNativeTarget", "name": "NotchscapeHelper", "buildPhases": [], "dependencies": []},
        "FACEPRODUCT": {"isa": "PBXFileReference", "path": "NotchscapeFaceVault.xpc"},
        "MAINPRODUCT": {"isa": "PBXFileReference", "path": "Notchscape.app"},
        "FACEPHASE": {"isa": "PBXSourcesBuildPhase", "files": ["FACETARGETBUILD"]},
        "FACETARGETBUILD": {"isa": "PBXBuildFile", "fileRef": "SHAREDSOURCE"},
        "FACECONFIGLIST": {"isa": "XCConfigurationList", "buildConfigurations": ["FACECONFIG"]},
        "FACECONFIG": {"isa": "XCBuildConfiguration", "buildSettings": {"CODE_SIGN_ENTITLEMENTS": "face.entitlements"}},
        "MAINCONFIGLIST": {"isa": "XCConfigurationList", "buildConfigurations": ["MAINDEBUG", "MAINRELEASE"]},
        "MAINDEBUG": {"isa": "XCBuildConfiguration", "buildSettings": {"INFOPLIST_FILE": "Notchscape/Info.plist"}},
        "MAINRELEASE": {"isa": "XCBuildConfiguration", "buildSettings": {"INFOPLIST_FILE": "Notchscape/Info.plist"}},
        "FACEDEP": {"isa": "PBXTargetDependency", "target": "FACE", "targetProxy": "PROXY"},
        "PROXY": {"isa": "PBXContainerItemProxy", "remoteGlobalIDString": "FACE"},
        "EMBED": {"isa": "PBXCopyFilesBuildPhase", "files": ["FACEEMBED", "HELPEREMBED"]},
        "FACEEMBED": {"isa": "PBXBuildFile", "fileRef": "FACEPRODUCT"},
        "HELPEREMBED": {"isa": "PBXBuildFile", "fileRef": "HELPERPRODUCT"},
        "HELPERPRODUCT": {"isa": "PBXFileReference", "path": "NotchscapeHelper.xpc"},
        "RESOURCES": {"isa": "PBXResourcesBuildPhase", "files": ["MODELBUILD", "NOTICEBUILD"]},
        "MODELBUILD": {"isa": "PBXBuildFile", "fileRef": "MODELREF"},
        "MODELREF": {"isa": "PBXFileReference", "path": "Notchscape/Resources/FaceModels"},
        "NOTICEBUILD": {"isa": "PBXBuildFile", "fileRef": "NOTICEREF"},
        "NOTICEREF": {"isa": "PBXFileReference", "path": "Notchscape/Resources/FacePreviewNotices.txt"},
    }
    return {"objects": objects, "rootObject": "P"}


class PublicProjectTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        base = pathlib.Path(self.temp.name)
        self.project = base / "Notchscape.xcodeproj"
        self.project.mkdir()
        with (self.project / "project.pbxproj").open("wb") as output:
            plistlib.dump(synthetic_project(), output)
        self.info = base / "Info.plist"
        self.info.write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "theboringteam.boringnotch",
            "NotchAccountsEnabled": False,
            "NotchFaceUnlockEnabled": True,
        }))
        self.output = base / "generated"

    def tearDown(self):
        self.temp.cleanup()

    def test_public_copy_removes_only_local_face_service_and_model(self):
        project_path, info_path = GENERATOR.write_public_project(self.project, self.info, self.output)
        copied = GENERATOR.load_project(project_path / "project.pbxproj")
        objects = copied["objects"]
        targets = {obj.get("name") for obj in objects.values() if obj.get("isa") == "PBXNativeTarget"}
        self.assertEqual(targets, {"Notchscape", "NotchscapeDockWidget", "NotchscapeHelper"})
        self.assertEqual(objects["P"]["projectDirPath"], str(self.project.parent.resolve()))
        self.assertFalse(any(obj.get("path") == "NotchscapeFaceVault.xpc" for obj in objects.values()))
        self.assertFalse(any(obj.get("path") == "Notchscape/Resources/FaceModels" for obj in objects.values()))
        self.assertTrue(any(obj.get("path") == "Notchscape/Resources/FacePreviewNotices.txt" for obj in objects.values()))
        self.assertIn("HELPEREMBED", objects["EMBED"]["files"])
        self.assertIn("NOTICEBUILD", objects["RESOURCES"]["files"])
        self.assertEqual(plistlib.loads(info_path.read_bytes())["NotchFaceUnlockEnabled"], False)
        self.assertEqual(objects["MAINDEBUG"]["buildSettings"]["INFOPLIST_FILE"], str(info_path))
        self.assertEqual(objects["MAINRELEASE"]["buildSettings"]["INFOPLIST_FILE"], str(info_path))
        self.assertNotIn("FACECONFIG", objects)
        self.assertTrue(self.project.joinpath("project.pbxproj").is_file())

    def test_generator_fails_closed_when_face_target_is_missing(self):
        project = synthetic_project()
        project["objects"].pop("FACE")
        with (self.project / "project.pbxproj").open("wb") as output:
            plistlib.dump(project, output)
        with self.assertRaisesRegex(ValueError, "exactly one main target"):
            GENERATOR.write_public_project(self.project, self.info, self.output)

    def test_public_bundle_gate_rejects_enabled_face_or_embedded_profile(self):
        with self.assertRaisesRegex(ValueError, "explicitly disable Face Unlock"):
            SIGNING.validate_public_bundle_contents(self.output, {"NotchFaceUnlockEnabled": True,
                                                                   "NotchAccountsEnabled": False})
        self.output.mkdir()
        (self.output / "local.provisionprofile").touch()
        with self.assertRaisesRegex(ValueError, "must not contain a provisioning profile"):
            SIGNING.validate_public_bundle_contents(self.output, {"NotchFaceUnlockEnabled": False,
                                                                   "NotchAccountsEnabled": False})


if __name__ == "__main__":
    unittest.main()
