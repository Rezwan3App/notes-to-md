#!/bin/bash
# Tests for scripts/notes-ocr. Draws synthetic note pages into a temp folder, runs the script on them,
# and checks the results. Needs macOS with the Xcode Command Line Tools. Run: tests/run_tests.sh
set -u
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"
OCR="$ROOT/scripts/notes-ocr"
T="$(mktemp -d -t notes-to-md-tests)"
trap 'rm -rf "$T"' EXIT
export NOTES_TO_MD_CACHE="$T/cache"
passed=0; failed=0

ok()   { passed=$((passed + 1)); echo "ok    $1"; }
bad()  { failed=$((failed + 1)); echo "FAIL  $1"; }
# check "description" command...: passes when the command succeeds.
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
# Value from manifest.json, for example: field "$OUT" pages.0.source
# Prints nothing when the key is missing (plutil prints its error on stdout).
field() { local v; v="$(plutil -extract "$2" raw -o - "$1/manifest.json" 2>/dev/null)" && echo "$v"; }
# Text of page N (1-based) on one line.
text()  { tr '\n' '|' < "$1/$(printf 'page-%03d.txt' "$2")"; }
# Line number of the first line containing a word.
lineof() { grep -n -i -m1 "$2" "$1" | cut -d: -f1; }
matches() { [[ "$1" == $2 ]]; }
has()   { grep -qi -- "$2" <<< "$1"; }
sums()  { (cd "$T/in" && find . -type f -exec md5 -r {} + | sort); }
originals_unchanged() { check "inputs unchanged after $1" test "$(sums)" = "$BEFORE"; }
# run OUT_NAME args...: runs the script, keeps stdout in $LOG and the exit code in $CODE.
run() { local out="$1"; shift; LOG="$("$OCR" "$@" 2>&1)"; CODE=$?; }

echo "making fixtures..."
swift tests/make_fixtures.swift "$T/fx" || { echo "could not make fixtures"; exit 1; }
FX="$T/fx"; IN="$T/in"
mkdir -p "$IN/mixed" "$IN/columns" "$IN/empty" "$IN/only-text" "$IN/only-corrupt" "$IN/order"
sips -s format heic "$FX/heic-source.jpg" --out "$IN/mixed/castle.HEIC" >/dev/null
sips -s format tiff "$FX/tiff-source.jpg" --out "$IN/mixed/forest.tiff" >/dev/null
(cd "$FX" && cp 1.jpg 2.jpg 10.jpg scan.pdf locked.pdf clear.png rotated.jpg upper.JPG blank.jpg tiny.jpg \
    name\ with\ spaces*.jpg "$IN/mixed/")
head -c 5000 /dev/urandom > "$IN/mixed/corrupt.jpg"
echo "not a picture" > "$IN/mixed/notes.txt"
head -c 3000 /dev/urandom > "$IN/mixed/clip.mov"
mkdir "$IN/mixed/folder.jpg"
cp "$FX"/two-columns.jpg "$FX"/margin-notes.jpg "$FX"/margin-busy.jpg "$FX"/indented.jpg "$FX"/table.jpg "$IN/columns/"
cp "$FX/huge.jpg" "$IN/"
cp "$FX/1.jpg" "$FX/2.jpg" "$FX/10.jpg" "$IN/order/"
echo "hello" > "$IN/only-text/a.txt"
head -c 2000 /dev/urandom > "$IN/only-corrupt/bad.jpg"
mkdir -p "$IN/wrapped" && cp "$FX/wrapped.jpg" "$IN/wrapped/"
BEFORE="$(sums)"

echo "two runs at once with an empty cache (both compile)..."
"$OCR" "$IN/order" "$T/par1" > "$T/par1.log" 2>&1 & p1=$!
"$OCR" "$IN/order" "$T/par2" > "$T/par2.log" 2>&1 & p2=$!
wait $p1; c1=$?; wait $p2; c2=$?
check "parallel run 1 succeeds" test $c1 -eq 0
check "parallel run 2 succeeds" test $c2 -eq 0
check "parallel runs give the same text" diff "$T/par1/page-001.txt" "$T/par2/page-001.txt"
check "one cached binary, no temp files left" test "$(ls -A "$NOTES_TO_MD_CACHE" | wc -l | tr -d ' ')" -eq 1
check "page order 1, 2, 10" test "$(field "$T/par1" pages.0.source),$(field "$T/par1" pages.1.source),$(field "$T/par1" pages.2.source)" = "1.jpg,2.jpg,10.jpg"

