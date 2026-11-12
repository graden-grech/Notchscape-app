#!/usr/bin/env python3
"""Read-only gates for the local, device-bound Face Vault development helper.

Never executes the helper, authenticates a user, or contacts a Keychain item.
The development profile stays in Xcode/private build outputs, never this repo.
"""
import argparse
import datetime as dt
import hashlib
import json
import pathlib
import plistlib
import subprocess
import sys
import tempfile

TEAM = "6H86CTRJCP"
BROKER = "com.graden-grech.Notchscape.FaceVault"
APP_ID = TEAM + "." + BROKER
SIGNER = "Apple Development: grechgraden@icloud.com (P45575RL23)"
CERT_SHA256 = "1de9eca9e1d7640177be9bdb79f3e7e52bade2278bc2cca35445d13a731f7a74"
MAIN = "theboringteam.boringnotch"
OLD_HELPER = MAIN + ".BoringNotchXPCHelper"
DOCK_WIDGET = "com.graden-grech.Notchscape.DockWidget"
DOCK_WIDGET_PATH = pathlib.Path("Contents/Helpers/NotchscapeDockWidget.app")
REQUIREMENT = (f'identifier "{BROKER}" and anchor apple generic and certificate leaf[subject.CN] = "{SIGNER}" '
               f'and certificate leaf[subject.OU] = "{TEAM}" and certificate 1[field.1.2.840.113635.100.6.2.1]')
DOCK_WIDGET_REQUIREMENT = REQUIREMENT.replace(f'identifier "{BROKER}"', f'identifier "{DOCK_WIDGET}"', 1)
MAIN_REQUIREMENT = REQUIREMENT.replace(f'identifier "{BROKER}"', f'identifier "{MAIN}"', 1)


def require(value, message):
    if not value:
        raise ValueError(message)


def command(args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    require(result.returncode == 0, "signing/profile command refused validation: " + pathlib.Path(args[0]).name)
    return result.stdout


def utc(value):
    return value.replace(tzinfo=dt.timezone.utc) if value.tzinfo is None else value.astimezone(dt.timezone.utc)


def validate_profile(profile, now, device_ids):
    """Pure profile authorization policy, tested using synthetic dictionaries."""
    require(profile.get("TeamIdentifier") == [TEAM], "wrong profile team")
    require(profile.get("ApplicationIdentifierPrefix") == [TEAM], "wrong profile prefix")
    require(profile.get("Platform") == ["OSX"], "profile is not macOS development")
    require(not profile.get("ProvisionsAllDevices"), "unrestricted/distribution profile is outside this local prototype")
    entitlements = profile.get("Entitlements", {})
    require(entitlements.get("com.apple.application-identifier") == APP_ID, "wrong profile AppID")
    require(entitlements.get("com.apple.developer.team-identifier") == TEAM, "wrong entitled profile team")
    groups = entitlements.get("keychain-access-groups", [])
    require(groups in ([APP_ID], [TEAM + ".*"]), "profile does not authorize the private group")
    devices = profile.get("ProvisionedDevices", [])
    require(isinstance(devices, list) and len(devices) == 1 and devices[0] in device_ids,
            "local development profile must name exactly this one Mac")
    created, expires = profile.get("CreationDate"), profile.get("ExpirationDate")
    require(isinstance(created, dt.datetime) and isinstance(expires, dt.datetime), "missing profile lifetime")
    require(utc(created) <= now < utc(expires), "profile is expired or not yet valid")
    require(dt.timedelta(0) < utc(expires) - utc(created) <= dt.timedelta(days=8), "expected a short free-development profile")
    certificates = profile.get("DeveloperCertificates", [])
    require(isinstance(certificates, list) and len(certificates) == 1 and
            hashlib.sha256(certificates[0]).hexdigest() == CERT_SHA256, "profile certificate differs from trusted signer")
    require(isinstance(profile.get("UUID"), str) and profile["UUID"], "missing profile UUID")
    return utc(expires).isoformat(timespec="seconds").replace("+00:00", "Z")


def validate_entitlements(entitlements):
    allowed = {"com.apple.application-identifier", "com.apple.developer.team-identifier",
               "keychain-access-groups", "com.apple.security.app-sandbox", "com.apple.security.get-task-allow"}
    require(set(entitlements) <= allowed, "broker has unexpected privileges")
    require(entitlements.get("com.apple.application-identifier") == APP_ID, "broker AppID is wrong")
    require(entitlements.get("com.apple.developer.team-identifier") == TEAM, "broker team is wrong")
    require(entitlements.get("keychain-access-groups") == [APP_ID], "broker needs exactly its own private group")
    require(entitlements.get("com.apple.security.app-sandbox") is True, "broker must be sandboxed")
    require(entitlements.get("com.apple.security.get-task-allow", False) is False, "broker must not permit debugger attachment")


def validate_service_configuration(info):
    require(info.get("CFBundleIdentifier") == BROKER, "wrong XPC service identifier")
    service = info.get("XPCService")
    require(isinstance(service, dict) and service.get("ServiceType") == "Application",
            "broker must be an app-private Application XPC service")
    require(service.get("JoinExistingSession") is True,
            "broker must join the calling application's audit/security session")


def current_device_ids():
    info = json.loads(command(["/usr/sbin/system_profiler", "SPHardwareDataType", "-json"]))
    ids = set()
    for hardware in info.get("SPHardwareDataType", []):
        for key in ("provisioning_UDID", "platform_UUID"):
            value = hardware.get(key)
            if isinstance(value, str) and value:
                ids.add(value)
    require(ids, "could not identify this Mac for the device-bound profile")
    return ids


def decode_profile(path):
    path = pathlib.Path(path)
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 1_000_000, "invalid profile file")
    # security(1) cms -D decodes even modified signed content. Use the public
    # CMSDecoder signature API plus SecTrust and a pinned Apple profile signer.
    verifier = pathlib.Path(__file__).with_name("verify_face_vault_profile.swift")
    return plistlib.loads(command(["/usr/bin/xcrun", "swift", str(verifier), str(path)]))


