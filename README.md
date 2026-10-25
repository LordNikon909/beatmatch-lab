# Beat Match Lab

A browser proof-of-concept exploring an RPG battle-screen mechanic built around DJ beatmatching: load MIDI records into a bin, mix two decks together with automatic phrase-synced crossfades, and see detected BPM/key/phrase-structure visualized live.

## Running it

It's a single static page with no build step. Any static file server works, e.g.:

```bash
python3 -m http.server 8000
```

Then open `http://localhost:8000/index.html`. (Needs an actual http server — `fetch()` for the preloaded bin won't work over a bare `file://` URL.)

## The record bin

**Running locally** (any server that serves directory listings, like `python3 -m http.server`): just drop `.mid`/`.midi` files into `midis/` and reload the page. On startup it reads the `midis/` directory listing directly and preloads whatever's there — no build step, no regeneration, no restart.

**Published as a Claude Artifact** (or any static host without directory listings): that trick doesn't work, so it falls back to a prebuilt `midis/bundle.json` — one base64-encoded JSON file (Artifacts only serve a fixed list of file extensions, and raw `.mid` isn't one of them, but `.json` is). Regenerate it whenever that deployment's crate should change:

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

You can still add more records manually from the page at any time — the preload just saves re-uploading the same set every session.

## What it does

- **Record bin** — upload multiple `.midi`/`.mid` files at once; each gets BPM and key detected immediately (Krumhansl-Schmuckler key-finding), plus a phrase-boundary heuristic (self-similarity over bar-bucketed note content).
- **Two decks (A/B)** — load any bin record onto either deck, play it, transpose it, adjust its volume.
- **Beatmatch Mix** — whichever deck is currently live is the anchor; press the button to retime the other (staged) deck onto the anchor's tempo, wait for the anchor's next phrase boundary, enter the incoming deck on its own first downbeat, and auto-crossfade over a configurable number of bars. The anchor then fades out and stops, handing "live" status to the deck that just mixed in — load a fresh record into the newly silent deck to keep the set going indefinitely.
- **Harmony badge** — compares the two decks' detected keys (same key / relative major-minor / a fifth apart / clashing) and offers a one-click suggested transpose.
- **Instrument playback** — each deck runs its own real SoundFont2 synthesizer ([SpessaSynth](https://github.com/spessasus/SpessaSynth), via an AudioWorklet), loaded with `soundfonts/GeneralUserGS.sf3`. Every MIDI channel plays through its own declared GM program, including proper polyphony; percussion plays through the soundfont's own real GM drum kit on channel 9. Drop in a different `.sf2`/`.sf3` file (e.g. an SC-55-style bank, for a more PS1-accurate character) and update the path in `initAudioEngine()` to change the whole instrument palette — no other code changes needed. A touch of reverb sits on the master bus so everything shares one room instead of sounding dry. **Local only** — the hosted Claude Artifact version falls back to plain oscillator synths, since its sandbox can't run an AudioWorklet module fetched from an arbitrary CDN.

## Known limitations

- Assumes 4/4 time throughout.
- Phrase detection is a heuristic (self-similarity on note density + pitch-class histograms), not verified song structure.
- Key detection is whole-track and blind to mid-song key changes.