echo "mixed folder..."
OUT="$T/out mixed/new folder"
run "$OUT" "$IN/mixed" "$OUT"
check "mixed folder: exit 0" test "$CODE" -eq 0
check "output folder that did not exist is created" test -f "$OUT/manifest.json"
order=""
for i in $(seq 0 12); do order="$order$(field "$OUT" pages.$i.source)$(field "$OUT" pages.$i.pdfPage)/"; done
# The accented name may come back in either Unicode form, so match it with a wildcard.
check "mixed folder: Finder name order, PDF pages in order" matches "$order" \
    "1.jpg/2.jpg/10.jpg/blank.jpg/castle.HEIC/clear.png/forest.tiff/name with spaces *.jpg/rotated.jpg/scan.pdf1/scan.pdf2/tiny.jpg/upper.JPG/"
check "mixed folder: 13 pages, no more" test "$(field "$OUT" pages.13.source)" = ""
check "JPG text"                  has "$(text "$OUT" 1)" "about apple"
check "10.jpg comes after 2.jpg"  has "$(text "$OUT" 3)" "about cherry"
check "blank page: NO TEXT FOUND" has "$LOG" "blank.jpg .*NO TEXT FOUND"
check "blank page left out of the printed text" test "$(grep -c -- '--- page 4 ---' <<< "$LOG")" -eq 0
check "text printed by default"   has "$LOG" "--- page 5 ---"
check "HEIC, uppercase extension" has "$(text "$OUT" 5)" "about castle"
check "PNG with transparency"     has "$(text "$OUT" 6)" "about pencil"
check "TIFF"                      has "$(text "$OUT" 7)" "about forest"
check "spaces and accents in name" has "$(text "$OUT" 8)" "about window"
check "EXIF rotation: text read"  has "$(text "$OUT" 9)" "^Notes about turtle|remember"
check "EXIF rotation: page upright" test "$(sips -g pixelHeight "$OUT/page-009.jpg" | awk '/pixelHeight/{print $2}')" -gt \
    "$(sips -g pixelWidth "$OUT/page-009.jpg" | awk '/pixelWidth/{print $2}')"
check "PDF page 1"                has "$(text "$OUT" 10)" "about dolphin"
check "PDF page 2"                has "$(text "$OUT" 11)" "about lantern"
check "tiny 50x50 image does not break the run" test "$(field "$OUT" pages.11.source)" = "tiny.jpg"
check "uppercase .JPG"            has "$(text "$OUT" 13)" "about garden"
check "corrupt jpg and locked PDF reported as skipped" has "$LOG" "skipped (could not open): corrupt.jpg, locked.pdf"
check "txt, mov and subfolders reported as ignored" has "$LOG" "ignored (not a supported type): clip.mov, folder.jpg, notes.txt$"
check "manifest lists ignored files" test "$(field "$OUT" ignored.2)" = "notes.txt"
originals_unchanged "mixed folder"

echo "stale pages..."
run "$OUT" "$IN/mixed/1.jpg" "$OUT"
check "rerun into old output folder: exit 0" test "$CODE" -eq 0
check "old pages removed (only page-001 left)" test "$(ls "$OUT" | grep -c '^page-')" -eq 3
check "manifest has 1 page" test "$(field "$OUT" pages.1.source)" = ""

echo "two columns..."
OUT="$T/out-columns"
run "$OUT" "$IN/columns" "$OUT"
check "columns folder: exit 0" test "$CODE" -eq 0
p() { echo "$OUT/$(printf 'page-%03d.txt' "$1")"; }   # 1 indented, 2 margin-busy, 3 margin-notes, 4 table, 5 two-columns
check "two-column page reported as 2 columns" has "$LOG" "two-columns.jpg .*2 columns"
check "two-column page: manifest columns=2" test "$(field "$OUT" pages.4.columns)" = "2"
f="$(p 5)"
check "two-column page: title first" test "$(lineof "$f" "Weekly Reading")" = "1"
check "two-column page: whole left column before right column" test \
    "$(lineof "$f" "morning class")" -lt "$(lineof "$f" "kitchen herbs")" -a \
    "$(lineof "$f" "kitchen herbs")" -lt "$(lineof "$f" "river water")" -a \
    "$(lineof "$f" "river water")" -lt "$(lineof "$f" "ocean tides")"