def select_profile(explicit=None):
    paths = [pathlib.Path(explicit)] if explicit else []
    if not paths:
        for directory in (pathlib.Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
                          pathlib.Path.home() / "Library/MobileDevice/Provisioning Profiles"):
            if directory.is_dir():
                paths.extend(directory.glob("*.provisionprofile"))
    now, ids = dt.datetime.now(dt.timezone.utc), current_device_ids()
    valid = []
    for path in paths:
        try:
            profile = decode_profile(path)
            expires = validate_profile(profile, now, ids)
            valid.append((expires, str(path), profile["UUID"]))
        except (ValueError, KeyError, plistlib.InvalidFileException):
            if explicit:
                raise
    require(valid, "no valid local Face Vault profile; renew ONLY the NotchscapeFaceVault target in Xcode")
    expires, path, identifier = max(valid)
    return path, identifier, expires


def signed_entitlements(bundle):
    return plistlib.loads(command(["/usr/bin/codesign", "-d", "--entitlements", ":-", str(bundle)]))


def parse_requirement_output(output):
    # Existing Sparkle components may have an implicit ad-hoc cdhash DR. The
    # leading comment marker is codesign's display convention, not permission to
    # omit that component from the before/after identity comparison.
    values = [line.removeprefix("# ").removeprefix("designated => ") for line in output.splitlines()
              if line.startswith(("designated => ", "# designated => "))]
    require(len(values) == 1 and values[0], "missing designated requirement")
    return values[0]


def requirement(bundle):
    result = subprocess.run(["/usr/bin/codesign", "-dr", "-", str(bundle)], capture_output=True, text=True)
    require(result.returncode == 0, "cannot read designated requirement")
    return parse_requirement_output(result.stderr + result.stdout)


def certificate_data(bundle):
    """Read the embedded public leaf certificate; never accesses a private key."""
    with tempfile.TemporaryDirectory(prefix="notchscape-dock-cert-") as directory:
        prefix = str(pathlib.Path(directory) / "leaf")
        command(["/usr/bin/codesign", "-d", "--extract-certificates=" + prefix, str(bundle)])
        return pathlib.Path(prefix + "0").read_bytes()


