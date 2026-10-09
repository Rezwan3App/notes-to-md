---
name: notes-to-md
description: Turn photos or scans of handwritten notes (HEIC, JPG, PNG, TIFF, PDF) into a markdown file. Works on macOS (Apple Vision, on-device) and Windows (Tesseract, on-device). Use when the user asks to convert, transcribe, digitize, extract, or turn handwritten notes, notebook photos, whiteboard pictures, lecture notes photos, or scanned note PDFs into markdown or text. Also use when they say "make my notes searchable", "I have a photo of my notes", or "turn my scan into text". Images are processed on-device; Claude never views them.
---

# notes-to-md

## Rules

- Never open, Read, or view any image or PDF, including the `page-NNN.jpg` files the script writes. If a page is unreadable, report it and move on.
- Never change, move, or delete the user's files.
- Never guess. Copy each `[unclear] ...` line exactly, tag included (a list marker in front is fine). Fix any other slip only when the right word is certain (`I. draft` just before `2. send` is `1.`).
- Never add content: no summaries, explanations, or filled gaps.

## Run

Detect the OS first, then run the matching script.

**macOS** — check with `uname -s` (returns `Darwin`):

```bash
"<this skill's folder>/scripts/notes-ocr" "<input file or folder>"
```

If `uname` is not `Darwin`, do not use this path. The first run takes a few seconds to compile; later runs start in about a second. If it says swift is missing, tell the user to run `xcode-select --install` and stop. Add `--no-spellcheck` only if the user says the notes are full of names or jargon.

**Windows** — when `uname -s` is not available or does not return `Darwin`:

```powershell
python "<this skill's folder>\scripts\notes_ocr_windows.py" "<input file or folder>"
```

If `python` is not found, try `python3`. If Tesseract is missing, the script prints a clear error with the installer link — stop and show that message to the user. The `--no-spellcheck` flag is accepted but has no effect on Windows (Tesseract does not use a dictionary).

**Neither macOS nor Windows:** stop and tell the user this skill supports macOS and Windows only.

The script prints one summary line per page, then each page's text after `--- page N ---` (blank pages are left out). That output is all you read. Lines that wrapped onto the next line are already joined.

## Write the markdown

- First line `# Title`: the user's title, or the output file name made readable (`lecture-3` becomes `# Lecture 3`).
- Each page starts with `## Page N`. A title written on the page becomes `###`.
- Use lists, headings, or tables only where the text clearly shows them. Otherwise keep one line per line.
- Escape a `#` or `>` at the start of a note line, for example `\# Muse`.
- Page flags: `MOSTLY UNREADABLE` keeps its raw lines, then `*This page was mostly unreadable.*`. `NO TEXT FOUND` gets `*No text found on this page.*`. `RECOGNITION FAILED` gets `*Text recognition failed on this page.*`

Save one `.md` next to the input unless the user names a path: folder `~/Notes/lecture-3/` becomes `~/Notes/lecture-3.md`, file `~/Downloads/IMG_1234.heic` becomes `~/Downloads/IMG_1234.md`. If that file exists, add `-2`, `-3`, and so on.

## Report

- Pages processed, and any files listed as skipped or ignored
- Count of `[unclear]` lines, and which pages
- Pages that were mostly unreadable, empty, or failed
- Where the `.md` was saved
- Always end with: "Recognition is reliable on neat and average handwriting. Messy handwriting shows up as [unclear] lines, which are left as-is and never guessed."
