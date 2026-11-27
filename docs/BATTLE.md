# Pixel Arena

Press **Battle!** in the playground window or choose **Companion battle** from its menu bar icon. The same live-linked game appears in the desktop strip and on the Touch Bar.

The three companions join a friendly, fictional free-for-all. They move, hop over low shots, fire coloured projectiles and lose health on impact. A countdown starts each round. The last fighter standing wins; a 35-second limit resolves a stalled round by remaining health. Winners celebrate, keep their score, and start a fresh round after four seconds.

## Controls and readable information

- **Tap a fighter:** select it, cheer it with a 0.9-second shield, and fire a two-shot special. Specials have a two-second cooldown.
- **Tap empty arena ground:** your selected fighter dashes toward it and fires. Dashes have a one-second cooldown shared with specials.
- **Tap LIVE at the right:** return to live coding activity. The window's **Live activity** button does the same.
- **Health and energy:** coloured health bars above each fighter, with a thinner mint energy bar beneath.
- **Attached labels:** each avatar carries its own name, model and action. Its label stays next to it, connected by a short matching-colour tether. Name/HP/energy/wins occupy the first line when space permits; the model and action use the next two lines. Long text truncates inside its space. During close passes, details collapse to a tiny owner badge rather than jumping elsewhere or covering another fighter. The desktop window always shows all three tools' full live details and game stats in fixed cards.
- **Knocked out:** a companion stays visible but dim, with a KO label. It returns with full health next round.
- **Winner:** a star and winner caption appear on that fighter's own label. There is no shared rotating panel that can show another fighter's data during a celebration.

All living fighters roam the full playable strip, passing each other without fixed lanes. The rightmost LIVE control remains reserved as an exit.

## Live information and energy

The coding tools' existing read-only status observations supply each fighter's actual mood, reported model/effort and action caption. A missing model is shown as **no model reported** on the strip and **Model unavailable** in the desktop card. An idle tool's known model is marked **Last:**. Starting a battle exits synthetic animation preview mode.

- Every fighter starts with 50/100 energy.
- Observed working time charges 3 energy per game second, capped at 100. More energy increases shot damage and firing rate; working also gives a modest extra boost.
- An open idle tool loses 3 energy/second and takes 1.35× damage. A sleeping tool loses 5 energy/second and takes 1.6× damage.
- Waiting for human input or approval does not drain energy or increase incoming damage. Completion adds 1 energy/second while the completion state is visible.
- Energy and observed work/idle timers carry between rounds. Health resets each round; leaving and starting a new arena resets the game.
- Source startup displays **Connecting…** until the initial status scan completes. Energy and idle timers stay neutral during that warmup.

Work and idle timers count time observed while this arena runs. They are game counters, not total tool usage, tokens, cost, benchmark scores or a productivity assessment. Real action timers and task recaps come from the existing activity model. Results are fictional, not a comparison of model quality.

This is a local toy game. Entering or leaving it does not send prompts, run commands, change coding-tool hooks or close coding apps. There is no network multiplayer or sound. Screen sleep pauses the simulation.

## Verification and previews

`./build.sh` runs the self-checks, including 30 seeded battles, collision damage, bounded health/positions/energy, one score per round, rematch resets, shields, cooldowns, dash bounds, deterministic replay, live model/action attribution, work charging, idle drain/damage, approval protection, source warmup and full-width roaming. Label layout tests check ownership, proximity, bounds and non-overlap in both spread-out and crowded arrangements.

Capture a reproducible native strip after building:

```sh
"Touch Bar Playground.app/Contents/MacOS/TouchBarPlayground" --render-battle arena.png --at 4
```

Add `--example-live` to use clearly labelled example model names, working and idle states without reading real sessions. Without it, the render command is a neutral practice fixture.

Launch straight into a fresh live-linked game:

```sh
open "Touch Bar Playground.app" --args --battle
```

If an instance is already open, use its Battle button instead; a second instance activates the existing app.
