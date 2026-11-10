fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Mac

### mac build_check

```sh
[bundle exec] fastlane mac build_check
```

PR gate: build and run the unit tests. No signing, no upload.

### mac release_dmg

```sh
[bundle exec] fastlane mac release_dmg
```

Build a Developer ID signed, notarized DMG and its Sparkle appcast. Needs the signing and notarization
secrets listed in `fastlane/.env.example`; CI supplies them from repository secrets, see CONTRIBUTING.md.

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.
More information about fastlane can be found on [fastlane.tools](https://fastlane.tools).
The documentation of [fastlane](https://docs.fastlane.tools) is available on [docs.fastlane.tools](https://docs.fastlane.tools).
