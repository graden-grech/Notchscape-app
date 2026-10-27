#!/usr/bin/env python3
"""Prevent the unfinished account feature from entering a public app build."""

import argparse
import plistlib
import sys
from pathlib import Path


def check_public_features(info: dict) -> None:
    if info.get("NotchAccountsEnabled") is not False:
        raise ValueError("Accounts are on release hold: NotchAccountsEnabled must explicitly be false.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("info_plist", type=Path)
    args = parser.parse_args()
    try:
        with args.info_plist.open("rb") as source:
            check_public_features(plistlib.load(source))
    except (OSError, ValueError, TypeError, plistlib.InvalidFileException) as error:
        print(f"FAIL: public feature gate: {error}", file=sys.stderr)
        return 1
    print("PASS: accounts excluded from public-facing app features")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