check "only the two-column page is split" test "$(grep -c '2 columns' <<< "$LOG")" -eq 1
check "margin notes stay beside their line" test "$(lineof "$(p 3)" "urgent")" -eq $(( $(lineof "$(p 3)" "budget is too high") + 1 ))
check "busy margin notes stay beside their line" test "$(lineof "$(p 2)" "ask Kim")" -eq $(( $(lineof "$(p 2)" "check the numbers") + 1 ))
check "indented list keeps its order" test "$(lineof "$(p 1)" "green apples")" -eq $(( $(lineof "$(p 1)" "fruit") + 1 ))
check "table keeps each label with its note" test "$(lineof "$(p 4)" "dentist")" -eq $(( $(lineof "$(p 4)" "Tuesday") + 1 ))
originals_unchanged "columns folder"

echo "wrapped lines..."
run x "$IN/wrapped/wrapped.jpg" "$T/out-wrapped"
f="$T/out-wrapped/page-001.txt"
check "wrapped line joined to the line above" grep -qi "should do when things go wrong" "$f"
check "list items without bullets stay apart" test "$(lineof "$f" "fresh eggs")" -eq $(( $(lineof "$f" "milk and bread") + 1 ))
check "heading not joined to the list" test "$(lineof "$f" "milk and bread")" -eq $(( $(lineof "$f" "Shopping") + 1 ))
check "capitalized line not joined" test "$(lineof "$f" "Tuesday")" -eq $(( $(lineof "$f" "Call the bank") + 1 ))
originals_unchanged "wrapped lines"

echo "--text..."
run x "$IN/order" "$T/out-text" --text
check "--text prints each page after the summary" has "$LOG" "--- page 3 ---"
check "--text output matches the page file" has "$LOG" "about cherry"

echo "very large image..."
OUT="$T/out-huge"
run "$OUT" "$IN/huge.jpg" "$OUT"
check "8000x6000 image: text read" has "$(text "$OUT" 1)" "about rocket"
check "8000x6000 image: page shrunk to 2000 px" test "$(sips -g pixelWidth "$OUT/page-001.jpg" | awk '/pixelWidth/{print $2}')" -le 2000

echo "errors..."
run x "$IN/empty" "$T/o1";            check "empty folder fails" test "$CODE" -ne 0
check "empty folder: clear message" has "$LOG" "no supported files"
run x "$T/does not exist" "$T/o2";    check "missing input fails" test "$CODE" -ne 0
check "missing input: clear message" has "$LOG" "input not found"
run x "$IN/only-text" "$T/o3";        check "folder with only a .txt fails" test "$CODE" -ne 0
run x "$IN/only-text/a.txt" "$T/o4";  check "single unsupported file fails" test "$CODE" -ne 0
run x "$IN/only-corrupt" "$T/o5";     check "folder with only a corrupt image fails" test "$CODE" -ne 0
check "corrupt only: clear message" has "$LOG" "none of the files could be opened"
mkdir -p "$T/o6"; echo keep > "$T/o6/mine.txt"
run x "$IN/order" "$T/o6";            check "output folder with other files is refused" test "$CODE" -ne 0
check "other files in output folder left alone" test "$(cat "$T/o6/mine.txt")" = "keep"
run x "$IN/order" "$IN/order";        check "output folder same as input is refused" test "$CODE" -ne 0
run x "$IN/order/1.jpg" "$IN/order";  check "output folder holding the input file is refused" test "$CODE" -ne 0
echo x > "$T/o7"
run x "$IN/order" "$T/o7";            check "output path that is a file fails" test "$CODE" -ne 0
run x "$IN/order" "$T/o8" --langs fr-FR; check "removed --langs option is rejected" test "$CODE" -ne 0
run x "$IN/order/1.jpg";              check "input path alone works" test "$CODE" -eq 0
work="$(sed -n 's/^work folder: //p' <<< "$LOG")"
check "input path alone: temp work folder made and printed" test -n "$work" -a -f "$work/page-001.txt"
check "input path alone: text printed" has "$LOG" "about apple"
[ -n "$work" ] && rm -rf "$work"
run x "$IN/order/1.jpg" "$T/o10" --no-text; check "--no-text prints only the summary" test "$(grep -c -- '--- page' <<< "$LOG")" -eq 0
originals_unchanged "error cases"

echo "fallback when compiling fails..."
mkdir -p "$T/fakebin"; printf '#!/bin/sh\nexit 1\n' > "$T/fakebin/swiftc"; chmod +x "$T/fakebin/swiftc"
LOG="$(PATH="$T/fakebin:$PATH" NOTES_TO_MD_CACHE="$T/cache2" "$OCR" "$IN/order/1.jpg" "$T/o9" 2>&1)"; CODE=$?
check "runs with swift when swiftc fails" test "$CODE" -eq 0 -a -f "$T/o9/page-001.txt"
originals_unchanged "fallback"

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
