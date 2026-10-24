# Beat Match Lab

A browser proof-of-concept exploring an RPG battle-screen mechanic built around DJ beatmatching: load MIDI records into a bin, mix two decks together with automatic phrase-synced crossfades, and see detected BPM/key/phrase-structure visualized live.

## Running it

It's a single static page with no build step. Any static file server works, e.g.:

```bash
python3 -m http.server 8000
```

Then open `http://localhost:8000/index.html`. (Needs an actual http server — `fetch()` for the preloaded bin won't work over a bare `file://` URL.)

## The record bin

Drop `.mid`/`.midi` files into `midis/`, then regenerate the base64 bundle it preloads from on startup:

```bash
cd midis && python3 -c "
import json, os, base64
bundle = {}
for f in sorted(os.listdir('.')):
    if f.lower().endswith(('.mid', '.midi')):
        bundle[f] = base64.b64encode(open(f, 'rb').read()).decode('ascii')
json.dump(bundle, open('bundle.json', 'w'))
"
```

It's one base64-encoded JSON file rather than per-file fetches so the same code and the same bundle also work when published as a Claude Artifact, whose sandbox only serves a fixed list of file extensions (raw `.mid` isn't one of them, but `.json` is).

You can still add more records manually from the page at any time — the preload just saves re-uploading the same set every session.

## What it does

- **Record bin** — upload multiple `.midi`/`.mid` files at once; each gets BPM and key detected immediately (Krumhansl-Schmuckler key-finding), plus a phrase-boundary heuristic (self-similarity over bar-bucketed note content).
- **Two decks (A/B)** — load any bin record onto either deck, play it, transpose it, adjust its volume.
- **Beatmatch Mix** — whichever deck is currently live is the anchor; press the button to retime the other (staged) deck onto the anchor's tempo, wait for the anchor's next phrase boundary, enter the incoming deck on its own first downbeat, and auto-crossfade over a configurable number of bars. The anchor then fades out and stops, handing "live" status to the deck that just mixed in — load a fresh record into the newly silent deck to keep the set going indefinitely.
- **Harmony badge** — compares the two decks' detected keys (same key / relative major-minor / a fifth apart / clashing) and offers a one-click suggested transpose.
- **Instrument playback** — each track plays through a real sampled GM instrument matching its own declared program (soundfont-player, MusyngKite soundfont), with a touch of reverb so everything sits in one room instead of sounding dry. Percussion still uses simple synthesized hits (this soundfont has no GM drum kit). **Local only** — the hosted Claude Artifact version falls back to plain oscillator synths, since its sandbox can't fetch instrument samples from an arbitrary CDN at runtime.

## Known limitations

- Assumes 4/4 time throughout.
- Phrase detection is a heuristic (self-similarity on note density + pitch-class histograms), not verified song structure.
- Key detection is whole-track and blind to mid-song key changes.
- The shared single-voice kick/snare/hat synths drop a hit if two of the same kind land too close together for the synth's envelope to retrigger in time (common on dense real drum tracks) — logged nowhere, just silently skipped.
