---
name: notes-to-md
description: Convert photos or scans of handwritten notes into a clean markdown file, on macOS only. Use when the user asks to convert, transcribe, or turn handwritten notes, notebook pages, whiteboard photos, or scanned pages (HEIC, JPG, PNG, PDF) into markdown or text. Text recognition runs locally with Apple Vision, so Claude only reads the recognized text and never the images. Works well on neat or average handwriting; messy handwriting will come out with many [unclear] lines.
---

# notes-to-md

Turns photos of handwritten notes into one markdown file. Apple's Vision framework does the cropping and text recognition on the Mac. You only ever read the text it produces.

## Hard rules

- **Never open, Read, or view any image or PDF** in this workflow: not the originals, not the processed `page-NNN.jpg` files. Not to check a page, not to fix a bad one. If a page comes out unreadable, report it and move on.
- Never modify, move, or delete the user's original files.
- Never guess at words. If a word or line is not certain, it stays `[unclear]`.
- Never add content that is not in the notes: no summaries, no explanations, no filled-in gaps.
- macOS only. If `uname` is not `Darwin`, stop and say the skill needs macOS.

## Step 1 and 2: run the local script

The script is `scripts/notes_ocr.swift` in this skill's folder. It needs the Xcode Command Line Tools (`swift`). If `swift` is missing, tell the user to run `xcode-select --install` and stop.

```bash
WORK=$(mktemp -d -t notes-to-md)
swift "<skill dir>/scripts/notes_ocr.swift" "<input file or folder>" "$WORK"
```

Options, only when the user asks for them:
- `--threshold 0.5` confidence cutoff below which a line is tagged `[unclear]`
- `--long-side 2000` pixel size of the long side of each processed page
- `--langs en-US` comma-separated recognition languages, for example `en-US,fr-FR`

The script prints one line per page (lines found, unclear count, mean confidence, whether the page was cropped, and `MOSTLY UNREADABLE` when half or more of the lines are unclear). It writes into `$WORK`:
- `page-NNN.txt` recognized text, top to bottom. Low-confidence lines start with `[unclear] `.
- `page-NNN.json` per-line confidence scores (you normally do not need these)
- `page-NNN.jpg` processed page images (never open these)
- `manifest.json` per-page stats

## Step 3: format into markdown

Read all the text files in one call, for example `cat "$WORK"/page-*.txt` with a separator between pages. Read nothing else from `$WORK` except `manifest.json` if needed.

Turn the raw text into markdown:
- Use headings, bullet lists, numbered lists, and tables only where the structure is obvious from the text.
- Fix a recognition slip only when the right word is certain from context. Example: `I. draft budget` right before `2. send to Sam` is clearly `1.`. If there is any doubt, leave it as it is.
- A line tagged `[unclear]` keeps the tag and Vision's raw text exactly as given, for example `[unclear] gr0cery lst`. Do not correct or reword these lines.
- Keep pages in the order the script numbered them. Start each page with `## Page N`. If a page's notes have their own title, make it a `###` heading under the page marker.
- A page marked `MOSTLY UNREADABLE` still gets its `## Page N` marker. Put its raw lines under it as they are, followed by `*This page was mostly unreadable.*`

Begin the file with a `# Title` line using the output file's name in readable form (for example `lecture-3` becomes `# Lecture 3`), unless the user gave a title.

## Where to save

One `.md` per run, saved next to the input unless the user gives another path or title:
- Folder input `~/Notes/lecture-3/` saves as `~/Notes/lecture-3.md`
- File input `~/Downloads/IMG_1234.heic` saves as `~/Downloads/IMG_1234.md`

If the file already exists, do not overwrite it. Add `-2`, `-3`, and so on to the name.

## Step 4: report

End with a short summary:
- Pages processed (and any files the script skipped)
- Number of `[unclear]` lines and which pages they are on
- Pages that were mostly unreadable
- Where the `.md` file was saved
- This line, every run: "Recognition is reliable on neat and average handwriting. Messy handwriting shows up as [unclear] lines, which are left as-is and never guessed."