def dock_signing_identity(previous):
    """Pin only the new target to the trusted app's exact development identity."""
    previous = pathlib.Path(previous)
    info = plistlib.loads((previous / "Contents/Info.plist").read_bytes())
    require(info.get("CFBundleIdentifier") == MAIN, "Dock signer baseline is not the trusted main app")
    command(["/usr/bin/codesign", "--verify", "--strict", str(previous)])
    command(["/usr/bin/codesign", "-v", "-R", "=" + MAIN_REQUIREMENT, str(previous)])
    certificate = certificate_data(previous)
    require(hashlib.sha256(certificate).hexdigest() == CERT_SHA256,
            "Dock signer baseline certificate differs from the trusted signer")
    # Xcode/codesign accepts this exact certificate hash as an identity. The
    # custom build setting is used only by the new Dock target.
    return hashlib.sha1(certificate).hexdigest().upper()


def validate_dock_widget_configuration(info, main_info):
    """Pure metadata boundary for the ordinary, permission-free child app."""
    require(main_info.get("CFBundleIdentifier") == MAIN, "Dock widget parent identity changed")
    require(info.get("CFBundleIdentifier") == DOCK_WIDGET, "wrong Dock widget identifier")
    require(info.get("CFBundleExecutable") == "NotchscapeDockWidget", "wrong Dock widget executable")
    require(info.get("CFBundlePackageType") == "APPL", "Dock widget must be a normal app")
    require(info.get("CFBundleName") == info.get("CFBundleDisplayName") == "Notchscape Dock Widget",
            "Dock widget branding changed")
    require(info.get("LSUIElement") is False and info.get("LSBackgroundOnly", False) is False,
            "Dock widget must retain its regular Dock app identity")
    require(info.get("LSMultipleInstancesProhibited", False) is False,
            "Dock widget must permit independent local-user instances")
    require(info.get("LSMinimumSystemVersion") == "15.0", "Dock widget must support the macOS15 baseline")
    for key in ("CFBundleVersion", "CFBundleShortVersionString"):
        require(isinstance(info.get(key), str) and info[key] and info[key] == main_info.get(key),
                "Dock widget/main version mismatch")
    require(not any(key.startswith("NS") and key.endswith("UsageDescription") for key in info),
            "Dock widget has an unexpected protected-resource permission declaration")
    require(not {"XPCService", "MachServices", "NSExtension", "CFBundleURLTypes", "LSEnvironment"} & set(info),
            "Dock widget has an unexpected service or launch surface")


def dock_widget_path(app):
    app = pathlib.Path(app)
    host = app / DOCK_WIDGET_PATH
    for directory in (app, app / "Contents", app / "Contents/Helpers", host,
                      host / "Contents", host / "Contents/MacOS"):
        require(directory.is_dir() and not directory.is_symlink(), "Dock widget is missing or has an indirect bundle path")
    for relative in ("Contents/Info.plist", "Contents/MacOS/NotchscapeDockWidget"):
        path = host / relative
        require(path.is_file() and not path.is_symlink(), "Dock widget metadata/executable is missing or indirect")
    require((host / "Contents/MacOS/NotchscapeDockWidget").stat().st_mode & 0o111,
            "Dock widget executable is not runnable")
    require(not any(path.is_symlink() for path in host.rglob("*")), "Dock widget contains an indirect bundled file")
    require(not any(path.suffix in (".provisionprofile", ".mobileprovision") for path in host.rglob("*")),
            "Dock widget must not contain a provisioning profile")
    return host


def verify_dock_widget_app(app, previous):
    """Validate the new child even when the trusted older app has no Dock host."""
    app, previous = pathlib.Path(app), pathlib.Path(previous)
    host = dock_widget_path(app)
    info = plistlib.loads((host / "Contents/Info.plist").read_bytes())
    main_info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    validate_dock_widget_configuration(info, main_info)
    command(["/usr/bin/codesign", "--verify", "--strict", str(host)])
    command(["/usr/bin/codesign", "-v", "-R", "=" + DOCK_WIDGET_REQUIREMENT, str(host)])
    raw_entitlements = command(["/usr/bin/codesign", "-d", "--entitlements", ":-", str(host)])
    entitlements = plistlib.loads(raw_entitlements) if raw_entitlements.strip() else {}
    require(isinstance(entitlements, dict) and not entitlements, "Dock widget must not have signed entitlements")
    for bundle in (host, app, previous):
        require(hashlib.sha256(certificate_data(bundle)).hexdigest() == CERT_SHA256,
                "Dock widget/main certificate differs from the trusted signer")
    details = subprocess.run(["/usr/bin/codesign", "-dv", "--verbose=4", str(host)], capture_output=True, text=True)
    lines = (details.stderr + details.stdout).splitlines()
    require(details.returncode == 0 and "(runtime)" in details.stderr and
            "TeamIdentifier=" + TEAM in lines and "Identifier=" + DOCK_WIDGET in lines,
            "Dock widget signing team, identifier or hardened runtime is wrong")
    old_host = previous / DOCK_WIDGET_PATH
    if old_host.exists():
        require(requirement(host) == requirement(old_host), "Dock widget designated requirement changed")
    print("PASS: exact Dock widget path/signer/runtime/version validated; no entitlements or provisioning profile")


