# Security

*English · [Deutsch](SECURITY.de.md)*

## Reporting a vulnerability

Please report security problems **not** as a public issue but by e-mail to
<christoph.lindl-guk@pm.me>. I answer as fast as I can — this is a spare-time project
with no promised response times.

## What leaves the device

Fundus brings no infrastructure with it. There is no server of mine, no telemetry and
no account.

| Where | What | When |
| --- | --- | --- |
| Model endpoint | The photo and the names of the things already in the inventory | When a photo is read |
| Search provider (Brave by default) | The identifier read off and the presumed name | Only when looking up is on and a search key is entered |
| Model endpoint, or a separate embedding address | The text of entries and your search queries | Only when search runs over the endpoint instead of on the device (the default) |
| `huggingface.co` | A download request, nothing of yours | Only when you download the optional SAM 2.1 model |

The inventory itself, the photos and the places stay on the device — in the shared app
group container, if the build has one, where Spind can sync them. Looking up can be
switched off, and the settings say what goes out when it is on. The on-device embedding
model is downloaded by iOS itself when you request it in the settings.

## Keys

API keys live in the **device's keychain**. The setting “Share with Spind and Faden” is
off by default. Switching it on puts the address and the model name into the shared
folder of the app group and the key into the shared keychain group — one app that is set
up then sets up the others. That is the purpose and at the same time the price: the
three apps see the same key. Switched off, your key stays in Fundus. In the other
direction, if Fundus has no endpoint yet and a sibling app has shared one, Fundus adopts
it on launch and says so.

Fundus ships no key of its own: every build starts without one, and the only key it uses
is the one you enter. A versioned `pre-commit` hook (`.githooks/pre-commit`, enabled with
`git config core.hooksPath .githooks`) refuses a commit that contains something that
looks like an API key.

## The architecture this is about

Fundus has no tools a model could call. The lever is quieter: what the model makes of
third-party text becomes a **suggestion**, and one tick later it is in the inventory.

**Search results are fenced.** They are wrapped in markers carrying an identifier
generated per call, and the system instruction for looking up says what applies inside
them: material, not instruction — and `name`, `maker` and `note` may contain only what
describes the object, no addresses and no demands. The reason: a page optimized for a
common part number otherwise writes into other people's inventories. An entry name is
short, gets searched later, and nobody reads it twice.

**A sticker is a sticker.** Text in a photo cannot be fenced — it is part of the image.
The only thing that helps is the rule in the instruction: text on a label is
print, not instruction. This route needs no network and no attacker on the Wi-Fi, just
a second at the shelf.

**The app checks the label itself.** Whether a suggestion is an exact match is not
something Fundus takes the model's word for: `exact` means the identifier appears
**verbatim** in a result, and that gets looked up. If it does not, the suggestion is
downgraded to `near`. A model that wants to please otherwise rates every result a
bullseye — and that very label decides how much trust the line is given.

**Nothing enters the inventory unasked.** Everything that comes out of a photo is a
suggestion with a tick. That is the reason this inventory can be believed, and at the
same time the most effective measure against everything above.

## Model weights

The segmentation model (SAM 2.1, Apple's Core ML version, Apache-2.0) is downloaded at
runtime and is not in the bundle — the IPA stays under two megabytes that way, and the
app's license stays separate from the model's.

It is downloaded over HTTPS from `huggingface.co`; what is checked is the file size
against what the server states. There is no checksum. That is a trade-off: it would
break with every update of the foreign store, and Core ML weights are data, not a
program. If you do not trust the transport, do not download the model; the app works
without it.

## Deliberate compromises

**The photo goes to a third-party endpoint.** That is the purpose of the app. Which one
is up to you; what happens to it there is not something Fundus can check.

**The fence is a request, not a barrier.** Whether the model holds to it cannot be
enforced by any line of code. What a successful attack achieves is a wrong suggestion —
and you see it before ticking it off.

**The shared keychain group is a decision.** See above under “Keys”. If you do not
want it, leave the setting off.

Faden has the same measures and the same limits; the two apps share the
architecture, but no code.

## What is tested

Two SAM tests are skipped in the simulator, because Core ML does not compute the SAM
mask there. The encoder and the scores come out correctly, `low_res_masks` is zero byte
for byte, on all three compute paths — the same model on the Mac delivers a mask within
two parts per thousand of the reference rectangle. So it is not the code. On a device
the two run as well.

The tests run in CI on every push to `main` and every pull request that changes more
than Markdown.
