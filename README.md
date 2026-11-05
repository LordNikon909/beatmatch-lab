# Beat Match Lab

A browser proof-of-concept exploring an RPG battle-screen mechanic built around DJ beatmatching: load MIDI records into a bin, mix two decks together with automatic phrase-synced crossfades, and watch each deck's actual notes scroll past a fixed playhead — Traktor/Rekordbox-style — live. The deck UI is keyboard-navigable (arrow keys stand in for a game controller, which is where this is ultimately headed), styled to match a Framer design reference (colors, type, chrome, the scrolling track-title ticker) pixel-for-pixel where the two overlap.

## Running it

**Don't open `index.html` directly (double-clicking it loads it as a `file://` URL)** — browsers block the fetches this app needs (the bin preload, the AudioWorklet module, the soundfont) from `file://`, so nothing will load and the console fills with CORS/module errors.

Easiest: double-click **`Start Beat Match Lab.command`**. It starts a local server and opens your browser to it. Leave that terminal window open while you use the app; closing it (or Ctrl+C) stops the server.

Or run any static file server yourself, e.g.:

```bash
python3 -m http.server 8000
```

and open `http://localhost:8000/index.html`.

## The record bin

**Running locally** (any server that serves directory listings, like `python3 -m http.server`): just drop `.mid`/`.midi` files into `tracks/` and reload the page. On startup it reads the `tracks/` directory listing directly and preloads whatever's there — no build step, no regeneration, no restart.

`tracks/` (MIDI) and `sfx/` (UI sound effects) are the only asset folders the app loads, and the only ones committed. `midis/` and `wavs/` are git-ignored scratch space for raw files and work in progress — move a finished file into `tracks/` or `sfx/` to ship it.

**Published as a Claude Artifact** (or any static host without directory listings): that trick doesn't work, so it falls back to a prebuilt `tracks/bundle.json` — one base64-encoded JSON file (Artifacts only serve a fixed list of file extensions, and raw `.mid` isn't one of them, but `.json` is). Regenerate it whenever that deployment's crate should change:

```bash
cd tracks && python3 -c "
import json, os, base64
bundle = {}
for f in sorted(os.listdir('.')):
    if f.lower().endswith(('.mid', '.midi')):
        bundle[f] = base64.b64encode(open(f, 'rb').read()).decode('ascii')
json.dump(bundle, open('bundle.json', 'w'))
"
```

This preload is the only way records get into the bin — the track-select menu is for browsing and loading what's already there, not adding new files.

## What it does