def helper_inventory(app):
    result = {}
    for root, directories, _ in __import__("os").walk(pathlib.Path(app) / "Contents", followlinks=False):
        directories[:] = [name for name in directories if not (pathlib.Path(root) / name).is_symlink()]
        bundle = pathlib.Path(root)
        if bundle.suffix not in (".app", ".xpc"):
            continue
        info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
        identifier = info.get("CFBundleIdentifier")
        require(isinstance(identifier, str) and identifier not in result, "duplicate/unknown nested helper identifier")
        result[identifier] = (bundle, requirement(bundle))
    return result


def compare_inventories(candidate, previous):
    require(set(candidate) - set(previous) <= {BROKER, DOCK_WIDGET}, "unapproved new nested helper")
    require(set(previous) <= set(candidate), "an existing nested helper disappeared")
    require(OLD_HELPER in candidate and BROKER in candidate, "required helper/broker is missing")
    for identifier, (_, old_requirement) in previous.items():
        require(candidate[identifier][1] == old_requirement, "designated requirement changed for existing helper " + identifier)


def verify_app(app, previous, selected_profile=None, require_dock_widget=False):
    app, previous = pathlib.Path(app), pathlib.Path(previous)
    candidate, baseline = helper_inventory(app), helper_inventory(previous)
    compare_inventories(candidate, baseline)
    if require_dock_widget or DOCK_WIDGET in candidate:
        verify_dock_widget_app(app, previous)
    broker = candidate[BROKER][0]
    require(broker == app / "Contents/XPCServices/NotchscapeFaceVault.xpc", "broker is not the expected app-private service")
    command(["/usr/bin/codesign", "--verify", "--strict", str(broker)])
    command(["/usr/bin/codesign", "-v", "-R", "=" + REQUIREMENT, str(broker)])
    validate_entitlements(signed_entitlements(broker))
    main_entitlements = signed_entitlements(app)
    require(not {"com.apple.application-identifier", "com.apple.developer.team-identifier", "keychain-access-groups"} & set(main_entitlements),
            "unsupported DP entitlement returned to inherited main identifier")
    embedded = broker / "Contents/embedded.provisionprofile"
    profile = decode_profile(embedded)
    expiration = validate_profile(profile, dt.datetime.now(dt.timezone.utc), current_device_ids())
    if selected_profile:
        require(embedded.read_bytes() == pathlib.Path(selected_profile).read_bytes(), "embedded profile differs from selected validated profile")
    info = plistlib.loads((broker / "Contents/Info.plist").read_bytes())
    require(info.get("FaceVaultProfileExpiration") == expiration, "signed runtime expiry stamp differs from profile")
    require(info.get("FaceVaultLocalDevelopmentOnly") is True, "broker local-only scope marker is missing")
    validate_service_configuration(info)
    main_info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    old_helper_info = plistlib.loads((candidate[OLD_HELPER][0] / "Contents/Info.plist").read_bytes())
    for key in ("CFBundleVersion", "CFBundleShortVersionString"):
        require(info.get(key) == main_info.get(key) == old_helper_info.get(key), "app/helper/broker version mismatch")
    with tempfile.TemporaryDirectory(prefix="notchscape-code-cert-") as directory:
        digests = []
        for index, bundle in enumerate((broker, previous)):
            prefix = str(pathlib.Path(directory) / str(index))
            command(["/usr/bin/codesign", "-d", "--extract-certificates=" + prefix, str(bundle)])
            digests.append(hashlib.sha256(pathlib.Path(prefix + "0").read_bytes()).hexdigest())
        require(digests == [CERT_SHA256, CERT_SHA256], "actual broker certificate differs from trusted app/profile")
    details = subprocess.run(["/usr/bin/codesign", "-dv", "--verbose=4", str(broker)], capture_output=True, text=True)
    require(details.returncode == 0 and "(runtime)" in details.stderr, "broker hardened runtime is missing")
    print("PASS: all existing nested helper requirements preserved; exact new Face Vault signer/profile/private group validated (local one-Mac profile, expires " + expiration + ")")


