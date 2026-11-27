# Pixel Arena

Press **Battle!** in the playground window or choose **Companion battle** from its menu bar icon. The same game appears in the desktop strip and on the Touch Bar.

All three companions join a friendly, fictional free-for-all. They move, hop over low shots, fire coloured projectiles and lose health on impact. A short countdown starts each round. The last fighter standing wins; a 35-second limit resolves a stalled round by remaining health. Winners celebrate, keep a score, and start a fresh round after four seconds.

- **Tap a fighter:** select it, cheer it with a 0.9-second shield, and fire a two-shot special. Specials have a two-second cooldown.
- **Tap empty arena ground:** your selected fighter dashes toward it and fires. Dashes have a one-second cooldown shared with specials.
- **Tap LIVE at the right:** leave the game and return to live coding activity. The window's **Live activity** button does the same.
- **Health:** small coloured bars above each fighter. Defeated fighters blink until the next round.
- **Score:** the three counts at the left follow Codex / Claude / Antigravity order. Full names, health and wins are shown in the desktop window.

This is a local toy game. Its results are unrelated to model quality, task performance or tool activity. Entering or leaving the arena does not send prompts, run commands, modify coding-tool hooks or close coding apps. There is no network multiplayer or sound. The screen sleep notification pauses the game with the rest of the app.

## Verification

`./build.sh` runs the self-checks, including 30 seeded autonomous battles, real collision damage, valid health/positions, one score per round, rematch resets, shield activation, cooldowns, bounded dash movement and reproducible simulation.

Capture a reproducible native strip after building:

```sh
"Touch Bar Playground.app/Contents/MacOS/TouchBarPlayground" --render-battle arena.png --at 4
```

Launch straight into a fresh game:

```sh
open "Touch Bar Playground.app" --args --battle
```

If an instance is already open, use its Battle button instead; a second instance only activates the existing app.
