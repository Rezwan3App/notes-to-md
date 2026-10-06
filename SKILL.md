---
name: notes-to-md
description: Turn photos or scans of handwritten notes (HEIC, JPG, PNG, TIFF, PDF) into a markdown file on macOS. Use when the user asks to convert, transcribe, or turn handwritten notes, notebook photos, whiteboard pictures, or scanned note PDFs into markdown or text. Text is read locally by Apple Vision, so Claude never views the images.
---

# notes-to-md

## Rules

- Never open, Read, or view any image or PDF, including the `page-NNN.jpg` files the script writes. If a page is unreadable, report it and move on.
- Never change, move, or delete the user's files.
- Never guess. Copy each `[unclear] ...` line exactly, tag included (a list marker in front is fine). Fix any other slip only when the right word is certain (`I. draft` just before `2. send` is `1.`).
- Never add content: no summaries, explanations, or filled gaps.

## Run

```bash
"<this skill's folder>/scripts/notes-ocr" "<input file or folder>"
```

macOS only. If `uname` is not `Darwin`, stop and tell the user this skill needs macOS. It prints one line per page, then each page's text after `--- page N ---` (blank pages are left out). That output is all you read. Lines that wrapped onto the next line are already joined. If it says swift is missing, tell the user to run `xcode-select --install` and stop. The first run takes a few seconds to compile. Add `--no-spellcheck` only if the user says the notes are full of names or jargon (the spell check tags lines with unknown words as `[unclear]`).

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
