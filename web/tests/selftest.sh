#!/usr/bin/env bash
# Build web assets on a disposable copy and prove upstream main.js stays intact.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${TMPDIR:-${HOME:-.}/.tmp}"
mkdir -p "$TMP_DIR"
TMP="$(mktemp -d "$TMP_DIR/agy-web-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
cp -a "$ROOT/web" "$TMP/web"
before="$(sha256sum "$TMP/web/main.js" | cut -d' ' -f1)"
bash "$TMP/web/build.sh"
after="$(sha256sum "$TMP/web/main.js" | cut -d' ' -f1)"
[ "$before" = "$after" ] || { echo "web/build.sh modified source main.js" >&2; exit 1; }
[ -s "$TMP/web/generated/main.js" ] || { echo "generated/main.js missing" >&2; exit 1; }
grep -Fq 'src="./generated/main.js"' "$TMP/web/index.html"

python3 - "$TMP/web" "${1:-}" <<'PY'
from pathlib import Path
import sys
from zipfile import ZipFile

web = Path(sys.argv[1])
sys.path.insert(0, str(web))
from patch_main import localize_literals

catalog = {"Settings": {"zh": "\u8bbe\u7f6e", "anchors": ["label:@TEXT@,onClick:"]}}
example = 'view({label:"Settings",onClick:open}); chat("Settings")'
assert localize_literals(example, catalog) == (
    'view({label:__agyT("Settings"),onClick:open}); chat("Settings")'
)
for invalid in ('chat("Settings")', example + example):
    try:
        localize_literals(invalid, catalog)
    except ValueError as error:
        assert "exactly one occurrence" in str(error), error
    else:
        raise AssertionError("An invalid anchor should stop the build")

html = (web / "index.html").read_text(encoding="utf-8")
assert html.index("./generated/boot/i18n.js") < html.index("./generated/main.js")
bundle = (web / "generated" / "main.js").read_text(encoding="utf-8")
assert 'Projects:{prefix:["projects:"],hasSections:!1,title:"Projects"}' in bundle
assert 'Conversations:{prefix:["conversations:"],hasSections:!1,title:"Conversations"}' in bundle
if sys.argv[2]:
    with ZipFile(sys.argv[2]) as apk:
        for path in ("index.html", "generated/boot/i18n.js", "generated/main.js"):
            assert apk.read(f"assets/web/{path}") == (web / path).read_bytes(), path
        assert "assets/web/src/i18n/catalog.json" not in apk.namelist()
        assert not any("/__pycache__/" in name for name in apk.namelist())
PY

if command -v node >/dev/null 2>&1; then
    node - "$TMP/web/generated/boot/i18n.js" <<'JS'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const boot = fs.readFileSync(process.argv[2], 'utf8');

for (const [saved, language, label] of [[undefined, 'zh-CN', '\u754c\u9762\u8bed\u8a00'], ['en', 'en', 'Interface Language']]) {
  const calls = [];
  const window = {
    __AG_UI_LANGUAGE__: saved,
    __AG_NATIVE_BRIDGE_TOKEN__: 'fixture-token',
    Android: {setUiLanguage: (...args) => calls.push(args)},
  };
  const document = {documentElement: {}};
  vm.runInNewContext(boot, {window, document});
  const i18n = window.__agyI18n;
  assert.equal(document.documentElement.lang, language);
  assert.equal(i18n.t('Interface Language'), label);
  assert.equal(i18n.t('Welcome to '), language === 'zh-CN' ? '欢迎使用 ' : 'Welcome to ');
  assert.equal(i18n.t('Having trouble signing in?'),
    language === 'zh-CN' ? '登录遇到问题？' : 'Having trouble signing in?');
  assert.equal(i18n.t('No Project'), language === 'zh-CN' ? '无项目' : 'No Project');
  assert.equal(i18n.t('constructor'), 'constructor');
  const other = language === 'en' ? 'zh-CN' : 'en';
  i18n.setLanguage(language);
  i18n.setLanguage('unknown');
  i18n.setLanguage(other);
  assert.deepEqual(calls, [['fixture-token', other]]);
}
JS
fi

# Verify no double IIFE wrappers in generated bundles (excluding vendor main.js)
for f in "$TMP"/web/generated/boot/*.js "$TMP"/web/generated/patches/*.js; do
    [ -f "$f" ] || continue
    if awk '
        BEGIN { iife_opens = 0; in_block = 0 }
        {
            line = $0
            if (in_block) {
                if (line ~ /\*\//) { sub(/^.*\*\//, "", line); in_block = 0 }
                else next
            }
            if (line ~ /\/\*/) { sub(/\/\*.*$/, "", line); in_block = 1 }
            sub(/^[ \t]+/, "", line)
            if (line ~ /^\(function/) iife_opens++
        }
        END { if (iife_opens > 1) exit 0; exit 1 }
    ' "$f"; then
        echo "Double IIFE wrapper detected in $f" >&2
        exit 1
    fi
done

echo "web build selftest: OK"
