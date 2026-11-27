# Verification

Checked on an Apple M2 MacBook Pro with a built-in Touch Bar running macOS 27.2.
The deployment target is macOS 13. Intel builds and other Touch Bar models have
not been independently checked.

## Automated local checks

- Swift/Objective-C build and strict verification of the ad-hoc app signature.
- Concurrent-session aggregation, state expiry and model rotation.
- Model attribution reset between turns and compatibility with older events.
- Action clock start/freeze, duplicate events, confirmed file counts and recap
  reset. Missing test exit status does not become a passing result.
- Open-app idle presence and Claude terminal session closure.
- Non-destructive hook merging, idempotence, neutral hook output and normalized
  metadata privacy checks. Hook tests use a temporary state root.
- Gemini-chan's installed atlas matches the original included PNG. All animation
  rows used by the app have nonempty frames and preserve a common foot anchor.

## Native and live checks

- Native Touch Bar view attachment at 685 × 30 points.
- Live Codex work/model metadata, action captions, and show/hide controls.
- Live Antigravity model reporting and open-app idle visibility.
- Desktop preview reactions, the three selected companions and demo completion
  recaps. Demo images and GIFs use example data, not live task results.

Claude and Antigravity action/completion parsing has been checked with hook
fixtures. Real Claude action/completion transitions and a complete live
Antigravity action/completion run were not independently exercised. Physical
finger taps remain unconfirmed.

## Shareable gallery

`./scripts/render-demo.sh` renders a 72-frame looping GIF and a PNG poster using
the native drawing code. The exported loop was checked for changing frames,
reading/attention/completion/idle phases and complete, unobscured character
studies. It uses synthetic data and does not read a live session or screenshot
the user's desktop.

## Live Pixel Arena (v1.5)

- Thirty seeded rounds check damage, bounded state, winner selection and scores, rematches, shields and input cooldowns.
- Energy tests distinguish working, open idle, sleeping and approval-wait states; work increases power, idle increases incoming damage, and startup warmup has no idle penalty.
- Each fighter crosses the previous lane boundaries and visits both ends of the playable strip in a deterministic run.
- Model/effort and action captions retain their owning tool; missing metadata is not guessed. Each label stays attached to its owning avatar, including winner celebrations. Crowded and spread-out layout checks cover ownership, adjacency, bounds and label non-overlap.
- Native 685 × 30 strip rendering was reviewed with clearly labelled example metadata for both working and idle states.
- Installed desktop preview confirmed actual reported Codex and Antigravity models/actions, per-tool energy and scores, plus entry/exit and selection controls. Claude had no model metadata in the observed session and was shown as unavailable.
- First-scan warmup is explicitly labelled Connecting. Sprite atlas decoding is cached before frame cropping to avoid repeated PNG decompression during animation.

## Bug boss and sports scoreboard (v1.6)

- Twelve cooperative encounters exercise party and bug victories, boss/party health bounds, no friendly fire, one score per encounter, and next-wave resets.
- Fresh observed actions trigger scans and shields. Repeated polls, stale observations, failures, unknown test outcomes and old recap-only test successes cannot manufacture a test finisher. A known current test pass triggers its larger attack once.
- Thirty duel simulations still pass after slowing health loss. An early-round check ensures the game remains in progress with healthy fighters after eight simulated seconds.
- Both modes hold the scoreboard through its celebration and then reset for a new round after six seconds. Native scoreboard snapshots were reviewed at the entrance and during the updated-score hold.
- The installed app was observed in co-op boss mode with actual reported Codex and Antigravity models, a live Codex SCAN combo and a completed party wave. Physical finger taps and a real reported passing-test finisher were not independently exercised; their event handling was checked with fixtures.

## Game gallery

`./scripts/render-game-gallery.sh` exports a native 116-frame loop with example models and fresh synthetic action events. The fixture reaches a party victory, shows the sports scoreboard, and advances into the next wave. Combat time is compressed for the preview; no live sessions, hooks or desktop captures are used.
