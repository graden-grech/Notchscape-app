#!/usr/bin/env python3
"""Check a staged app is readable/runnable by other local Mac accounts."""
import argparse
import json
import os
from pathlib import Path
import stat


def validate_app(app):
    app = Path(app)
    if app.name != "Notchscape.app" or not app.is_dir() or app.is_symlink():
        raise ValueError("Expected the real Notchscape.app bundle")
    root = app.resolve()
    checked = 0
    for directory, dirs, files in os.walk(app, followlinks=False):
        for path in [Path(directory)] + [Path(directory) / name for name in dirs + files]:
            metadata = path.lstat()
            mode = stat.S_IMODE(metadata.st_mode)
            if stat.S_ISLNK(metadata.st_mode):
                try:
                    path.resolve(strict=True).relative_to(root)
                except (OSError, ValueError, RuntimeError):
                    raise ValueError("A bundled symlink escapes the app or is broken") from None
                continue
            if mode & stat.S_IWOTH:
                raise ValueError("World-writable app content is not a safe shared installation")
            if stat.S_ISDIR(metadata.st_mode):
                if mode & 0o005 != 0o005:
                    raise ValueError("A bundle directory is not readable/traversable by other users")
            elif stat.S_ISREG(metadata.st_mode):
                if not mode & stat.S_IROTH:
                    raise ValueError("A bundle resource is not readable by other users")
                if mode & stat.S_IXUSR and not mode & stat.S_IXOTH:
                    raise ValueError("An executable is restricted to its owner")
            else:
                raise ValueError("Unsupported special file in app bundle")
            checked += 1
    binary = app / "Contents/MacOS/Notchscape"
    if not binary.is_file() or not binary.stat().st_mode & stat.S_IXOTH:
        raise ValueError("The main app executable is not runnable by other local users")
    return {"sharedInstallPath": "/Applications/Notchscape.app", "checkedEntries": checked,
            "otherLocalUsersCanReadAndExecute": True,
            "note": "Filesystem access only; each account manages its own settings, permissions and login startup. Signing/notarization are separate."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(validate_app(args.app), indent=2))
    except (OSError, ValueError) as error:
        parser.exit(1, "FAIL: {}\n".format(error))


if __name__ == "__main__":
    main()
