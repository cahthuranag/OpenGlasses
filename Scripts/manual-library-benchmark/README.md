# Private manual indexing benchmark

This separate iOS app measures the production PDF extractor, Vision text/table readers,
chunker, embedder and document store. It does not replace the main app. Telemetry and preferences
are adapted in `Stubs.swift`; this is a core pipeline measurement, not an end-to-end app test.

Generate its project with a local signing team in the `DEVELOPMENT_TEAM` environment:

```sh
xcodegen generate --spec Scripts/manual-library-benchmark/project.yml
xcodebuild build -project Scripts/manual-library-benchmark/ManualLibraryBenchmark.xcodeproj \
  -scheme ManualLibraryBenchmark -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/manual-library-benchmark -allowProvisioningUpdates
```

Install the generated app with Xcode or `devicectl`. Copy private fixture PDFs into **this app's**
Documents directory, then launch it on an unlocked phone. The bundle identifier is
`com.openglasses.manualbenchmark`. Keep it foreground while measuring. Each launch removes only
its own generated index and starts a cold import; input PDFs remain. Leave the run uninterrupted.

`Documents/results.json` records counts, stage timings, thermal state and sampled resident bytes.
It contains no manual text, titles, source file paths, table cells or answers. Resident samples
are not peak memory or the OS memory-pressure footprint. `--standard` disables the contextual
embedding preference to measure the baseline embedding path separately.

Retrieve the JSON with `devicectl device copy from` using the app-data-container domain and this
bundle identifier. Commit only reviewed anonymous statistics. Never add private PDFs, extracted
text, checkpoints, generated SQLite indexes, signing settings or the generated Xcode project.
Remove the helper after collecting measurements to erase its private fixture copies.
