#!/usr/bin/env python3
"""Patch the generated React bundle for the pinned v2.4.1 web UI."""

import hashlib
import json
from pathlib import Path
import re
import sys


WEB = Path(__file__).resolve().parent
UPSTREAM_SHA256 = "867d1990b61d87f4b9ff8c5ecb1551c8688135267f32e56e02563f2d3e78fd68"
TEXT = "@TEXT@"
CATALOG_MARKER = "/* AGY_TRANSLATIONS */ {}"
TRANSLATE = "\nfunction __agyT(source) { return window.__agyI18n?.t(source) ?? source; }\n"


def unique_position(content, anchor, label):
    start = content.find(anchor)
    if start < 0 or content.find(anchor, start + 1) >= 0:
        raise ValueError(f"{label}: expected exactly one occurrence of {anchor!r}")
    return start


def replace_unique(content, old, new, label):
    start = unique_position(content, old, label)
    return content[:start] + new + content[start + len(old):]


def localize_literals(content, catalog):
    """Replace the literal inside each audited anchor, leaving its context alone."""
    replacements = []
    for english, entry in catalog.items():
        literal = json.dumps(english, ensure_ascii=False)
        for anchor in entry["anchors"]:
            before, after = anchor.split(TEXT)
            pattern = before + literal + after
            start = unique_position(content, pattern, english) + len(before)
            replacements.append((start, start + len(literal), f"__agyT({literal})"))

    parts = []
    cursor = 0
    for start, end, replacement in sorted(replacements):
        if start < cursor:
            raise ValueError(f"overlapping translation anchors at offset {start}")
        parts.extend((content[cursor:start], replacement))
        cursor = end
    parts.append(content[cursor:])
    return "".join(parts)


def patch_settings(content):
    # v2.4.1's Appearance component. Keep the host's Desktop Mode toggle and
    # add a language picker using the same option component as Theme.
    hook = "var C=g!==3,D=g!==2,E=F=>G=>{F===t&&v(G)};"
    desktop_hooks = (
        "var [isDesktop,setIsDesktop]=(0,A.useState)(()=>{"
        "try{if(window.Android&&typeof window.Android.isDesktopMode==='function')return window.Android.isDesktopMode();"
        "return localStorage.getItem('ag_desktop_mode')==='true'}catch(_){return !1}});"
        "var onDesktopToggle=(0,A.useCallback)(v=>{"
        "setIsDesktop(v);try{localStorage.setItem('ag_desktop_mode',String(v));"
        "if(window.Android&&typeof window.Android.setDesktopMode==='function')window.Android.setDesktopMode(v)}catch(_){}},[]);"
    )
    content = replace_unique(content, hook, desktop_hooks + hook, "Appearance hooks")
    theme_rows = re.findall(r'A\.createElement\(YKb,\{label:"Theme",[^\n]*?onSelect:h\}\)', content)
    if len(theme_rows) != 1:
        raise ValueError("Appearance: expected exactly one Theme picker")
    theme = theme_rows[0]
    desktop = (
        'A.createElement(v3,{label:__agyT("Desktop Mode"),'
        'description:__agyT("Use desktop viewport and user agent for the workspace"),'
        'rightElement:A.createElement(dX,{checked:isDesktop,onCheckedChange:onDesktopToggle})})'
    )
    language = (
        'A.createElement(YKb,{label:__agyT("Interface Language"),'
        'description:__agyT("Changing language reloads the interface."),'
        'value:window.__agyI18n?.language??"en",options:["zh-CN","en"],'
        'resolveOptionToLabel:F=>F==="zh-CN"?"简体中文":"English",'
        'onSelect:F=>window.__agyI18n?.setLanguage(F)})'
    )
    return replace_unique(content, theme, f"{theme},{desktop},{language}", "Appearance pickers")


def patch_navigation(content):
    # The labels below render built-in screen names. Leave the route keys,
    # test IDs and the names of user-created workspaces on their original paths.
    replacements = (
        ("gNb({label:a,onClick:b})", "gNb({label:a,displayLabel:c,onClick:b})"),
        ('"flex-1 truncate text-sm text-foreground select-none"},a),A.createElement(W,{name:"chevron_right"',
         '"flex-1 truncate text-sm text-foreground select-none"},c??a),A.createElement(W,{name:"chevron_right"'),
        ("gNb,{key:q,label:q,onClick:", "gNb,{key:q,label:q,displayLabel:__agyT(Geb(q)),onClick:"),
        ("Q3,{key:F,text:F,label:Geb(F),", "Q3,{key:F,text:F,label:__agyT(Geb(F)),"),
        ('["Settings",Geb(a)]', '[__agyT("Settings"),__agyT(Geb(a))]'),
        ('["Workspaces",nr(b)]', '[__agyT("Workspaces"),nr(b)]'),
        ('["Projects",f]:e==="outside-of-project"?["Not in Project","Conversations"]',
         '[__agyT("Projects"),f]:e==="outside-of-project"?[__agyT("Not in Project"),__agyT("Conversations")]'),
    )
    for label in ("Shortcuts", "Provide Feedback", "Conversations"):
        literal = json.dumps(label)
        before = f"Q3,{{text:{literal},"
        content = replace_unique(content, before, before + f"label:__agyT({literal}),", "Settings sidebar")
    for before, after in replacements:
        content = replace_unique(content, before, after, "Settings navigation")
    return content


def patch_main(main_path, boot_path):
    if main_path.resolve() == WEB / "main.js":
        raise ValueError("patch_main.py must target a generated copy of main.js")
    source = main_path.read_text(encoding="utf-8")
    if hashlib.sha256(source.encode("utf-8")).hexdigest() != UPSTREAM_SHA256:
        raise ValueError("unexpected upstream Web bundle; review the localization anchors for this version")
    catalog_path = WEB / "src" / "i18n" / "catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))

    patched = patch_settings(source)
    patched = localize_literals(patched, catalog)
    patched = patch_navigation(patched)
    translations = {english: entry["zh"] for english, entry in catalog.items()}
    boot = replace_unique(boot_path.read_text(encoding="utf-8"), CATALOG_MARKER,
                          json.dumps(translations, ensure_ascii=False, indent=2), "language catalog")

    main_path.write_text(patched + TRANSLATE, encoding="utf-8", newline="\n")
    boot_path.write_text(boot, encoding="utf-8", newline="\n")
    print(f"[web-patch] Added the Appearance language picker and {len(catalog)} Chinese strings")


if __name__ == "__main__":
    try:
        main = Path(sys.argv[1]) if len(sys.argv) > 1 else WEB / "generated" / "main.js"
        patch_main(main, main.parent / "boot" / "i18n.js")
    except (OSError, ValueError) as error:
        sys.exit(f"[web-patch] {error}")
