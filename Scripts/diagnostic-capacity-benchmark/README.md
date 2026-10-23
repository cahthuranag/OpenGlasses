# Diagnostic capacity benchmark (Plan JQ)

A separate temporary iPhone app using the production diagnostic ring/store and file protection.
It creates only synthetic data in its own sandbox, never opens Avenkin's container, and reports
ring-initialization time, including JSON load/decode/pruning. It does not measure total app
startup or cold-filesystem reads. Only the logger value types are stubbed; the measured synthetic
category/name spellings and line lengths are in `LogTypes.swift` and `App.swift`.

Set `DEVELOPMENT_TEAM` to your Apple development team and `JQ_DEVICE` to an unlocked paired iPhone.
From this directory, with XcodeGen installed:

```sh
xcodegen generate --spec project.yml
xcodebuild build -project JQBenchmark.xcodeproj -scheme JQBenchmark \
  -destination "id=$JQ_DEVICE" -derivedDataPath /tmp/avenkin-jq-benchmark \
  -allowProvisioningUpdates
xcrun devicectl device install app --device "$JQ_DEVICE" \
  /tmp/avenkin-jq-benchmark/Build/Products/Debug-iphoneos/JQBenchmark.app
xcrun devicectl device process launch --device "$JQ_DEVICE" com.openglasses.jqbenchmark
```

When the screen says complete, collect the synthetic result and remove the app:

```sh
xcrun devicectl device copy from --device "$JQ_DEVICE" \
  --domain-type appDataContainer --domain-identifier com.openglasses.jqbenchmark \
  --source Documents/result.json --destination /tmp/avenkin-jq-benchmark-result.json
xcrun devicectl device uninstall app --device "$JQ_DEVICE" com.openglasses.jqbenchmark
```

For the 2026-10-23 run the production source was copied into a temporary project, with only the
read-size guard changed from 4 MB to the candidate 16 MB before measurement. That measured guard
is now the production default. The app benchmarks 2,000 and 14,000 per-run capacities, both the
single retained history and the doubled history/current-run checkpoint, with 100- and
300-character lines and nine loads per shape. The files are freshly written before loading.
See the plan for the phone model, OS, measured sizes/times and raw samples.
