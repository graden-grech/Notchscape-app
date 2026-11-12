import datetime as dt
import hashlib
import importlib.util
import os
import pathlib
import plistlib
import subprocess
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent


def load(name, path):
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module


gate=load("broker_signing",ROOT/".github/scripts/face_vault_signing.py")
archive=load("distribution_archive",ROOT/".github/scripts/verify_distribution_archive.py")


class FaceVaultSigningTests(unittest.TestCase):
    def setUp(self):
        self.now=dt.datetime(2026,10,30,tzinfo=dt.timezone.utc)
        self.certificate=b"synthetic certificate fixture, never a real signing identity"
        self.previous_digest=gate.CERT_SHA256
        gate.CERT_SHA256=hashlib.sha256(self.certificate).hexdigest()
        self.profile={"TeamIdentifier":[gate.TEAM],"ApplicationIdentifierPrefix":[gate.TEAM],"Platform":["OSX"],
            "Entitlements":{"com.apple.application-identifier":gate.APP_ID,"com.apple.developer.team-identifier":gate.TEAM,
                            "keychain-access-groups":[gate.TEAM+".*"]},"ProvisionedDevices":["SYNTHETIC-MAC"],
            "CreationDate":self.now-dt.timedelta(hours=1),"ExpirationDate":self.now+dt.timedelta(days=6),
            "DeveloperCertificates":[self.certificate],"UUID":"synthetic-profile-id"}

    def tearDown(self):
        gate.CERT_SHA256=self.previous_digest

    def test_valid_local_profile(self):
        self.assertEqual(gate.validate_profile(self.profile,self.now,{"SYNTHETIC-MAC"}),"2026-11-05T00:00:00Z")

    def test_profile_refusals(self):
        mutations={"TeamIdentifier":["FOREIGN"],"ApplicationIdentifierPrefix":["FOREIGN"],"Platform":["iOS"],
                   "ProvisionsAllDevices":True,"ProvisionedDevices":[],"DeveloperCertificates":[b"another cert"],
                   "ExpirationDate":self.now,"CreationDate":self.now+dt.timedelta(seconds=1),"UUID":""}
        for key,value in mutations.items():
            with self.subTest(key=key):
                profile=dict(self.profile);profile[key]=value
                with self.assertRaises(ValueError):gate.validate_profile(profile,self.now,{"SYNTHETIC-MAC"})
        for devices in [["ANOTHER-MAC"],["SYNTHETIC-MAC","ANOTHER-MAC"]]:
            profile=dict(self.profile);profile["ProvisionedDevices"]=devices
            with self.assertRaises(ValueError):gate.validate_profile(profile,self.now,{"SYNTHETIC-MAC"})
        profile=dict(self.profile);profile["ExpirationDate"]=self.now+dt.timedelta(days=365)
        with self.assertRaises(ValueError):gate.validate_profile(profile,self.now,{"SYNTHETIC-MAC"})

    def test_private_group_and_privileges(self):
        ent={"com.apple.application-identifier":gate.APP_ID,"com.apple.developer.team-identifier":gate.TEAM,
             "keychain-access-groups":[gate.APP_ID],"com.apple.security.app-sandbox":True}
        gate.validate_entitlements(ent)
        for key,value in {"keychain-access-groups":[gate.TEAM+".*"],"com.apple.security.app-sandbox":False,
                          "com.apple.security.get-task-allow":True,"com.apple.security.cs.disable-library-validation":True}.items():
            invalid=dict(ent);invalid[key]=value
            with self.assertRaises(ValueError):gate.validate_entitlements(invalid)
        for key,value in {"com.apple.application-identifier":gate.TEAM+".wrong","com.apple.developer.team-identifier":"FOREIGN",
                          "keychain-access-groups":["FOREIGN.*"]}.items():
            profile=dict(self.profile);profile["Entitlements"]=dict(profile["Entitlements"]);profile["Entitlements"][key]=value
            with self.assertRaises(ValueError):gate.validate_profile(profile,self.now,{"SYNTHETIC-MAC"})

    def test_broker_requires_explicit_caller_session_configuration(self):
        info={"CFBundleIdentifier":gate.BROKER,
              "XPCService":{"ServiceType":"Application","JoinExistingSession":True}}
        gate.validate_service_configuration(info)
        for service in [None,{},[],{"ServiceType":"Application"},
                        {"ServiceType":"User","JoinExistingSession":True},
                        {"ServiceType":"Application","JoinExistingSession":False},
                        {"ServiceType":"Application","JoinExistingSession":1},
                        {"ServiceType":"Application","JoinExistingSession":"true"}]:
            with self.subTest(service=service):
                with self.assertRaises(ValueError):
                    gate.validate_service_configuration({"CFBundleIdentifier":gate.BROKER,"XPCService":service})
        with self.assertRaises(ValueError):
            gate.validate_service_configuration({**info,"CFBundleIdentifier":"other.helper"})

    def test_preserve_all_old_helpers_only_allow_named_addition(self):
        old={gate.OLD_HELPER:(None,"old exact DR"),"org.sparkle-project.Installer":(None,"Sparkle exact DR")}
        candidate={**old,gate.BROKER:(None,"new exact broker DR")}
        gate.compare_inventories(candidate,old)
        for invalid in [{**candidate,"unexpected.helper":(None,"other")},
                        {k:v for k,v in candidate.items() if k!="org.sparkle-project.Installer"},
                        {**candidate,"org.sparkle-project.Installer":(None,"changed DR")}]:
            with self.assertRaises(ValueError):gate.compare_inventories(invalid,old)

    def test_explicit_and_implicit_existing_designated_requirements(self):
        self.assertEqual(gate.parse_requirement_output('Executable=/private/example\ndesignated => identifier "example"\n'),'identifier "example"')
        self.assertEqual(gate.parse_requirement_output('# designated => cdhash H"1234" or cdhash H"5678"\n'),'cdhash H"1234" or cdhash H"5678"')
        with self.assertRaises(ValueError):gate.parse_requirement_output('Executable=missing-requirement\n')

    def test_device_bound_broker_cannot_enter_public_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            path=pathlib.Path(directory)/"synthetic.zip"
            for helper in ["NotchscapeFaceVault.xpc","Renamed.xpc"]:
                with zipfile.ZipFile(path,"w") as output:
                    output.writestr("Notchscape.app/Contents/XPCServices/"+helper+"/Contents/Info.plist",
                                    plistlib.dumps({"CFBundleIdentifier":gate.BROKER,"FaceVaultLocalDevelopmentOnly":True}))
                with self.assertRaisesRegex(ValueError,"local|development"):archive.validate_archive(path)
            app=pathlib.Path(directory)/"Notchscape.app"
            info=app/"Contents/XPCServices/Renamed.xpc/Contents/Info.plist";info.parent.mkdir(parents=True)
            info.write_bytes(plistlib.dumps({"CFBundleIdentifier":gate.BROKER}))
            with self.assertRaisesRegex(ValueError,"local-only"):gate.public_release_app(app)

    @unittest.skipUnless(os.environ.get("FACE_VAULT_TEST_PROFILE"), "local authenticated-Xcode profile fixture not supplied")
    def test_actual_apple_cms_signature_and_tampered_content(self):
        path=pathlib.Path(os.environ["FACE_VAULT_TEST_PROFILE"])
        self.assertEqual(gate.decode_profile(path)["Entitlements"]["com.apple.application-identifier"],gate.APP_ID)
        encoded=bytearray(path.read_bytes());index=encoded.find(b"Mac Team Provisioning Profile:")
        self.assertGreaterEqual(index,0)
        encoded[index]=ord("N") # harmless display-name change, plist still valid, signature invalid
        with tempfile.TemporaryDirectory() as directory:
            tampered=pathlib.Path(directory)/"bad.provisionprofile";tampered.write_bytes(encoded)
            with self.assertRaises(ValueError):gate.decode_profile(tampered)

    @unittest.skipUnless(os.environ.get("FACE_VAULT_TEST_CANDIDATE") and os.environ.get("FACE_VAULT_TEST_PREVIOUS"),
                         "signed local build/trusted baseline fixtures not supplied")
    def test_bash32_two_argument_gate_and_empty_optional_profile(self):
        arguments=["/bin/bash",str(ROOT/".github/scripts/verify_custom_app_identity.sh"),
                   os.environ["FACE_VAULT_TEST_CANDIDATE"],os.environ["FACE_VAULT_TEST_PREVIOUS"]]
        for suffix in [[],[""]]:
            with self.subTest(profile="omitted" if not suffix else "explicitly empty"):
                result=subprocess.run(arguments+suffix,capture_output=True,text=True,timeout=60)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                self.assertIn("all existing nested helper requirements preserved",result.stdout)
                self.assertIn("exact new Face Vault signer/profile/private group validated",result.stdout)
                self.assertIn("update key preserved",result.stdout)


if __name__=="__main__":unittest.main()
