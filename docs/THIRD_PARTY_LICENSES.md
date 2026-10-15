---
summary: "Bundled open-source notices and how to refresh their pinned sources."
read_when:
  - Auditing bundled third-party resources and their licenses
  - Updating SwiftPM dependencies
---

# Third-party notices

Settings → About → Acknowledgements displays the full notices bundled in
`Sources/CodexBarCore/Resources/Acknowledgements.json`. This generated resource ships with the app,
widget and CLI. CLI release archives also carry a readable `THIRD_PARTY_NOTICES` file.
The desktop links system Qt libraries; it does not bundle Qt.

This inventory covers SwiftPM and the vendored application sources. The static Linux SDK also
embeds runtime libraries outside Package.resolved. Its upstream archive currently contains no
license files; completing that runtime inventory and pinned-source notice collection remains
necessary before treating the static distribution as fully covered.

Refresh notices after changing either root or widget `Package.resolved`:

```sh
python3 Scripts/acknowledgements.py --write
python3 Scripts/acknowledgements.py --verify-upstream
```

The generator reads immutable revisions from both lockfiles, retrieves exact LICENSE and NOTICE files,
and keeps their text and SHA-256 hashes. It includes Sparkle's external notices and ed25519 license,
Swift Crypto's BoringSSL/Fiat and XKCP notices.

`make check` checks both lockfiles, required vendored notices and source-text hashes
without network access. Adding a SwiftPM dependency requires adding its license source to the generator.
`--verify-upstream` additionally regenerates and compares all text against upstream sources.

To inspect the exact plaintext carried by a release archive:

```sh
python3 Scripts/acknowledgements.py --text-output /tmp/THIRD_PARTY_NOTICES
```
