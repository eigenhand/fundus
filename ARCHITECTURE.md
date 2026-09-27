# Architecture

*English · [Deutsch](ARCHITECTURE.de.md)*

The README says what Fundus does, `SECURITY.md` says what it protects. This one says how
it is put together and which decisions you need to know before you change something.

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
| `App/` | `AppModel` and the app entry — about 600 lines, the smallest folder that matters |
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
     ├─► Segmenter             on the device, SAM 2.1, only when the user taps a thing
     │
     ├─► IntakePrompt ─► ModelClient ─► proposals            one paid call
     │
     ├─► IdentityLookup ─► SearchClient ─► ModelClient       only if looking up is on
     │
     └─► review ─► tick ─► Inventory ─► Indexer ─► vector
```

Two rules are built into that order.

**The device does first what the device can do.** A barcode is decoded locally, with a
check digit, before a single model call is paid for. A tapped thing or a drawn box is cut out locally. The
model sees the photo only after everything cheap and certain has happened — and the
result of the cheap step constrains the expensive one: if the model names an EAN the
decoder did *not* see, it is discarded. A barcode cannot be read by eye.

**Nothing crosses into the inventory without a tick.** `IntakeJob` has six phases, and
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
*usable / foreign / missing*, name the models found in the index, and offer three
separate buttons: catch up, rebuild, delete. Three buttons and not one, because the three
mean different things and one of them deletes.

## `ModelClient` is deliberately small

Faden's provider layer speaks two wire formats, tool calls and reasoning — about nine
hundred lines. Fundus has about 550 across the three files in `Providers/`, and that is
a decision, not a gap: carrying Faden's layer along would mean maintaining it in two
apps so that one of them could use a fraction.

What it does: send an image, get JSON back, plus vectors. It streams nonetheless, and for
a measured reason — one tested provider answered streamed calls in seconds while
non-streamed ones of the same size did not come back at all.

The same applies to the fencing of foreign text: `Intake/UntrustedContent.swift` is the
same seventy-odd lines as in Faden, duplicated. The source says why: sharing it would be
worth a common library, and until that exists, duplicated code is better than one
unprotected app.

## Where state lives

**In the shared container.** The inventory is stored as plain JSON in
`group.dev.eigenhand.shared`, so that Spind can sync it without knowing Fundus. If the
app group is not enabled in a build, `SharedContainer` falls back to the app's own folder
— and the settings say which of the two applies. An app that silently writes somewhere
else is an app that silently loses data.

**In `AppModel`.** One `@Observable` class: the inventory, the settings, the intake
queue. Fundus has no per-conversation state like Faden; there is one inventory and one
queue.

**In the keychain.** Keys, referenced from the settings by name. When “Share with Spind
and Faden” is on (it is off by default), the model key goes into the shared keychain
group — that is the purpose and at the same time the price, and it is written down in
`SECURITY.md`.

## Model weights are not in the bundle

SAM 2.1 Tiny (Apple's Core ML version, float16, Apache-2.0, about 80 MB) is downloaded
at runtime from `huggingface.co/apple/coreml-sam2.1-tiny`, and only when you tap
“Download” in the settings.
`SegmentAssets.swift` handles it. Two reasons, and both matter: the IPA stays under two
megabytes, and the app's license stays separate from the model's.

Segmentation is optional in a second sense too. Without the model, object mode falls back
to what the device picks for itself — which is built for portraits and often misses at a
workbench. With it, your finger decides.

## Testing

Two of the tests are always skipped in the simulator, and they are the honest part: Core ML does not compute the SAM mask in the simulator. The encoder and the
scores come out correctly, `low_res_masks` is zero byte for byte on all three compute
paths, and the same model on the Mac delivers a mask within two parts per
thousand of the reference rectangle. So it is not the code. On a device the two run as
well.

All tests run without a network except `RemoteModelTests`: they download the smallest
SAM package (2.1 MB) from Hugging Face, because resuming a broken-off download can only
be measured, not reasoned out. If the server is unreachable, they skip.

`./run-tests.sh` runs them on a simulator and says why it failed if it did. The CI runs
them on every push that touches something other than a `.md` file.

## Design notes moved from the README

**Looking up identifiers.** A resolved product name sits at the end of a chain with
three fallible links: a blurred sticker, a model that confuses characters, a search
engine that answers anything to any string. Afterwards it looks more reliable than
everything else in the inventory and is the least reliable. Hence the separate tick
that defaults to off, the identifier kept verbatim, and the query, source and date on
the entry. If the results do not match the number, `null` is the model's intended
answer — no suggestion is better than a plausible one. At most eight numbers per photo
(`IdentityLookup.maxPerIntake`): a full toolbox would otherwise cost forty searches and
forty model calls for a list that may be thrown away. The search URL defaults to Brave
Search because Faden uses it too, so one key covers both.

**Barcodes versus manufacturer numbers.** Show a language model some bars and it reads
the digits underneath and guesses where they blur — hence the rule that an EAN only
counts if the on-device decoder saw it. Manufacturer numbers are printed as plain text
and may be read off, but stay marked as *read off*.

**Freshness thresholds.** *Seen* up to 30 days, *presumed* up to 180, then
*unconfirmed* (`Models/Item.swift`). An inventory ages while the database looks like day
one; the stages are there to say so. The two thresholds are set, not measured, and the
source says so.

**On-device embeddings.** `NLContextualEmbedding` (512 dimensions) runs on the phone. It is
coarser than a large embedding model on a server, and still the default: an inventory gets
searched in the basement with one bar of reception or none, and a slightly worse answer
without a network beats a better one that needs it.

**Endpoints and the token budget.** Tested with `z-ai/glm-5.3-flash` through TensorX.
Reasoning models spend the token budget twice — first thinking, then writing — which is
why the output limit defaults to 32,000 and is adjustable in the settings. Too little
looks like an empty answer. “Check the images” in the settings sends a tiny two-color
picture and asks what is on it: a refusal means the model cannot read images, an answer
that names both colors means it can.

**The icon.** A sorting box seen from above, generated rather than drawn:
`python3 Tools/make-icon.py` rewrites the three variants (light, dark, tinted)
byte for byte; the corrections from three attempts are recorded in the script.

## For maintainers

**Releasing.** `./release.sh` archives the app, uploads it to TestFlight and assigns the
build to the internal tester group (`assign-build.sh`). It needs a `.release.env` (copy `.release.env.example`) with `ASC_ISSUER_ID` and
`ASC_KEY_ID`, an App Store Connect API key at
`~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`, and the one-off setup listed at
the top of the script (bundle ID, app record, app group). The Release configuration in
`project.yml` signs manually with the profile “Fundus App Store (API)”; Debug signs
automatically, so the simulator and the tests are unaffected.

**The pre-commit hook.** `git config core.hooksPath .githooks` arms a hook that rejects
commits containing something that looks like an API key. It is versioned in the
repository because a hook in `.git/hooks` is not copied when you clone.
