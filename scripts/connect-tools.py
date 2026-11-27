#!/usr/bin/env python3
"""Add observational hooks without replacing existing settings or hooks."""
import argparse
import datetime
import json
import pathlib
import shlex
import shutil
import sys

MARKER = "TouchBarPlayground"
HOME_DIR = pathlib.Path.home()
DEFAULT_APP = HOME_DIR / "Applications/Touch Bar Playground.app"


def merge_claude(config, command):
    hooks = config.setdefault("hooks", {})
    for event in ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest", "Notification", "Stop", "SessionEnd"]:
        groups = hooks.setdefault(event, [])
        cleaned = []
        for group in groups:
            group["hooks"] = [h for h in group.get("hooks", []) if MARKER not in h.get("command", "")]
            if group["hooks"]:
                cleaned.append(group)
        groups[:] = cleaned
        group = {"hooks": [{"type": "command", "command": f"{command} --event claude {event}", "timeout": 2}]}
        if event == "Notification":
            group["matcher"] = "permission_prompt|idle_prompt|elicitation_dialog"
        groups.append(group)
    return config


def merge_antigravity(config, command):
    # No PreToolUse hook: the playground never participates in permission decisions.
    config["touchbar-playground"] = {
        "enabled": True,
        "PreInvocation": [{"type": "command", "command": f"{command} --event antigravity PreInvocation", "timeout": 2}],
        "PostToolUse": [{"matcher": ".*", "hooks": [{"type": "command", "command": f"{command} --event antigravity PostToolUse", "timeout": 2}]}],
        "Stop": [{"type": "command", "command": f"{command} --event antigravity Stop", "timeout": 2}],
    }
    return config


def save(path, config):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        backup = path.with_name(path.name + ".playground-backup-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S%f"))
        shutil.copy2(path, backup)
    scratch = path.with_suffix(path.suffix + ".playground-new")
    scratch.write_text(json.dumps(config, indent=2) + "\n")
    scratch.chmod(0o600)
    scratch.replace(path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=pathlib.Path, default=DEFAULT_APP)
    parser.add_argument("--remove", action="store_true")
    args = parser.parse_args()
    binary = args.app / "Contents/MacOS/TouchBarPlayground"
    if not args.remove and not binary.exists():
        sys.exit(f"Build or install the app first: {binary}")
    command = shlex.quote(str(binary))
    targets = [
        (HOME_DIR / ".claude/settings.json", merge_claude),
        (HOME_DIR / ".gemini/config/hooks.json", merge_antigravity),
    ]
    # Parse both files before writing either. Invalid existing config is never overwritten.
    parsed = [(path, merge, json.loads(path.read_text()) if path.exists() else {}) for path, merge in targets]
    for path, merge, config in parsed:
        if args.remove:
            if merge is merge_claude:
                for event, groups in config.get("hooks", {}).items():
                    cleaned = []
                    for group in groups:
                        group["hooks"] = [h for h in group.get("hooks", []) if MARKER not in h.get("command", "")]
                        if group["hooks"]:
                            cleaned.append(group)
                    groups[:] = cleaned
            else:
                config.pop("touchbar-playground", None)
        else:
            merge(config, command)
        save(path, config)
        print(f"{'Disconnected' if args.remove else 'Connected'}: {path}")
    print("Codex uses read-only local activity events; existing notify settings are unchanged.")


if __name__ == "__main__":
    main()
