# Architecture

*English · [Deutsch](ARCHITECTURE.de.md)*

The README says what Fundus does, `SECURITY.md` says what it protects. This one says how
it is put together and which decisions you have to know before you change something.

## The shape

Nine folders, no external dependencies, about 9,300 lines.

```
UI  ────────►  App  ────►  Intake  ────►  Providers
 │              ├───────►  Search          │
 │              ├───────►  Storage  ───────┤
 │              └───────►  Models  ◄───────┘
 └────────────────────────────────►  Media
```

The direction is downwards, with **one** exception in the code. `Models/Settings.swift`
reaches into `Search` for one constant — `LocalEmbedder.modelIdentifier` — because a
vector has to carry the name of the model that produced it, and the settings decide which
model that is. It could be inverted by passing the value in. It has not been, and this
sentence exists so that nobody has to find that out by reading.

(A second apparent back-edge, `Intake → UI`, is a doc comment in `Segmenter.swift`
pointing at `ObjectPicker.circle`. No code follows it.)

| Folder | What lives there |
| --- | --- |
| `Models/` | Value types: item, code, place, inventory, settings. `Codable`, testable, no I/O |
| `Intake/` | The pipeline from photo to proposal: barcode, segmentation, prompt, lookup |
| `Search/` | Embedding on the device, the index, the two-route search |
| `Providers/` | Model client, search client, vision probe — all the network traffic |
| `Media/` | Camera, library picker, image preparation |
| `Storage/` | The shared container, JSON persistence, keychain, photo store |
| `App/` | `AppModel` and the app entry — 605 lines, the smallest folder that matters |
| `UI/` | 10 views, 3,600 lines |
| `Design/` | One file, taken over from Faden verbatim |

## The spine: photo to entry

Everything else in this app serves one pipeline, and the order of its steps is the
architecture.

```
   photo
     │
     ├─► BarcodeScanner        on the device, Apple Vision, with a check digit
     │                         — before anything is paid for
     ├─► Segmenter             on the device, SAM 2.1, only when the user draws a box
     │
     ├─► IntakePrompt ─► ModelClient ─► proposals            one paid call
     │
     ├─► IdentityLookup ─► SearchClient ─► ModelClient       only if looking up is on
     │
     └─► review ─► tick ─► Inventory ─► Indexer ─► vector
```

Two rules are built into that order.

**The device does first what the device can do.** A barcode is decoded locally, with a
check digit, before a single model call is paid for. A drawn box is cut out locally. The
model sees the photo only after everything cheap and certain has happened — and the
result of the cheap step constrains the expensive one: if the model names an EAN the
decoder did *not* see, it is discarded. A barcode cannot be read by eye.

**Nothing crosses into the inventory without a tick.** `IntakeJob` has seven phases, and
`review` is one of them. There is no path from `ModelClient` to `Inventory` that does not
pass through a human. This is not a safety feature bolted on; it is why the pipeline is
shaped this way at all, and it is the reason the inventory can be believed.

## The queue

Photos do not arrive one at a time. Someone walking a basement takes twenty, and each one
costs a model call of several seconds.

`IntakeJob` is therefore a value type with a phase, and `AppModel` holds a queue of them.
How many run side by side is a setting, not a constant — and the reason is in the source:
the right number does not depend on the app but on the provider. One accepts six calls
next to each other, the next throttles at two and answers 429.

The phases are `waiting · reading · looking · review · empty · failed`, and two of them
are not errors. `empty` means the model read the photo and found nothing that belongs in
an inventory. `failed` carries a sentence for a human. Both stay in the strip until
someone dismisses them, because a photo that quietly disappears is worse than one that
says why it did not work.

## Two embedding spaces, and why every vector is stamped

Search runs two routes, and the order is a decision rather than a ranking: a name match
is a certainty, a cosine is a guess. `ItemSearch` puts name hits first and never lets a
similarity result push a certain one down.

The vectors themselves come either from Apple's `NLContextualEmbedding` on the device or
from an endpoint. That is the interesting problem: **two embeddings are only comparable
if they come from the same model.** Without a stamp, the search would quietly compute
between two spaces after a model change and return nonsense that looks like results.

Every vector therefore carries a model name and a dimension. The settings count
*usable / foreign / missing*, name the models that lie in the index, and offer three
separate buttons: catch up, rebuild, delete. Three buttons and not one, because the three
mean different things and one of them deletes.

## `ModelClient` is deliberately small

Faden's provider layer speaks two wire formats, tool calls and reasoning — about nine
hundred lines. Fundus has 547 across three files, and that is a decision, not a gap:
carrying Faden's layer along would mean maintaining it in two apps so that one of them
could use a fraction.

What it does: send an image, get JSON back, plus vectors. It streams nonetheless, and for
a measured reason — one tested provider answered streamed calls in seconds while
non-streamed ones of the same size did not come back at all.

The same applies to the fencing of foreign text: `Intake/UntrustedContent.swift` is the
same sixty lines as in Faden, duplicated. The source says why: sharing it would be worth
a common library, and until that exists, duplicated code is better than one unprotected
app.

## Where state lives

**In the shared container.** The inventory lies as plain JSON in
`group.dev.eigenhand.shared`, so that Spind can sync it without knowing Fundus. If the
app group is not enabled in a build, `SharedContainer` falls back to the app's own folder
— and the settings say which of the two applies. An app that silently writes somewhere
else is an app that silently loses data.

**In `AppModel`.** One `@Observable` class: the inventory, the settings, the intake
queue. Fundus has no per-conversation state like Faden; there is one inventory and one
queue.

**In the keychain.** Keys, referenced from the settings by name. When “share with Spind
and Faden” is on, they lie in the shared keychain group — that is the purpose and at the
same time the price, and it is written down in `SECURITY.md`.

## Model weights are not in the bundle

SAM 2.1 (Apple's Core ML version, Apache-2.0) is downloaded at runtime.
`SegmentAssets.swift` handles it. Two reasons, and both matter: the IPA stays under two
megabytes, and the app's licence stays separate from the model's.

Segmentation is optional in a second sense too. Without the model, object mode falls back
to what the device picks for itself — which is built for portraits and often misses at a
workbench. With it, your finger decides.

## Testing

182 tests, two of them skipped, all without a network. The two skipped ones are the
honest part: Core ML does not compute the SAM mask in the simulator. The encoder and the
scores come out correctly, `low_res_masks` is zero byte for byte on all three compute
paths, and the same model on the Mac delivers a mask that lies within two parts per
thousand of the reference rectangle. So it is not the code. On a device the two run
along.

`./run-tests.sh` runs them on a simulator and says why it failed if it did. The CI runs
them on every push that touches something other than a `.md` file.
