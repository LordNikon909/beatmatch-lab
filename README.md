# Beat Match Lab

A browser proof-of-concept exploring an RPG battle-screen mechanic built around DJ beatmatching: load MIDI records into a bin, mix two decks together with automatic marker-synced crossfades, and see each record's actual notes and mix points visualized live as a piano roll.

## Running it

**Don't open `index.html` directly (double-clicking it loads it as a `file://` URL)** — browsers block the fetches this app needs (the bin preload, the AudioWorklet module, the soundfont) from `file://`, so nothing will load and the console fills with CORS/module errors.

Easiest: double-click **`Start Beat Match Lab.command`**. It starts a local server and opens your browser to it. Leave that terminal window open while you use the app; closing it (or Ctrl+C) stops the server.

Or run any static file server yourself, e.g.:

```bash
python3 -m http.server 8000
```

and open `http://localhost:8000/index.html`.

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

- **Record bin** — upload multiple `.midi`/`.mid` files at once; each gets BPM and key detected immediately (Krumhansl-Schmuckler key-finding). Any markers already baked into a file are read too, and each entry shows its marker count — or a warning if it has none.
- **Two decks (A/B)** — load any bin record onto either deck, play it, transpose it, adjust its volume.
- **Mix points come from real MIDI markers, not a guess.** This app doesn't detect phrase boundaries itself — it reads standard MIDI Marker meta-events baked into the file beforehand by the companion [MIDI Marker Tool](../midi-marker-tool), so mix points are "set in stone" ahead of time rather than re-guessed at runtime, same as a game would want. A record with no markers can still mix **in** as the incoming deck (it enters at its own MIDI start), but can't be the anchor — Beatmatch Mix needs to know where the *live* deck's next valid mix point is.
- **Beatmatch Mix** — whichever deck is currently live is the anchor; press the button to retime the other (staged) deck onto the anchor's tempo, wait for the anchor's own next marker, enter the incoming deck on its own first downbeat, and auto-crossfade over a configurable number of bars. The anchor then fades out and stops, handing "live" status to the deck that just mixed in — load a fresh (marked) record into the newly silent deck to keep the set going indefinitely.
- **Piano-roll phrase grid** — the currently-live deck's actual notes, rendered as a full piano roll (colored by channel, percussion in gray), with its markers drawn as amber flags right on the timeline — the same data driving the mix, not a separate abstraction. Playhead, the armed mix trigger point, and the crossfade window all draw on top of it live.
- **Harmony badge** — compares the two decks' detected keys (same key / relative major-minor / a fifth apart / clashing) and offers a one-click suggested transpose.
- **Live time/bar readout** — elapsed, remaining, and total time plus bar position (e.g. "bar 14 / 89") for whichever deck is currently live, next to the phrase grid. Tracks each deck's *effective* tempo and its own position on the Transport timeline (not just its native tempo and an assumed zero start), so it stays accurate through any number of chained mixes.
- **Instrument playback** — each deck runs its own real SoundFont2 synthesizer ([SpessaSynth](https://github.com/spessasus/SpessaSynth), via an AudioWorklet), loaded with `soundfonts/GeneralUserGS.sf3`. Every MIDI channel plays through its own declared GM program, including proper polyphony; percussion plays through the soundfont's own real GM drum kit on channel 9. Drop in a different `.sf2`/`.sf3` file (e.g. an SC-55-style bank, for a more PS1-accurate character) and update the path in `initAudioEngine()` to change the whole instrument palette — no other code changes needed. A native `DynamicsCompressorNode` sits on the master bus as a safety limiter. **Local only** — the hosted Claude Artifact version falls back to plain oscillator synths, since its sandbox can't run an AudioWorklet module fetched from an arbitrary CDN.
- **Two separate AudioContexts, on purpose.** The synth engine runs on its own plain native `AudioContext` (`nativeCtx`), kept deliberately apart from the one Tone.js manages. Tone wraps whatever context it owns in its internal `standardized-audio-context` shim, which a real `AudioWorkletNode` constructor's strict native checks reject outright — and handing Tone a native context via `Tone.setContext()` "fixes" that but silently breaks `Tone.Transport` scheduling instead (every `Tone.Part`/`Tone.Loop` callback just stops firing, no error). So `Tone.Transport`/`Tone.Part` keep driving *timing* on Tone's own untouched context, and every scheduled callback's time gets converted to `nativeCtx`'s own clock (a single fixed offset, refreshed in `ensureAudio()`) before it reaches the synth or a gain node. There's no reverb send for the same reason — it lived on Tone's context and can't take input from a different real `AudioContext`; a native `ConvolverNode`-based reverb could replace the compressor later if the dry sound needs it.

## Known limitations

- Assumes 4/4 time throughout.
- An anchor deck with no markers can't trigger Beatmatch Mix — mark it with the [MIDI Marker Tool](../midi-marker-tool) first (a double-click launcher/README live there too).
- Key detection is whole-track and blind to mid-song key changes.
