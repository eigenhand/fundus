# Fundus

*English · [Deutsch](README.de.md)*

[![Tests](https://github.com/eigenhand/fundus/actions/workflows/tests.yml/badge.svg)](https://github.com/eigenhand/fundus/actions/workflows/tests.yml)

An iPhone inventory app that ships only the interface; you bring the model, endpoint
and API key. Photograph a shelf, and your own model suggests the entries — you decide
which ones go in.

Its two siblings: [Faden](https://github.com/eigenhand/faden), an AI chat app, and
[Spind](https://github.com/eigenhand/spind), a file app. What the app protects, and
what it does not: [SECURITY.md](SECURITY.md). How it is built:
[ARCHITECTURE.md](ARCHITECTURE.md).

## Status and requirements

- An early spare-time project, not a product, and not on the App Store: build it from
  source.
- iPhone only, iOS 17.0 or later. Interface in German and English.
- Building needs Xcode with Swift 6 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
  The CI builds with Xcode 26.6.
- An OpenAI-compatible endpoint (`/v1/chat/completions` with `image_url` contents), a
  model that can read images, and your own API key.

## What leaves your phone

No server of mine, no accounts, no telemetry. The app talks to:

- **your model endpoint** — the photo and the names of things already in the inventory;
- **your search provider** (Brave by default) — only if you turn on lookups and enter a key;
- **huggingface.co** — only if you download the optional SAM 2.1 segmentation model.

Details, including optional embeddings over your endpoint: [SECURITY.md](SECURITY.md#what-leaves-the-device).

## Features

**Photographing instead of typing.** Photograph a shelf, drawer or box; your model
writes entries from what it sees.

**Suggestions, not entries.** Nothing enters the inventory without your tick. Names and
quantities are editable, and a find matching an existing entry raises its quantity
instead of adding a duplicate.

**“Cannot be determined” is an answer.** The model does not guess what it cannot see;
things it cannot name go into a separate list, so you know where to look.

**Tap a thing to single it out.** Tap items or drag a box to send each to the model as
its own cut-out. Optionally uses on-device SAM 2.1 (about 80 MB, downloaded from Hugging
Face on request), otherwise Apple's built-in object detection.

**Barcodes are read by the device, not by the model.** Barcodes and QR codes are decoded
on the device; an EAN the model names but the decoder did not see is discarded.

**Numbers get looked up, but nothing gets replaced.** For a manufacturer number or
barcode, the app can search the web and propose a name, with its own tick (off by
default). The number stays on the entry, with query, source and date.

**A quantity or “—”.** Uncounted is not zero, and nothing is estimated.

**Every entry knows when you last saw it, and who wrote it.** *Seen* (up to 30 days),
*presumed* (up to 180), then *unconfirmed*; swipe right to confirm. Each entry names its
author, a person or a specific model, with the photo as evidence.

**Search that finds what you cannot name.** Name matches first, then matches by meaning,
with vectors computed on the device by default or by your endpoint.

**Places as a tree.** Basement → shelf 2 → box C. Deleting a place deletes no inventory.

**Readable by Faden.** The inventory is plain JSON in the shared app group, so Faden can
read it. Placing your endpoint and API key there too is a separate setting, **“Store
model access in the shared area”**, off by default; no other app reads them yet.

## Building

```bash
brew install xcodegen
xcodegen generate
open Fundus.xcodeproj
```

The `.xcodeproj` is generated from `project.yml` and not checked in. `./run-tests.sh`
runs the tests on a simulator (default “iPhone 17 Pro”, or pass another name).

**Building with your own Apple account.** Replace the author's values before building
for a device:

- `DEVELOPMENT_TEAM` in `project.yml` → your team ID.
- `bundleIdPrefix` and both `PRODUCT_BUNDLE_IDENTIFIER`s (`dev.eigenhand.fundus.ios…`) →
  your own prefix.
- In `Fundus/Fundus.entitlements`, the app group `group.dev.eigenhand.shared` and the
  keychain group `dev.eigenhand.shared` → your own identifiers, or remove them. They
  also appear in `Storage/SharedContainer.swift` and `Storage/Keychain.swift`.

Without a working app group, Fundus uses its own folder and keychain entries, says so
in the settings, and shares nothing with Spind or Faden.

**First run.** Open the settings (gear icon) and enter address, path, model name and
key. **“Check the images”** tells you whether your model can read images. To look up
numbers, enter a search key under “Look up numbers”; any service returning JSON with
title, URL and description works.

Maintainers: releasing (`./release.sh`) and the pre-commit hook are in
[ARCHITECTURE.md](ARCHITECTURE.md#for-maintainers).

## License

Apache-2.0. See [LICENSE](LICENSE). Copyright 2026 Christoph Lindl-Guk.

The optional SAM 2.1 segmentation model is not part of this repository; it is
downloaded from Hugging Face at runtime and has its own license (Apache-2.0, see
`Fundus/Intake/SegmentAssets.swift`).
