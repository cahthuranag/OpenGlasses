#!/usr/bin/env python3
"""Transport built test products, never DerivedData, between matching CI runners."""
import argparse
import json
import os
from pathlib import Path
import subprocess


def capture(*args):
    return subprocess.check_output(args, text=True).strip()


def package(products, simulator, output):
    devices = json.loads(capture("xcrun", "simctl", "list", "devices", "available", "--json"))["devices"]
    matches = [(runtime, device) for runtime, rows in devices.items() for device in rows
               if device["udid"] == simulator]
    if len(matches) != 1:
        raise SystemExit("Build simulator not found")
    runtime, device = matches[0]
    manifest = dict(xcode=capture("xcodebuild", "-version"),
                    developer_dir=capture("xcode-select", "-p"),
                    runtime=runtime, device_type=device["deviceTypeIdentifier"])
    if os.environ.get("DEVELOPER_DIR"):
        manifest["developer_dir"] = os.environ["DEVELOPER_DIR"]
    runners = list(products.glob("OpenGlassesUITests_*.xctestrun"))
    if len(runners) != 1:
        raise SystemExit("Expected exactly one UI-test run file")
    (products / "audit-toolchain.json").write_text(json.dumps(manifest, indent=2))
    subprocess.run(["tar", "-czf", str(output.resolve()), "-C", str(products.parent), products.name], check=True)


def prepare(archive, directory):
    directory.mkdir(parents=True, exist_ok=False)
    subprocess.run(["tar", "-xzf", str(archive.resolve()), "-C", str(directory)], check=True)
    products = directory / "Products"
    manifest = json.loads((products / "audit-toolchain.json").read_text())
    os.environ["DEVELOPER_DIR"] = manifest["developer_dir"]
    if capture("xcodebuild", "-version") != manifest["xcode"]:
        raise SystemExit("Test runner Xcode differs from the build runner")
    runners = list(products.glob("OpenGlassesUITests_*.xctestrun"))
    if len(runners) != 1:
        raise SystemExit("Expected exactly one UI-test run file")
    udid = capture("xcrun", "simctl", "create", "Accessibility audit", manifest["device_type"], manifest["runtime"])
    subprocess.run(["xcrun", "simctl", "boot", udid], check=True)
    subprocess.run(["xcrun", "simctl", "bootstatus", udid, "-b"], check=True)
    subprocess.run(["xcrun", "simctl", "install", udid,
                    str(products / "Debug-iphonesimulator" / "OpenGlasses.app")], check=True)
    # These audits use seeded media and never record audio. Declare the ungranted
    # permission state up front so a microphone prompt cannot cover a Job screen.
    subprocess.run(["xcrun", "simctl", "privacy", udid, "revoke", "microphone", "com.openglasses.app"], check=True)
    values = dict(DEVELOPER_DIR=manifest["developer_dir"], AUDIT_SIMULATOR=udid,
                  AUDIT_XCTESTRUN=str(runners[0].resolve()))
    destination = os.environ.get("GITHUB_ENV")
    if destination:
        with open(destination, "a") as stream:
            for key, value in values.items():
                stream.write(f"{key}={value}\n")
    print(json.dumps(values))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    build = commands.add_parser("package")
    build.add_argument("--products", type=Path, required=True)
    build.add_argument("--simulator", required=True)
    build.add_argument("--output", type=Path, required=True)
    run = commands.add_parser("prepare")
    run.add_argument("--archive", type=Path, required=True)
    run.add_argument("--directory", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "package":
        package(args.products, args.simulator, args.output)
    else:
        prepare(args.archive, args.directory)


if __name__ == "__main__":
    main()
