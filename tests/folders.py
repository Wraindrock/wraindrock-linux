#!/usr/bin/env python3
"""Assert the app-folder definition gives every app exactly one home.

GNOME Shell shows an app in every folder whose `apps` or `categories` match
it, minus `excluded-apps`. Wraindrock's drop-in no longer merges the upstream
fleet: it defines the complete folder set, uses only explicit apps lists, and
keeps those lists disjoint. This script checks those invariants on the
generated file (or on an image copy passed by parity).
"""

import re
import sys

SECTION = re.compile(r"^\[(?P<path>.+)]$")
KEY = re.compile(r"^(?P<key>[A-Za-z-]+)=(?P<value>.*)$")
ITEM = re.compile(r"'([^']*)'")


def parse(path):
    entries = {}
    current = None
    for raw in open(path, encoding="utf-8"):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        section = SECTION.match(line)
        if section:
            current = entries.setdefault(section.group("path"), {})
            continue
        key = KEY.match(line)
        if key and current is not None:
            current[key.group("key")] = key.group("value")
    return entries


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: folders.py DCONF_FILE")
    entries = parse(sys.argv[1])
    children = ITEM.findall(entries["org/gnome/desktop/app-folders"]["folder-children"])
    defined = {}
    for path, keys in entries.items():
        match = re.match(r"org/gnome/desktop/app-folders/folders/(.+)$", path)
        if not match:
            continue
        name = match.group(1)
        apps = ITEM.findall(keys.get("apps", ""))
        if not apps:
            sys.exit(f"folder {name} has no apps; empty folders are not allowed")
        if "categories" in keys:
            sys.exit(f"folder {name} uses categories; explicit apps only")
        defined[name] = apps
    if set(children) != set(defined):
        sys.exit(f"folder-children {sorted(children)} != defined {sorted(defined)}")
    seen = {}
    for folder, apps in defined.items():
        for app in apps:
            if app in seen:
                sys.exit(f"{app} is in both {seen[app]} and {folder}")
            seen[app] = folder
    print(f"folders: {len(defined)} folders, {len(seen)} grouped apps, no duplicates")


if __name__ == "__main__":
    main()
