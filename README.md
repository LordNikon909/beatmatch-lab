# Beat Match Lab

A browser proof-of-concept exploring an RPG battle-screen mechanic built around DJ beatmatching: load MIDI records into a bin, mix two decks together with automatic phrase-synced crossfades, and watch each deck's actual notes scroll past a fixed playhead — Traktor/Rekordbox-style — live. The deck UI is keyboard-navigable (arrow keys stand in for a game controller, which is where this is ultimately headed).

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

- **Record bin** — upload multiple `.midi`/`.mid` files at once; each gets BPM and key detected immediately (Krumhansl-Schmuckler key-finding), plus a phrase-boundary heuristic (self-similarity over bar-bucketed note content) used to auto-suggest a sensible phrase length. Any grid anchor or markers already baked into a file (via the companion [MIDI Marker Tool](../midi-marker-tool)) are read too, and each entry shows whether it's anchored and how many markers it has.
- **Two decks (A/B), each with its own always-on scrolling piano roll** — every note the deck is about to play, colored by channel (percussion in gray), scrolling past a fixed playhead line as it plays, both decks running independently and simultaneously. The visible window is always ~4 bars at the deck's *current* tempo, so the zoom level naturally tracks tempo changes from a beatmatch. A deck's grid anchor (cyan flag) and markers (amber flags, pure annotations) are drawn right on the timeline; the armed mix trigger point and crossfade window overlay on top of whichever deck is the current mix anchor.
- **Keyboard-driven deck selection and loading** — arrow keys stand in for a game controller for now:

  | Key | Effect |
  |---|---|
  | ← / → | Select Deck A / Deck B (same highlight as hovering a deck with the mouse) |
  | Enter | Opens the track-select menu for the selected deck; inside the menu, loads the highlighted record and closes it |
  | ↑ / ↓ | Moves the highlight inside the track-select menu |
  | Esc | Closes the menu without loading anything |
  | Space | Triggers the automatic Beatmatch Mix once a record is loaded in the other (silent) deck while one is live; otherwise arms (plays) the selected deck — e.g. starting the very first deck, when there's nothing yet to mix into |
  | P | Pauses or resumes everything — a true freeze (the Transport and the audio engine both stop), with a full-screen "PAUSED" overlay, like pausing a game |

  A deck that's already playing is locked — once armed, neither Space nor its on-screen button can stop it again. The only ways a live deck goes quiet are Beatmatch Mix fading it out automatically, Stop All, or Pause freezing everything in place.

  Clicking directly on a deck's canvas does the same as Left/Right + Enter — selects it and opens its menu. The original mouse-driven record bin (upload, "→ Deck A/B" buttons) still works exactly as before; the menu is a second path to the same `loadBinEntryIntoDeck` call, not a replacement.
- **Beatmatch Mix** — whichever deck is currently live is the anchor; press the button to retime the other (staged) deck onto the anchor's tempo, wait for the anchor's next phrase boundary, enter the incoming deck on its own first downbeat (or its grid anchor, if it has one — see below), and auto-crossfade over a configurable number of bars. The anchor then fades out and stops, handing "live" status to the deck that just mixed in — load a fresh record into the newly silent deck to keep the set going indefinitely. Phrasing is fully automatic (a configurable 2/4/8/16-bar grid) and never blocked by a record's markers.
- **Grid anchor** — a single special point per track, marking its real first downbeat, like a beatgrid marker in Traktor. Set it with the MIDI Marker Tool and the automatic bar-count phrasing (and the piano roll's own grid) counts bar 1 from there instead of assuming it's at the file's own start — handles an intro, a pickup, or any MIDI file that just doesn't start exactly on the beat. No anchor is required; it's a refinement, not a gate. It also changes how a track *enters* a mix: a record with a grid anchor begins playing there when it mixes in — like triggering a hot cue in Traktor — skipping whatever came before it rather than starting at the file's literal beginning; a record with no anchor still enters at its own start, as before.
- **Harmony badge** — compares the two decks' detected keys (same key / relative major-minor / a fifth apart / clashing) and offers a one-click suggested transpose.
- **Live time readout** — remaining and elapsed time per deck, overlaid on its own canvas. Tracks each deck's *effective* tempo and its own position on the Transport timeline (not just its native tempo and an assumed zero start), so it stays accurate through any number of chained mixes.
- **Crossfader** — a read-only visual reflecting the live gain balance between the two decks; not draggable, just a restyled indicator.
- **Instrument playback** — each deck runs its own real SoundFont2 synthesizer ([SpessaSynth](https://github.com/spessasus/SpessaSynth), via an AudioWorklet), loaded with `soundfonts/Arachno_SoundFont_Version_1.0.sf2`. Every MIDI channel plays through its own declared GM program, including proper polyphony; percussion plays through the soundfont's own real GM drum kit on channel 9. Drop in a different `.sf2`/`.sf3` file (e.g. an SC-55-style bank, for a more retro/PS1-era character) and update the path in `initAudioEngine()` to change the whole instrument palette — no other code changes needed. A native `DynamicsCompressorNode` sits on the master bus as a safety limiter. **Local only** — the hosted Claude Artifact version falls back to plain oscillator synths, since its sandbox can't run an AudioWorklet module fetched from an arbitrary CDN.
- **Two separate AudioContexts, on purpose.** The synth engine runs on its own plain native `AudioContext` (`nativeCtx`), kept deliberately apart from the one Tone.js manages. Tone wraps whatever context it owns in its internal `standardized-audio-context` shim, which a real `AudioWorkletNode` constructor's strict native checks reject outright — and handing Tone a native context via `Tone.setContext()` "fixes" that but silently breaks `Tone.Transport` scheduling instead (every `Tone.Part`/`Tone.Loop` callback just stops firing, no error). So `Tone.Transport`/`Tone.Part` keep driving *timing* on Tone's own untouched context, and every scheduled callback's time gets converted to `nativeCtx`'s own clock (a single fixed offset, refreshed in `ensureAudio()`) before it reaches the synth or a gain node. There's no reverb send for the same reason — it lived on Tone's context and can't take input from a different real `AudioContext`; a native `ConvolverNode`-based reverb could replace the compressor later if the dry sound needs it.

## Known limitations

- Assumes 4/4 time throughout.
- Phrase-length auto-suggestion is a heuristic (self-similarity on note density + pitch-class histograms), not verified song structure — it's just a starting point for the dropdown, not what actually triggers the mix.
- Without a grid anchor, phrasing assumes a record's own MIDI start is its downbeat.
- Key detection is whole-track and blind to mid-song key changes.