- **Record bin** — no separate panel; it lives inside each deck's track-select menu (open it with Enter or a click), populated from whatever's preloaded from `tracks/` (see below). Each entry gets BPM and key detected immediately (Krumhansl-Schmuckler key-finding). Any grid start or markers already baked into a file (via the companion [MIDI Marker Tool](../midi-marker-tool)) are read too and used during mixing (see Grid start, below), even though the menu row itself no longer displays that status.
- **Title/artist, read from the file itself when present** — if a track has been through the MIDI Marker Tool's Track Info fields, its display name becomes "Artist — Title" instead of the raw filename. Title comes from the file's own Sequence/Track Name slot; artist has no standard MIDI field, so it's a plain Text meta-event by convention with that tool. Falls back to the filename when neither is set. Since this just reads whatever's in those slots, a file from somewhere else that already happens to have *something* there (a few of the preloaded tracks carry a leftover watermark or generic sequencer name from whatever tool originally made them) will show that instead — there's no way to tell real tags apart from incidental ones at the format level.
- **Two decks (A/B), each with its own always-on scrolling piano roll** — every note the deck is about to play, colored by channel (percussion in gray), scrolling past a fixed playhead line as it plays, both decks running independently and simultaneously. The visible window is always ~4 bars at the deck's *current* tempo, so the zoom level naturally tracks tempo changes from a beatmatch. A deck's grid start (cyan flag) and markers (amber flags, pure annotations) are drawn right on the timeline; the armed mix trigger point and crossfade window overlay on top of whichever deck is the current mix anchor.
- **Keyboard-driven deck selection and loading** — a SNES-emulator-style layout: arrow keys are the d-pad, and A/S/X/Enter stand in for a game controller's face buttons and Start:

  | Key | Effect |
  |---|---|
  | ← / → | Select Deck A / Deck B (same highlight as hovering a deck with the mouse) |
  | A | Opens the track-select menu for the selected deck; inside the menu, loads the highlighted record and closes it |
  | ↑ / ↓ | Moves the highlight inside the track-select menu |
  | X / Esc | Closes the menu without loading anything |
  | S / Space | Triggers the automatic Beatmatch Mix once a record is loaded in the other (silent) deck while one is live; otherwise arms (plays) the selected deck — e.g. starting the very first deck, when there's nothing yet to mix into |
  | Enter / P | Pauses or resumes everything — a true freeze (the Transport and the audio engine both stop), with a full-screen "PAUSED" overlay, like pausing a game |
  | Backspace | Stop All — kills both decks immediately and resets to idle |

  A deck that's already playing is locked — once armed, neither S/Space nor a click can stop it again, and it can't be selected or have its menu opened either (by keyboard, hover, or click) since there's nothing to load onto it. The only ways a live deck goes quiet are Beatmatch Mix fading it out automatically, Backspace stopping everything, or Pause freezing everything in place. The moment a deck locks, selection moves off it automatically — onto the other deck if that one's free, or clears entirely if both are briefly live mid-crossfade. When Beatmatch Mix finishes and the deck that just faded out stops, it's reset to empty ("No record loaded") and auto-selected, ready for the next record — no need to arrow-key over to it.

  Clicking directly on a deck's canvas does the same as Left/Right + Enter — selects it and opens its menu; clicking a row in the menu loads it, same as Enter. The track-select menu is the whole record bin UI — there's no separate bin panel.
