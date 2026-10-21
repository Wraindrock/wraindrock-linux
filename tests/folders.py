#!/usr/bin/env python3
"""Assert that the merged app-folder definition gives each app one home.

GNOME Shell shows an app in every folder where it matches

    (apps ∪ category matches) − excluded-apps

so two folders that both list an app (or one lists it and another matches its
category) show it twice. This test merges Bluefin's upstream definition with
the Wraindrock drop-in and checks the invariant we control:

  * every desktop ID appears in at most one folder once excluded-apps apply;
  * every app we re-home is explicitly excluded from the upstream folder that
    also lists it (categories are not simulated, so this exclusion is what
    prevents a second home);
  * folder-children lists all folders that exist.
"""

import re
import sys

SECTION = re.compile(r"^\[(?P<path>.+)]$")
KEY = re.compile(r"^(?P<key>[A-Za-z-]+)=(?P<value>.*)$")
LIST_ITEM = re.compile(r"'([^']*)'")


def parse(path):
    """Return {schema path: {key: raw value}} for one dconf text file."""
    entries = {}
    current = None
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        match = SECTION.match(line)
        if match:
            current = entries.setdefault(match.group("path"), {})
            continue
        match = KEY.match(line)
        if match and current is not None:
            current[match.group("key")] = match.group("value")
    return entries


def as_list(raw):
    if raw is None:
        return []
    return LIST_ITEM.findall(raw)


def folder_name(path):
    prefix = "org/gnome/desktop/app-folders/folders/"
    return path[len(prefix):] if path.startswith(prefix) else None


def main(upstream_path, ours_path):
    upstream = parse(upstream_path)
    merged = {path: dict(keys) for path, keys in upstream.items()}
    for path, keys in parse(ours_path).items():
        merged.setdefault(path, {}).update(keys)

    folders = {}
    for path, keys in merged.items():
        name = folder_name(path)
        if name is None:
            continue
        folders[name] = {
            "apps": as_list(keys.get("apps")),
            "excluded": as_list(keys.get("excluded-apps")),
        }

    errors = []
    homes = {}
    for folder, data in folders.items():
        for app in set(data["apps"]) - set(data["excluded"]):
            homes.setdefault(app, []).append(folder)

    for app, where in sorted(homes.items()):
        if len(where) > 1:
            errors.append(f"{app} is in more than one folder: {', '.join(sorted(where))}")

    upstream_folders = {}
    for path, keys in upstream.items():
        name = folder_name(path)
        if name is not None:
            upstream_folders[name] = set(as_list(keys.get("apps")))

    for app, where in sorted(homes.items()):
        for folder, apps in upstream_folders.items():
            if folder in where:
                continue
            if app in apps and app not in set(folders[folder]["excluded"]):
                errors.append(
                    f"{app} lives in {', '.join(where)} but upstream {folder} also lists it "
                    "and does not exclude it"
                )

    children = as_list(merged.get("org/gnome/desktop/app-folders", {}).get("folder-children"))
    for name in sorted(folders):
        if name not in children:
            errors.append(f"folder {name} is defined but missing from folder-children")
    for child in children:
        if child not in folders:
            errors.append(f"folder-children names {child}, which has no definition")

    if errors:
        for line in errors:
            print(f"FAIL: {line}")
        return 1
    print(f"folders: {len(folders)} folders, {len(homes)} grouped apps, no duplicates")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <bluefin-folders.conf> <wraindrock-app-folders>", file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(main(sys.argv[1], sys.argv[2]))
