# Pixel Arena

Press **Battle!** in the playground window or choose **Companion battle** from its menu bar icon. The same live-linked game appears in the desktop strip and on the Touch Bar.

The three companions join a friendly, fictional free-for-all. They move, hop over low shots, fire coloured projectiles and lose health on impact. A countdown starts each round. The last fighter standing wins; a 75-second limit resolves a stalled round by remaining health. Winners celebrate, keep their score, and start a fresh round after six seconds.

## Controls and readable information

- **Tap a fighter:** select it, cheer it with a 0.9-second shield, and fire a two-shot special. Specials have a two-second cooldown.
- **Tap empty arena ground:** your selected fighter dashes toward it and fires. Dashes have a one-second cooldown shared with specials.
- **Tap LIVE at the right:** return to live coding activity. The window's **Live activity** button does the same.
- **Health and energy:** coloured health bars above each fighter, with a thinner mint energy bar beneath.
- **Attached labels:** each avatar carries its own name, model and action. Its label stays next to it, connected by a short matching-colour tether. Name/HP/energy occupy the first line when space permits; the model and action use the next two lines. Long text truncates inside its space. During close passes, details collapse to a tiny owner badge rather than jumping elsewhere or covering another fighter. The desktop window always shows all three tools' full live details and game stats in fixed cards.
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

## Co-op bug boss (v1.6)

Choose **Bug boss** beside Battle, or launch with `--boss`. The companions form a party and shoot a shared pixel bug; party projectiles cannot hurt companions. The bug has a separate red health bar, telegraphs an incoming attack with `!`, and turns yellow while a scan exposes its weak spot. Its HP or current combo multiplier appears below it.

Fresh reported work actions trigger moves:

| Reported action | Game move |
| --- | --- |
| Reading, searching, checking the screen | SCAN: expose the bug for four seconds |
| Editing | PATCH SHIELD: protect that companion for two seconds |
| Building | FORTIFY: briefly shield the whole party |
| Running a command | TERMINAL BOLT: fire a stronger shot |
| Starting tests | CHARGING |
| Completing tests with a known passing result | TEST FINISHER: a larger projectile strengthened by the current chain |
| Replying or completing a task | RALLY: restore a small amount of party health |

Moves chain for six seconds between actions, up to ×9. Duplicate polls, first-observed historical state, stale events, unknown test outcomes, failed actions and approval waits do not manufacture abilities. A previous test pass retained for a completion recap is distinct from the current test result. Known current passes can trigger the finisher even when a short test completes within the normal ability cooldown.

Health now drains more slowly in both modes: incoming companion hit damage is approximately one fifth of the previous setting, with a minimum of one HP and the existing idle multipliers. Ordinary shots fire less frequently. The duel timeout is 75 seconds and the boss timeout is 90 seconds. A first-wave bug has 600 HP and reduces incoming party damage; later waves increase its health up to 840. This supports a longer encounter while leaving meaningful boosts from live work and taps.

At the end of either mode, a sports-style scoreboard slides in. It announces the winner, increments the series score, adds pixel confetti and a next-round countdown, then slides away. Celebrations last six seconds before the next countdown starts. Avatar labels no longer carry win/loss counts; the scoreboard is the place for series scores. The LIVE exit remains accessible at the right throughout.

Additional self-checks cover twelve boss encounters with both outcomes, no party friendly fire, fresh-action abilities, deduplication, old/unknown/failed-result guards, combo chains, encounter scores, wave resets and slower early health loss.

### Boss challenge and identity

The boss uses a beetle silhouette with split wing armour, jointed stepping legs, antennae, bright eyes and a persistent **BUG** label. Its shell stays coloured when hit; the edge flashes instead of turning the whole creature into a white block. Scanning reveals its weak spot, and its low-health phase turns the shell orange.

The bug alternates aimed attacks with a telegraphed two-direction spread. Below 30% health, its attacks become faster and its spread more frequent. One projectile is spawned per direction, avoiding an invisible stack of hits when companions stand together. Boss hits are stronger than ordinary companion shots, while the slower duel balance stays unchanged.

Boss health and attack strength scale with party victories, not with losses. Losing therefore allows another attempt at the same difficulty. Balance checks include engaged parties using shields and an unattended party with two working tools and one sleeping companion, alongside the current-action and scoring guards.
