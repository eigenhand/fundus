# Fundus

*English · [Deutsch](README.de.md)*

[![Tests](https://github.com/eigenhand/fundus/actions/workflows/tests.yml/badge.svg)](https://github.com/eigenhand/fundus/actions/workflows/tests.yml)

An iPhone inventory app that ships only the interface; you bring the model, endpoint
and API key. Photograph a shelf, and your own model suggests the entries — you decide
which ones go in.

Designed after [eigenhand.dev](https://eigenhand.dev), like its two siblings:
[Faden](https://github.com/eigenhand/faden), an AI chat app, and
[Spind](https://github.com/eigenhand/spind), a file app that can also sync the
inventory. What the app protects and what it expressly does not:
[SECURITY.md](SECURITY.md). How it is put together: [ARCHITECTURE.md](ARCHITECTURE.md).

## Status and requirements

- An early spare-time project, not a product. Not on the App Store yet — build it from
  source.
- iPhone only, iOS 17.0 or later. Interface in German and English.
- Building needs Xcode with Swift 6 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
  The CI builds with Xcode 26.6.
- An OpenAI-compatible endpoint (`/v1/chat/completions` with `image_url` contents), a
  model that can read images, and your own API key.

## What leaves your phone

No server of mine, no accounts, no telemetry. The app talks to:

- **your model endpoint** — the photo and the names of things already in the inventory;
- **your search provider** (Brave by default) — only if you switch looking up on and enter a key;
- **huggingface.co** — only if you download the optional SAM 2.1 segmentation model.

Details, including optional embeddings over your endpoint: [SECURITY.md](SECURITY.md#what-leaves-the-device).

## Features

**Photographing instead of typing.** A shelf, a drawer, a box — your model reads what
is on it and writes entries from that. Anyone who would have to enter forty things by
hand does not enter them; that is why the camera is the most prominent button.

**Suggestions, not entries.** Nothing lands in the inventory without a tick. A model
reading a shelf miscounts, lumps things together and misreads labels — and an
inventory that silently absorbs model output is worse than none, because people
believe it. The review step shows every find individually, with an editable name and
quantity, and says in advance when a find matches an existing entry and will raise its
quantity rather than create a second one.

**“Cannot be determined” is an answer.** The model is instructed not to guess: no
brand, no size, no variety it cannot see. What it sees but cannot name goes into a list
of its own — “a grey box, lettering out of focus” — so you know where to look yourself.

**Tap a thing to single it out.** Tap the items you mean in the photo, or drag a box
around one, and each goes to the model as its own cut-out — a motor on its own gets its
lettering read, a whole shelf gets half-read. Optionally with SAM 2.1 (Apple's Core ML version,
about 80 MB, downloaded from Hugging Face on request in the settings), which runs on
the device; without it, the app falls back to Apple's built-in object detection, which
is made for portraits and often misses at a workbench.

**Barcodes are read by the device, not by the model.** Apple's Vision decodes EAN, UPC,
Code 128, QR and DataMatrix from the photo — with a check digit, offline, before the
first paid call. If the model names an EAN the decoder did *not* see, it is discarded.
Manufacturer numbers are plain text and may be read off; they stay marked as *read off*.

**Numbers get looked up, but nothing gets replaced.** For a manufacturer number or a
barcode, the app can search the web and propose a precise name — “MP1584EN DC-DC
step-down converter 3 A” instead of “a circuit board”. This is the most dangerous
feature in the app, and it is built accordingly:

- The search result has a **tick of its own** that defaults to **off**. You can keep
  the find and discard the interpretation.
- The number stays with the entry verbatim — the one thing you can check without
  picking the part up.
- The entry records the search query, the source and the date.

**A quantity or “—”.** Uncounted is not zero. An estimated number is worse than none,
because it looks like a count.

**Every entry knows when you last saw it, and who wrote it.** Three stages: *seen* (up
to 30 days), *presumed* (up to 180), *unconfirmed*; a swipe right confirms. Every entry
also says whether a human typed it or a model read it off a photo — and which model —
with the photo kept as evidence.

**Search that finds what you cannot name.** Name matches come first, because they are
certain; matches by meaning (“the black cable with the square plug”) come after and are
labelled as such. The vectors are computed on the device by default, because an
inventory gets searched in the basement with no reception; you can switch to your
endpoint instead.

**Places as a tree.** Basement → shelf 2 → box C, so that “everything in the basement”
stays answerable and renaming the basement does not leave thirty stale entries.
Deleting a place deletes no inventory.

**Optional sharing with Spind and Faden.** The inventory is stored as plain JSON in the
shared app group container `group.dev.eigenhand.shared`, so Spind can sync it. Sharing
the endpoint and API key with the sibling apps is a separate setting, **“Share with
Spind and Faden”**, and it is off by default. If the app group is not available in a
build, Fundus uses its own folder and says so in the settings.

What Fundus deliberately does not do: estimate quantities, adopt model output without
your tick, or run accounts and sync of its own.

## Building

```bash
brew install xcodegen
xcodegen generate
open Fundus.xcodeproj
```

The `.xcodeproj` is not in the repository; it is generated from `project.yml`.
`./run-tests.sh` runs the tests on a simulator (default: “iPhone 17 Pro”, or pass
another name).

**Building with your own Apple account.** `project.yml` and the entitlements carry the
author's values. Change them before building for a device:

- `DEVELOPMENT_TEAM` in `project.yml` → your team ID.
- `bundleIdPrefix` and both `PRODUCT_BUNDLE_IDENTIFIER`s (`dev.eigenhand.fundus.ios…`) →
  your own prefix.
- In `Fundus/Fundus.entitlements`, the app group `group.dev.eigenhand.shared` and the
  keychain group `dev.eigenhand.shared` → your own identifiers, or remove them. The
  same identifiers are also written in `Storage/SharedContainer.swift` and
  `Storage/Keychain.swift`.

Without a working app group, Fundus falls back to its own folder and its own keychain
entries; it keeps working, but nothing is shared with Spind or Faden.

**First run.** Open the settings (gear icon) and enter address, path, model name and
key. **“Check the images”** sends a tiny two-color picture and asks what is on it — that
tells you whether your model can read images. To look up numbers, enter a search key
under “Look up numbers”; any service that returns JSON with title, URL and description
works.

Maintainers: releasing (`./release.sh`) and the pre-commit hook are described in
[ARCHITECTURE.md](ARCHITECTURE.md#for-maintainers).

## License

Apache-2.0. See [LICENSE](LICENSE). Copyright 2026 Christoph Lindl-Guk.

Permissive rather than copyleft, because an inventory app on a phone is not something
anyone could take over as a service — the risk copyleft protects against does not exist
here. Apache-2.0 rather than MIT because of the express patent license.

The optional SAM 2.1 segmentation model is not part of this repository: it is
downloaded at runtime from Hugging Face and is under its own license (Apache-2.0, see
`Fundus/Intake/SegmentAssets.swift`).
