# Fundus

*English · [Deutsch](README.de.md)*

[![Tests](https://github.com/eigenhand/fundus/actions/workflows/tests.yml/badge.svg)](https://github.com/eigenhand/fundus/actions/workflows/tests.yml)

An inventory for the iPhone that brings nothing but the interface. The model, the
endpoint and the API key come from you. No servers in between, no accounts, no
telemetry — the app speaks only to the address you enter.

Design after [eigenhand.dev](https://eigenhand.dev). Sister to
[Faden](https://github.com/eigenhand/faden) (AI chat) and Spind (files).

What the app protects and what it expressly does not: [SECURITY.md](SECURITY.md).
How it is put together: [ARCHITECTURE.md](ARCHITECTURE.md).

## What is in it

**Photographing instead of typing.** A shelf, a drawer, a box — your model reads what
is on it and writes entries from that. Anyone who would have to enter forty things by
hand does not enter them; that is why this app has a camera as its most prominent
button.

**Suggestions, not entries.** Nothing lands in the inventory without a tick. A model
reading a shelf miscounts, lumps things together and misreads labels — and an
inventory that silently absorbs model output is worse than none, because people
believe it. The review step shows every find individually, with an editable name and
an adjustable quantity, and says in advance when a find falls on an existing entry and
will raise its quantity rather than create a second one.

**“Cannot be determined” is an answer.** The model is expressly instructed not to
guess: no brand, no size, no variety that it cannot see. What it sees but cannot name
goes into a list of its own — “a grey box, lettering out of focus”. That tells you
where you have to look yourself, instead of selling you a plausible invention as
inventory.

**Numbers get looked up, but nothing gets replaced.** If a part carries a manufacturer
number, or a barcode is stuck to it, the app can search the web for it and propose a
precise name — “MP1584EN DC-DC step-down converter 3 A” instead of “a circuit board”.
This is the most dangerous feature in this app, and it is built accordingly. A resolved
product name stands at the end of a chain with three fallible links: a blurred sticker,
a model that confuses characters, a search engine that answers anything to any string.
Afterwards it looks more reliable than everything else in the inventory and is the
least so. Therefore:

- The search result has a **tick of its own** and is preset to **off**. You can keep
  the find and discard the interpretation.
- The number stands beside it, verbatim, and stays with the entry — it is the only
  thing that can be checked without picking the thing up.
- The entry carries the search query, the source and the date.
- If the results do not match the number, `null` is the model's intended answer. No
  suggestion is better than a plausible one.

**Barcodes are read by the device, not by the model.** Apple's Vision decodes EAN, UPC,
Code 128, QR and DataMatrix from the photo — with a check digit, without a network,
without cost, before the first paid call. Show a language model some bars and it reads
the digits underneath and guesses where they blur. If the model names an EAN the
decoder did *not* see, it is discarded: a barcode cannot be read by eye. Manufacturer
numbers, by contrast, stand as plain text on the part and may be read off — they stay
marked as *read off* and therefore as fallible.

**A quantity or “—”.** `null` means uncounted, not zero. An estimated number is worse
than none, because it looks like a count. Tins in a box, screws in a bin: uncounted.

**Every entry knows when you last saw it.** An inventory ages while the database looks
like day one — that is the one untruth an inventory app produces all by itself. Three
stages: *seen* (up to 30 days), *presumed* (up to 180), *unconfirmed*. A swipe right
confirms. A filter shows what has gone too long without confirmation. The two
thresholds are set, not measured, and say so in the source.

**And who wrote it.** Every entry says whether a human typed it or a model read it off
a photo — and **which** model. The photo stays beside it as evidence. Whoever stands in
front of the shelf later and cannot find the number again needs to know whose number
that was.

**Search that finds what you cannot name.** Two routes, and the order is the decision:
a name match is a certainty, a cosine is a guess. Whoever types “Rudi” gets the thing
called Rudi first. Similarity search earns its place with “the black cable with the
square plug” — no substring finds anything there — but must not push a certain match
down. Results that come from meaning are labelled as such.

**Vectors on the device, by default.** Apple's `NLContextualEmbedding`: 512 dimensions,
108 MB of model files, measured at 8 ms per entry and 13.5 MB of memory. Coarser than a
network model — on nine questions against fourteen sentences, `qwen3-embedding-8b` hit
first place seven times, this one five. The default nonetheless, and the reason is the
place: an inventory is searched in the basement, in front of the shelf, with one bar of
reception or none. Five out of nine without a network beat seven out of nine with. Do
it differently and you switch to your endpoint.

**The index says what is in it.** Every vector carries a model name and a dimension.
Two embeddings are comparable only if they come from the same model — without the stamp
the search would quietly compute between two spaces that have nothing to do with each
other after a model change. The settings therefore count *usable / foreign / missing*
and name the models that lie in the index. Catching up, rebuilding and deleting are
three separate buttons.

**Places as a tree.** Basement → shelf 2 → box C. As a tree and not as a string, so
that “everything in the basement” stays answerable and a renamed basement does not
linger in thirty entries. Deleting a place deletes no inventory: the things lie nowhere
afterwards, which is true and visible.

**Shared with Spind and Faden.** The inventory lies as plain JSON in the shared
container `group.dev.eigenhand.shared` — Spind can sync it without knowing Fundus. The
endpoint and model name lie beside it in `eigenhand/endpoint.json`, the key in the
shared keychain group: set up one of the three apps and you have set up all three. If
the app group is not enabled in a build, the app falls back to its own folder — and
says in the settings which of the two applies, instead of leaving you to guess.

## What it does not do

- **No barcode as the main route.** EAN is read where there is one, and resolved if you
  switch that on. But a box of M4 screws and a nameless USB-C cable have none, and that
  is the normal case in a workshop.
- **No accounts, no server, no syncing from us.** That is what Spind is for.
- **No silent adoption of model output.** See above — that is the point.
- **No quantity estimates.** What cannot be counted stays uncounted.

## Setting it up

On first launch Fundus asks for an address, path, model name and key. Anything
OpenAI-compatible works: `/v1/chat/completions` with `image_url` contents. The model has
to be able to read images — **“Check images”** in the settings sends a tiny two-colour
picture and asks what is on it. A refusal means no, an answer that names both colours
means yes. Nothing is guessed.

Tested with `z-ai/glm-5.3-flash` through TensorX. Reasoning models need the token budget
twice — first to think, then to write — which is why the limit sits at 32,000 and is
adjustable in the settings. Too little of it looks like an empty answer; the app now
says when that is what it was.

Looking numbers up is off until a search key is entered. Preset to Brave Search,
because Faden uses the same one; any service works that returns JSON with a title, an
address and a description. At most eight numbers per photo — a full toolbox would
otherwise cost forty searches and forty model calls for a list that may be thrown away.

## Building

```bash
brew install xcodegen
xcodegen generate
open Fundus.xcodeproj
```

The `.xcodeproj` is not in the repository — it is generated from `project.yml`. The
bundle ID is `dev.eigenhand.fundus.ios`; for the app group it needs the
`com.apple.security.application-groups` entitlement with `group.dev.eigenhand.shared`
in the developer portal.

```bash
./run-tests.sh            # 182 tests on a simulator
./release.sh              # archive, upload to TestFlight, assignment
git config core.hooksPath .githooks
```

The hook keeps a key used for a TestFlight build out of the history. It lies versioned
in the repository, because a hook in `.git/hooks` travels with no clone.

## Layout

```
Fundus/
  Models/      Item · ItemCode · Place · Inventory · Settings   — value types, testable
  Intake/      IntakePrompt · PhotoIntake · BarcodeScanner · IdentityLookup
  Search/      LocalEmbedder · Indexer · ItemSearch     — names, meaning, index
  Storage/     SharedContainer · Store · Keychain · PhotoStore
  Providers/   ModelClient · SearchClient · VisionProbe  — all the network traffic
  UI/          InventoryView · IntakeView · ItemDetailView · PlacesView · SettingsView
  App/         AppModel · FundusApp
  Design/      Theme                                    — verbatim as in Faden
```

`ModelClient` is deliberately small: an image out, JSON back, plus vectors. Faden's
provider layer speaks two wire formats, tool calls and reasoning — carrying nine hundred
lines of that along would mean maintaining them in two apps so that one could use a
fraction. It streams nonetheless: one tested provider answered streamed calls in
seconds, while non-streamed ones of the same size did not come back at all.

## The icon

A sorting box seen from above, navy on light like the rest of the family. Generated,
not painted — `python3 Tools/make-icon.py` rewrites the three variants (light, dark,
tinted) and arrives at the same bytes.

Three attempts, and the corrections stand in the script: rectangles in cells read as a
wireframe, not as a box. What makes the difference is the thick outer wall against thin
dividers — a diagram has the same stroke width everywhere — and contents with a shape
instead of filled tiles. No dashboard has round tiles; three circles say “screws”.

## Licence

Apache-2.0. See [LICENSE](LICENSE). Copyright 2026 Christoph Lindl-Guk.

Permissive and not copyleft, because an inventory app on a phone is not something
anyone could take over as a service — the risk a copyleft protects against does not
exist here. Apache-2.0 rather than MIT because of the express patent licence.

The model weights are not part of it: they are downloaded at runtime and stand under
their own licences (see `Intake/SegmentAssets.swift`).