def validate_public_bundle_contents(app, info):
    """Pure public-release boundary; local Face Unlock stays development-only."""
    app = pathlib.Path(app)
    require(info.get("NotchFaceUnlockEnabled") is False,
            "public build must explicitly disable Face Unlock")
    require(info.get("NotchAccountsEnabled") is False,
            "accounts are on release hold and must remain disabled")
    require(not any(path.suffix in (".provisionprofile", ".mobileprovision") for path in app.rglob("*")),
            "public app must not contain a provisioning profile")
    require(not any(path.name == "FaceModels" for path in app.rglob("FaceModels")),
            "public app must not bundle local Face Unlock model weights")
    for bundle in app.rglob("*.xpc"):
        info_path = bundle / "Contents/Info.plist"
        require(info_path.is_file(), "nested XPC service is missing its Info.plist")
        service_info = plistlib.loads(info_path.read_bytes())
        require(service_info.get("CFBundleIdentifier") != BROKER and
                service_info.get("FaceVaultLocalDevelopmentOnly") is not True,
                "Face Vault development helper/profile is local-only and cannot enter a public release archive")


def verify_public_app(app, previous, require_dock_widget=False):
    """Verify a public app against a trusted public baseline with no local broker."""
    app, previous = pathlib.Path(app), pathlib.Path(previous)
    validate_public_bundle_contents(app, plistlib.loads((app / "Contents/Info.plist").read_bytes()))
    candidate, baseline = helper_inventory(app), helper_inventory(previous)
    require(set(candidate) - set(baseline) <= {DOCK_WIDGET}, "unapproved new nested helper in public build")
    require(set(baseline) <= set(candidate), "an existing trusted nested helper disappeared")
    require(OLD_HELPER in candidate and OLD_HELPER in baseline,
            "original trusted helper is missing from public build or baseline")
    require(BROKER not in candidate, "local Face Vault broker is forbidden in a public build")
    for identifier, (_, old_requirement) in baseline.items():
        require(candidate[identifier][1] == old_requirement,
                "designated requirement changed for existing helper " + identifier)
    if require_dock_widget or DOCK_WIDGET in candidate:
        verify_dock_widget_app(app, previous)
    print("PASS: public build excludes Face Vault, profiles and model weights; trusted helper and Dock signatures validated")


def public_release_app(app):
    # This helper is deliberately a one-device, seven-day development prototype.
    # Do not let the local build gate turn into permission to package its profile
    # (which contains device metadata) for a general customer download.
    app = pathlib.Path(app)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    validate_public_bundle_contents(app, info)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--select-profile", action="store_true")
    parser.add_argument("--profile")
    parser.add_argument("--verify-app", nargs=2, metavar=("CANDIDATE", "PREVIOUS"))
    parser.add_argument("--verify-public-app", nargs=2, metavar=("CANDIDATE", "PREVIOUS"))
    parser.add_argument("--public-release-app")
    parser.add_argument("--dock-signing-identity", metavar="PREVIOUS")
    parser.add_argument("--require-dock-widget", action="store_true")
    args = parser.parse_args()
    if args.select_profile:
        print("\t".join(select_profile(args.profile)))
    elif args.verify_public_app:
        verify_public_app(*args.verify_public_app, require_dock_widget=args.require_dock_widget)
    elif args.verify_app:
        verify_app(*args.verify_app, selected_profile=args.profile, require_dock_widget=args.require_dock_widget)
    elif args.public_release_app:
        public_release_app(args.public_release_app)
    elif args.dock_signing_identity:
        print(dock_signing_identity(args.dock_signing_identity))
    else:
        parser.error("choose --select-profile or --verify-app")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, plistlib.InvalidFileException) as error:
        print("FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