- **Beatmatch Mix** — whichever deck is currently live is the anchor; S/Space retimes the other (staged) deck onto the anchor's tempo, waits for the anchor's next phrase boundary, enters the incoming deck on its own first downbeat (or its grid start, if it has one — see below), and auto-crossfades over a configurable number of bars. The anchor then fades out and stops, handing "live" status to the deck that just mixed in — load a fresh record into the newly silent deck to keep the set going indefinitely. Phrasing is fully automatic (a configurable 2/4/8/16-bar grid) and never blocked by a record's markers.
- **Post-mix tempo glide** — once a mix finishes and a deck is playing solo, its tempo glides back to its own native BPM over about 4 seconds (real time, not bar-synced — this is deliberately gamified rather than a strict CDJ simulation) instead of staying pinned to whatever it was matched to. The deck stays locked for that same window, same as while actually playing; if a new mix starts before the glide finishes, the incoming track just matches whatever tempo is current at that instant, and if the mid-glide deck itself becomes the new anchor, its tempo freezes right there so it stays a stable reference. A small "master tempo" readout next to the crossfader shows whatever tempo is currently live, ticking as it glides.
- **Grid start** — a single special point per track, marking its real first downbeat, like a beatgrid marker in Traktor. Set it with the MIDI Marker Tool and the automatic bar-count phrasing (and the piano roll's own grid) counts bar 1 from there instead of assuming it's at the file's own start — handles an intro, a pickup, or any MIDI file that just doesn't start exactly on the beat. No grid start is required; it's a refinement, not a gate. It also changes how a track *enters* a mix: a record with a grid start begins playing there when it mixes in — like triggering a hot cue in Traktor — skipping whatever came before it rather than starting at the file's literal beginning; a record with no grid start still enters at its own start, as before.
- **Camelot-colored key pills** — each key pill (on a deck and in the track-select menu) is colored by its [Camelot wheel](https://mixedinkey.com/harmonic-mixing-guide/) position: hue steps evenly around the wheel by Camelot number, with minor keys rendered darker/more muted than their relative major — so two harmonically compatible tracks (same number, or a relative major/minor pair) show visibly similar colors at a glance.
- **Live time readout** — remaining and elapsed time per deck, overlaid on its own canvas. Tracks each deck's *effective* tempo and its own position on the Transport timeline (not just its native tempo and an assumed zero start), so it stays accurate through any number of chained mixes.
- **Crossfader** — a read-only visual reflecting the live gain balance between the two decks; not draggable, just a restyled indicator.
- **Visual design, matched to a Framer prototype** — the deck chrome (pill-bar + player bar, the purple key pill, the green play/arm button), the crossfader ("Mixer"), and the track-select menu (header row, key pills, the distinct "on this deck" row) are styled directly from a Framer reference design, down to its real colors/radii/type (Inter) rather than approximated from screenshots. A dark/light toggle (top-right, persisted in `localStorage`, defaulting to the system preference on first visit) switches the whole page between the reference's own dark palette and a light equivalent; the deck/menu chrome itself (light card surfaces, black screens, the purple/green/coral accents) stays identical in both, same as in the reference.
- **Instrument playback** — each deck runs its own real SoundFont2 synthesizer ([SpessaSynth](https://github.com/spessasus/SpessaSynth), via an AudioWorklet), loaded with `soundfonts/GeneralUserGS.sf3` (GeneralUser GS, ~10MB, Ogg-compressed SF3). Every MIDI channel plays through its own declared GM program, including proper polyphony; percussion plays through the soundfont's own real GM drum kit on channel 9. Drop in a different `.sf2`/`.sf3` file (e.g. an SC-55-style bank, for a more retro/PS1-era character) and update the path in `initAudioEngine()` to change the whole instrument palette — no other code changes needed. A native `DynamicsCompressorNode` sits on the master bus as a safety limiter, and both decks also send into a shared reverb (a `ConvolverNode` driven by a synthesized plate-ish impulse response — exponentially-decaying white noise, no external asset needed) and chorus (an LFO-modulated `DelayNode`) — dry GM playback alone reads thin, and this pair adds most of what makes it sound like a produced track instead. **Local only** — the hosted Claude Artifact version falls back to plain oscillator synths, since its sandbox can't run an AudioWorklet module fetched from an arbitrary CDN.

  **Only that one soundfont is committed**, so a static deploy (e.g. Vercel) has everything it needs. Everything else in `soundfonts/` is gitignored — larger banks like the Arachno SoundFont (~148MB) run past GitHub's 100MB per-file limit and would be a heavy download for every visitor. To try a different bank locally, drop it in `soundfonts/` and update the path in `initAudioEngine()`; compressed `.sf3` versions keep a deploy small.
- **Two separate AudioContexts, on purpose.** The synth engine runs on its own plain native `AudioContext` (`nativeCtx`), kept deliberately apart from the one Tone.js manages. Tone wraps whatever context it owns in its internal `standardized-audio-context` shim, which a real `AudioWorkletNode` constructor's strict native checks reject outright — and handing Tone a native context via `Tone.setContext()` "fixes" that but silently breaks `Tone.Transport` scheduling instead (every `Tone.Part`/`Tone.Loop` callback just stops firing, no error). So `Tone.Transport`/`Tone.Part` keep driving *timing* on Tone's own untouched context, and every scheduled callback's time gets converted to `nativeCtx`'s own clock (a single fixed offset, refreshed in `ensureAudio()`) before it reaches the synth or a gain node. The old Tone.Reverb lived on Tone's context for the same reason and couldn't take input from a different real `AudioContext` — replaced with a native reverb/chorus pair (see below) that runs entirely on `nativeCtx` instead, no bridging needed.

## Known limitations

- Assumes 4/4 time throughout.
- Without a grid start, phrasing assumes a record's own MIDI start is its downbeat.
- Key detection is whole-track and blind to mid-song key changes.
