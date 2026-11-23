# Bouncer plugins for SwiftPM and Xcode

SwiftPM and Xcode plugins that run [Bouncer](https://github.com/matthewa26/bouncer) as part of your build.

> **Not released yet.** The first release of this package will follow Bouncer 1.3.0, the first Bouncer release
> that ships the prebuilt artifact bundle. Until then, `Package.swift` points at a placeholder and won't resolve.

- **BouncerBuildPlugin** runs `bouncer check` on a target's sources whenever they change, and Bouncer's
  findings show up as compiler warnings and errors in `swift build` output and in Xcode's issue navigator.
- **BouncerCommandPlugin** runs `bouncer review` on the whole package on demand: `swift package bouncer`,
  or the Bouncer item in Xcode's package plugin menu.

Bouncer comes into your build as a prebuilt binary (a SwiftPM artifact bundle attached to each Bouncer
release), not as source. That keeps Bouncer's own dependencies, swift-syntax among them, out of your
package's dependency graph, so it can't clash with the swift-syntax version your macros need. The bundle
has macOS (arm64 and x86_64) and Linux (x86_64 and arm64, static) binaries; Windows isn't covered yet.

## Install

### SwiftPM

Add the package, then the plugin to each target you want checked:

```swift
dependencies: [
    .package(url: "https://github.com/matthewa26/bouncer-plugin", from: "1.3.0"),
],
targets: [
    .target(
        name: "MyLibrary",
        plugins: [.plugin(name: "BouncerBuildPlugin", package: "bouncer-plugin")]
    ),
]
```

`swift build` then prints Bouncer's findings next to the compiler's:

```
/path/to/Sources/MyLibrary/Parser.swift:42:1: warning: Function is 14 logical lines; the limit is 10. [long-function]
```

### Xcode

1. File > Add Package Dependencies..., enter `https://github.com/matthewa26/bouncer-plugin`, and add it to
   your project without linking any product to a target.
2. Select a target, open Build Phases, and under Run Build Tool Plug-ins add **BouncerBuildPlugin**.
3. Build. Xcode asks once to trust the plugin ("Trust & Enable"). In CI, `xcodebuild` needs
   `-skipPackagePluginValidation`, or the plugin's fingerprint pre-approved in Xcode's defaults.

Findings appear in the issue navigator, attached to their file and line.

## Errors and warnings

The build plugin runs `bouncer check --files <the target's sources> --format xcode`. Each finding is
reported at its configured severity:

- `warning` and `info` findings show up as warnings and notes and never fail the build.
- `error` findings show up as errors and **fail the build**, the same as `bouncer check` failing a pre-commit
  hook. That's Bouncer's default `--severity-threshold error`, and it's what a rule set to `error` in
  `.bouncer` is asking for.

To see a rule's findings without failing builds, lower its severity in `.bouncer`:

```json
{ "rules": { "long-function": { "severity": "warning" } } }
```

A failed check leaves no stamp file, so the next build runs it again rather than hiding the errors. A
passing check reruns only when one of the target's sources or the repo's `.bouncer` changes.

## Configuration

The plugin runs Bouncer from the package directory (or, in Xcode, the project directory), so Bouncer finds
your configuration the same way it does on the command line: the `.bouncer` at the root of the enclosing git
repository, layered over `~/.bouncer`. Exclude globs in `.bouncer` apply to the files the plugin passes.

Builds run plugins in a sandbox that may only write to the plugin's own work directory, which shapes a few
things:

- The update check is off (`--no-update-check`, and `BOUNCER_NO_UPDATE_CHECK=1`), since the sandbox has no
  network and Bouncer couldn't write its update-check cache anyway.
- Hooks in `.bouncer` don't run: there's no terminal to answer the trust prompt.
- Leave `project.inCheck` off (its default). The project rules cache facts in `.bouncer-cache/` at the repo
  root, which the sandbox can't write. Run them with `swift package bouncer`, or `bouncer review` directly.

## The command plugin

```sh
swift package --allow-writing-to-package-directory bouncer
swift package --allow-writing-to-package-directory bouncer --format table
```

It runs `bouncer review <package directory> --no-update-check`, passing any extra arguments to `review`. It
asks to write to the package directory because `review`'s project rules cache facts in `.bouncer-cache/`;
without the flag, SwiftPM prompts. If the package sits below its git repository's root (a monorepo),
`.bouncer-cache/` is outside the package and the sandbox refuses the write; run `bouncer review` directly
there, or add `--disable-sandbox`.

## Testing an unreleased Bouncer

Point the package at a local bundle by setting `BOUNCER_PLUGIN_LOCAL_BUNDLE` to a path inside this package
(SwiftPM requires binary targets to live in the package; `LocalBundle/` is git-ignored):

```sh
# In a Bouncer checkout:
swift build -c release --arch arm64 --arch x86_64
sh Scripts/make-artifactbundle.sh dev "$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/bouncer" \
  - - /path/to/bouncer-plugin/LocalBundle/bouncer.artifactbundle.zip

# In a package that depends on bouncer-plugin by local path:
BOUNCER_PLUGIN_LOCAL_BUNDLE=LocalBundle/bouncer.artifactbundle.zip swift build
```

`-` leaves a platform out of the bundle, which is fine for a local test. Xcode doesn't pass your shell's
environment to package manifests, so this switch is for `swift build` only; launch Xcode from a shell with
the variable exported (`open -a Xcode`) if you need it there.

## Releasing

Bouncer's release workflow does this automatically: after publishing a release, its `plugin` job sets
`bouncerVersion` and `bouncerChecksum` in `Package.swift` to the new tag and its `bouncer.artifactbundle.zip`
checksum, commits, and tags this repo with the same version without the `v` (for example `1.3.0`, so `from:`
requirements work). It uses Bouncer's `HOMEBREW_TAP_TOKEN` secret, which needs Contents read and write here.

To do it by hand, for example if that token has expired:

1. In `Package.swift`, set `bouncerVersion` to the release tag and `bouncerChecksum` to the checksum the release
   run prints in its summary. To recompute it: download the zip and run
   `swift package compute-checksum bouncer.artifactbundle.zip`.
2. Check it resolves: `swift package resolve` in a package that depends on this one by local path.
3. Commit, then tag this repo with the release's version without the `v`, and push the tag.

## License

GPL-3.0-or-later, the same as Bouncer. See [LICENSE](LICENSE).
