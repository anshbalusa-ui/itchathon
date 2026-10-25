#!/usr/bin/env python3
"""Local Xcode verification; no network services, signing, or hardware claims."""

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ASSET = "FitCheckGeometricVest.fitmesh"
DIGEST = "ecc2df7e57f5a12ac89f4bd16bb51d101718780ee609a72f41c8ff1b653f7f30"
PRIVACY = {
    "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"],
    "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
    "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
}
MARKERS = (
    "CatalogPreviewAssociation", "CatalogIllustrativePreview", "RendererPresentation",
    "catalog.preview.open", "renderer.product-context", "View illustrative 3D preview",
    "RendererLabView", "RendererSceneSession", "RendererProceduralAssets", "renderer.scene",
    "internal.open-renderer", "fitcheck.r0.metal.v1", "rendererVertex", "rendererFragment",
    "CatalogRootView", "AvatarScannerModel", "local-synthetic-fixture",
    "RendererBundledAssetLoader", "RendererBundledAssetDescriptor", "RendererLoadedGarment",
    "RendererMeshPackage", "RendererGarmentLoading", "fitcheck.bundled-geometric-vest",
    "FitCheckGeometricVest", "FitCheckDevelopmentAssets", "renderer.asset.bundled",
    "renderer.asset.invalid", "RendererGeometrySource", "Geometric Vest Concept",
    "geometric-vest-navy-small", "geometric-vest-navy-medium",
    "InternalDevelopmentHub", "AvatarPilotRootView", "AvatarPilotModel",
    "SyntheticCatalog", "OfflineCatalogRepository", "avatar-pilot-root",
    "internal.open-avatar", "internal.open-catalog", "-fitcheck-avatar-internal",
    "-fitcheck-catalog-internal", "-fitcheck-integrated-internal",
    "AvatarGeometryLabView", "AvatarGeometryLabModel", "SyntheticGeometryGenerator",
    "GeometryKernel", "GeometryResult", "GeometryRendererAdapter", "GeometryViewport",
    "GeometryFixtureID", "internal.open-geometry", "geometry.scene",
    "Synthetic surface A", "Synthetic surface B",
    "SyntheticArtifactCodec", "SyntheticArtifactRepository", "VerifiedSyntheticArtifact",
    "SyntheticArtifactLabStorage", "FitCheckSyntheticGeometryS2B", "reviewed-synthetic.geometry-artifact",
    "geometry.artifact.save", "geometry.artifact.load", "geometry.artifact.delete", "geometry.artifact.loaded",
    "-fitcheck-synthetic-artifact-test-namespace", "-fitcheck-synthetic-artifact-test-seed",
    "SpatialReplayLabView", "SpatialReplayLabModel", "SyntheticDepthReplayFactory",
    "ReviewedSyntheticReplay", "ReplayCameraMath", "ReplaySpatialMapper",
    "ReplayReconstructionEngine", "ReplayGeometryResult", "SyntheticReplayReconstructor",
    "internal.open-replay", "replay.scene", "Simulated column A", "Simulated column B",
)
RELEASE_SELECTORS = (
    "FitCheckTests/AvatarFeatureIsolationTests",
    "FitCheckTests/CatalogIsolationTests",
    "FitCheckTests/InternalDevelopmentRouteTests",
    "FitCheckTests/IntegrationPrivacyManifestTests",
    "FitCheckTests/RendererDevelopmentResourceIsolationTests",
    "FitCheckUITests/AvatarPilotUITests",
    "FitCheckUITests/CatalogUITests/testNormalLaunchAndReleaseOptInRemainIsolated",
    "FitCheckUITests/IntegrationUITests/testInternalRouteFlagsRemainLegacyInRelease",
    "FitCheckUITests/RendererUITests/testRendererLabRemainsUnavailableFromProductionLaunches",
    "FitCheckUITests/AvatarGeometryUITests/testGeometryLabIsAbsentFromProductionLaunches",
    "FitCheckUITests/AvatarGeometryUITests/testArtifactPersistenceIsAbsentFromProductionLaunches",
    "FitCheckUITests/SpatialReplayUITests/testSyntheticReplayIsAbsentFromEveryProductionLaunch",
)
MACHO_MAGICS = {bytes.fromhex(value) for value in (
    "cffaedfe", "cefaedfe", "feedfacf", "feedface", "cafebabe", "bebafeca", "cafebabf", "bfbafeca",
)}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def source_digest():
    digest = hashlib.sha256()
    paths = [ROOT / "project.yml", Path(__file__).resolve()]
    for directory in ("Sources", "Tests", "UITests", "DevelopmentAssets"):
        paths.extend(path for path in (ROOT / directory).rglob("*") if path.is_file())
    for path in sorted(paths):
        digest.update(str(path.relative_to(ROOT)).encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
    return digest.hexdigest()


def development_asset(app):
    path = app / "FitCheckDevelopmentAssets" / ASSET
    require(path.is_file() and not path.is_symlink(), f"Missing/nonregular development fixture: {path}")
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    require(actual == DIGEST, f"Development fixture digest mismatch: {path}")
    return actual


def inspect_bundles(derived):
    source_hash = hashlib.sha256((ROOT / "DevelopmentAssets" / ASSET).read_bytes()).hexdigest()
    require(source_hash == DIGEST, "Reviewed source fixture digest changed")
    apps = {
        "debug": derived / "DebugDerived/Build/Products/Debug-iphonesimulator/FitCheck.app",
        "iPhone": derived / "iPhoneDerived/Build/Products/Debug-iphoneos/FitCheck.app",
        "release": derived / "ReleaseDerived/Build/Products/Release-iphonesimulator/FitCheck.app",
        "releaseTests": derived / "ReleaseTestDerived/Build/Products/Release-iphonesimulator/FitCheck.app",
    }
    result = {"sourceAssetSHA256": source_hash, "bundles": {}}
    for name, app in apps.items():
        require(app.is_dir(), f"Missing built app: {app}")
        with (app / "PrivacyInfo.xcprivacy").open("rb") as stream:
            manifest = plistlib.load(stream)
        entries = manifest.get("NSPrivacyAccessedAPITypes", [])
        declarations = {entry["NSPrivacyAccessedAPIType"]: entry["NSPrivacyAccessedAPITypeReasons"] for entry in entries}
        require(len(entries) == len(PRIVACY) and declarations == PRIVACY, f"Incorrect privacy reasons: {app}")
        require(manifest.get("NSPrivacyTracking") is False, f"Tracking declaration changed: {app}")
        require(manifest.get("NSPrivacyCollectedDataTypes") == [], f"Collection declaration changed: {app}")
        bundle = {"path": str(app), "privacy": manifest}
        artifacts = [str(path.relative_to(app)) for path in app.rglob("*")
                     if path.suffix.lower() in (".geometry-artifact", ".stage")
                     or path.name == ".repository.lock" or path.name.startswith("FitCheckSyntheticGeometryS2B")]
        require(not artifacts, f"Runtime synthetic storage was packaged into {name}: {artifacts}")
        bundle["syntheticArtifactResources"] = artifacts
        replay_resources = [str(path.relative_to(app)) for path in app.rglob("*")
                            if path.suffix.lower() in (".lidarreplay", ".depth-replay")
                            or path.name == "SpatialReplayFixtures"]
        require(not replay_resources, f"Synthetic replay resources packaged into {name}: {replay_resources}")
        bundle["syntheticReplayResources"] = replay_resources
        if name in ("debug", "iPhone"):
            bundle["assetSHA256"] = development_asset(app)
        else:
            leaks = [str(path.relative_to(app)) for path in app.rglob("*")
                     if path.suffix.lower() == ".fitmesh" or path.name == "FitCheckDevelopmentAssets"]
            require(not leaks, f"Development resources leaked into {name}: {leaks}")
            bundle["developmentResourceLeaks"] = leaks
        result["bundles"][name] = bundle
    for name in ("debug", "release"):
        app = apps[name]
        if name == "debug":
            with (app / "Info.plist").open("rb") as stream:
                executable = plistlib.load(stream)["CFBundleExecutable"]
            candidates = [app / executable, app / (executable + ".debug.dylib")]
        else:
            candidates = [path for path in app.rglob("*") if path.is_file()]
        binaries = []
        found = {marker: False for marker in MARKERS}
        for path in candidates:
            if not path.is_file():
                continue
            with path.open("rb") as stream:
                if stream.read(4) not in MACHO_MAGICS:
                    continue
                stream.seek(0)
                data = stream.read()
            binaries.append(str(path.relative_to(app)))
            for marker in MARKERS:
                found[marker] |= marker.encode() in data
        require(binaries, f"No Mach-O inspected in {name}")
        if name == "debug":
            require(all(found.values()), f"Missing Debug positive-control markers: {[key for key, value in found.items() if not value]}")
        else:
            require(not any(found.values()), f"Development binary markers leaked: {[key for key, value in found.items() if value]}")
        result["bundles"][name]["binariesInspected"] = binaries
        result["bundles"][name]["developmentMarkers"] = found
    return result


class Verification:
    def __init__(self, output):
        self.output = output

    def command(self, name, arguments, json_output=False):
        print(f"{name}: {self.output / (name + '.log')}", flush=True)
        with (self.output / (name + ".log")).open("wb") as log:
            if json_output:
                completed = subprocess.run(arguments, cwd=ROOT, stdout=subprocess.PIPE, stderr=log, check=True)
                (self.output / (name + ".json")).write_bytes(completed.stdout)
                return json.loads(completed.stdout)
            subprocess.run(arguments, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)

    def test(self, name, arguments, selectors=()):
        try:
            self.command(name, arguments)
        except subprocess.CalledProcessError:
            if (self.output / (name + ".xcresult")).is_dir():
                self.results(name, selectors)
            raise
        return self.results(name, selectors)

    def results(self, name, selectors=()):
        bundle = str(self.output / (name + ".xcresult"))
        # Sequential extraction avoids the installed xcresulttool SQLite-cache race.
        summary = self.command(name + "-summary", ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", bundle, "--compact"], True)
        tree = self.command(name + "-tests", ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", bundle, "--compact"], True)
        require(summary["result"] == "Passed" and summary["failedTests"] == 0
                and summary["skippedTests"] == 0 and summary["expectedFailures"] == 0,
                f"Failed, skipped, or expected-failure tests in {bundle}")
        cases = []

        def visit(node):
            if node.get("nodeType") == "Test Case":
                cases.append(node)
            for child in node.get("children", []):
                visit(child)

        for node in tree["testNodes"]:
            visit(node)
        require(len(cases) == summary["totalTestCount"] and cases, "xcresult case/summary count mismatch")
        require(all(case["result"] == "Passed" for case in cases), "A test case did not pass")
        identifiers = [case["nodeIdentifierURL"].removeprefix("test://com.apple.xcode/FitCheck/") for case in cases]
        for selector in selectors:
            require(any(item == selector or item.startswith(selector + "/") for item in identifiers),
                    f"Requested selector did not execute: {selector}")
        counts = {"unit": sum(item.startswith("FitCheckTests/") for item in identifiers),
                  "UI": sum(item.startswith("FitCheckUITests/") for item in identifiers)}
        require(counts["unit"] + counts["UI"] == len(cases) and all(counts.values()), "Unit/UI target coverage missing")
        return {"summary": summary, "counts": counts, "executedSelectors": list(selectors)}

    def run(self, simulator):
        before = source_digest()
        self.command("xcodegen", ["xcodegen", "generate"])
        common = ["xcodebuild", "-project", "FitCheck.xcodeproj", "-scheme", "FitCheck"]
        destination = ["-destination", "platform=iOS Simulator,id=" + simulator]
        debug = self.test("DebugTests", common + ["-configuration", "Debug"] + destination + [
            "-derivedDataPath", str(self.output / "DebugDerived"), "-resultBundlePath", str(self.output / "DebugTests.xcresult"),
            "-parallel-testing-enabled", "NO", "CODE_SIGNING_ALLOWED=NO", "clean", "build", "test", "-quiet"])
        self.command("iPhoneBuild", common + ["-configuration", "Debug", "-sdk", "iphoneos", "-destination", "generic/platform=iOS",
            "-derivedDataPath", str(self.output / "iPhoneDerived"), "-resultBundlePath", str(self.output / "iPhoneBuild.xcresult"),
            "CODE_SIGNING_ALLOWED=NO", "build", "-quiet"])
        self.command("ReleaseBuild", common + ["-configuration", "Release", "-sdk", "iphonesimulator", "-destination", "generic/platform=iOS Simulator",
            "-derivedDataPath", str(self.output / "ReleaseDerived"), "-resultBundlePath", str(self.output / "ReleaseBuild.xcresult"),
            "CODE_SIGNING_ALLOWED=NO", "build", "-quiet"])
        settings = self.command("ReleaseSettings", common + ["-configuration", "Release", "-sdk", "iphonesimulator",
            "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", str(self.output / "ReleaseDerived"), "-showBuildSettings", "-json"], True)
        app_settings = next(item["buildSettings"] for item in settings if item["target"] == "FitCheck")
        require(app_settings["ENABLE_TESTABILITY"] == "NO", "Normal Release unexpectedly enables testability")
        release = self.test("ReleaseTests", common + ["-configuration", "Release"] + destination + [
            "-derivedDataPath", str(self.output / "ReleaseTestDerived"), "-resultBundlePath", str(self.output / "ReleaseTests.xcresult"),
            "-parallel-testing-enabled", "NO", "ENABLE_TESTABILITY=YES", "CODE_SIGNING_ALLOWED=NO"]
            + ["-only-testing:" + selector for selector in RELEASE_SELECTORS] + ["test", "-quiet"], RELEASE_SELECTORS)
        inspection = inspect_bundles(self.output)
        require(source_digest() == before, "Build/test inputs changed during verification; rerun against final source")
        return {"mode": "fresh-local-builds-and-tests", "simulator": simulator, "sourceSHA256": before,
                "Debug": debug, "Release": release, "normalReleaseTestability": "NO", "inspection": inspection,
                "physicalHardware": "NOT RUN", "manualVisualReview": "Inspect exported synthetic UI evidence separately"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", help="Available iPhone UDID; default dynamically prefers a booted iPhone")
    parser.add_argument("--output-root", type=Path, default=Path(tempfile.gettempdir()) / "FitCheckVerification")
    parser.add_argument("--inspect-derived", type=Path, help="Inspect existing four derived directories only; not fresh build/test proof")
    args = parser.parse_args()
    output_root = args.output_root.expanduser().resolve()
    require(not output_root.is_relative_to(ROOT), "Verification artifacts must remain outside the repository")
    output_root.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix="verification-", dir=output_root))
    print(f"Evidence directory: {output}", flush=True)
    verification = Verification(output)
    try:
        if args.inspect_derived:
            result = {"mode": "existing-artifact-inspection-only", "freshBuildsAndTests": False,
                      "inspection": inspect_bundles(args.inspect_derived.expanduser().resolve())}
        else:
            devices = verification.command("available-simulators", ["xcrun", "simctl", "list", "devices", "available", "--json"], True)
            phones = [device for group in devices["devices"].values() for device in group
                      if device["isAvailable"] and device["name"].startswith("iPhone")]
            require(phones, "No available iPhone simulator")
            phones.sort(key=lambda device: (device["state"] != "Booted", device["name"], device["udid"]))
            simulator = args.simulator or phones[0]["udid"]
            require(any(device["udid"] == simulator for device in phones), "Requested simulator is not an available iPhone")
            verification.command("xcode-version", ["xcodebuild", "-version"])
            verification.command("xcodegen-version", ["xcodegen", "--version"])
            result = verification.run(simulator)
        (output / "verification.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps({"result": "PASS", "evidence": str(output)}, indent=2))
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        (output / "failure.json").write_text(json.dumps({"result": "FAIL", "error": str(error)}, indent=2) + "\n")
        print(f"FAIL: {error}\nEvidence: {output}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
