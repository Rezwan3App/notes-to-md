<p align="center">
  <img src="assets/icon.png" width="128" alt="notes-to-md icon">
</p>

<h1 align="center">notes-to-md</h1>

<p align="center">
  Snap a photo of your handwritten notes. Get a clean markdown file back.<br>
  A <a href="https://claude.com/claude-code">Claude Code</a> skill for macOS.
</p>

---

## What it does

You point Claude Code at a photo, a folder of photos, or a scanned PDF, and you get back one tidy `.md` file with headings, lists, and tables where your notes had them.

Your Mac does all the image work. Apple's Vision framework (the engine behind Live Text) finds the page in each photo, straightens it, and reads the handwriting on-device. Claude only sees the recognized text, never your photos. That keeps it cheap on tokens and keeps your images on your Mac.

```
~/Notes/lecture-3/            ~/Notes/lecture-3.md
├── IMG_2041.HEIC     ──►      # Lecture 3
├── IMG_2042.HEIC              ## Page 1
└── IMG_2043.HEIC              - Photosynthesis happens in the chloroplast
                               - [unclear] light dep. rxns
                               ...
```

Your original photos are never changed.

## Good to know before you start

- **Mac only.** The skill runs on macOS 13 (Ventura) or newer. It doesn't run on Windows, Linux, iPhone, or Android. Your iPhone works great as the camera, though (see below).
- **Messy handwriting won't come out well.** Lines the Mac isn't confident about are marked `[unclear]` and left exactly as recognized. Claude never guesses or fills in missing words.
- **Neat and average handwriting works well**, and so does printed text.

## Install on a Mac

You need three things: Claude Code, Apple's command line tools, and this skill.

### 1. Install Claude Code

If you don't have it yet, follow the [Claude Code setup guide](https://docs.claude.com/en/docs/claude-code/setup).

### 2. Install Apple's command line tools

These give your Mac the `swift` command that runs the script. Open **Terminal** and run:

```bash
xcode-select --install
```

A window pops up. Click **Install** and wait a few minutes. If it says the tools are already installed, you're set.

Check that it worked:

```bash
swift --version
```

You should see a line starting with `Apple Swift version`.

### 3. Add the skill

**Option A: with git (easiest to update later)**

```bash
git clone https://github.com/Rezwan3App/notes-to-md.git ~/.claude/skills/notes-to-md
```

To update later:

```bash
git -C ~/.claude/skills/notes-to-md pull
```

**Option B: without git**

1. On this page, click the green **Code** button, then **Download ZIP**.
2. Unzip it. You'll get a folder called `notes-to-md-main`.
3. Rename it to `notes-to-md`.
4. In Finder, press **Cmd + Shift + G**, type `~/.claude/skills`, and press Return. If the folder doesn't exist, create it first:

   ```bash
   mkdir -p ~/.claude/skills
   ```

5. Drag the `notes-to-md` folder in there.

When you're done, this file should exist:

```
~/.claude/skills/notes-to-md/SKILL.md
```

### 4. Try it

Restart Claude Code, then ask:

> convert my handwritten notes in ~/Downloads/lecture-3 to markdown

The first run takes a few extra seconds while Swift compiles the script.

## Using it with your iPhone

The skill runs on the Mac, but your iPhone is the best way to capture notes. Take photos, then get them onto your Mac in whichever way you like:

| Method | How |
| --- | --- |
| **AirDrop** | Select the photos, tap Share, pick your Mac. They land in `~/Downloads`. |
| **iCloud Photos** | In Photos on the Mac, select the pictures and drag them into a folder. |
| **Scan Documents** (recommended) | In the **Notes** or **Files** app, tap the camera or ••• menu, choose **Scan Documents**. The iPhone flattens and crops each page for you. Save as a PDF to iCloud Drive and point the skill at that PDF. |
| **Shortcuts inbox** | Make a Shortcut that takes photos and uses **Save File** to put them in an iCloud Drive folder such as `Notes Inbox`. On your Mac that folder is at `~/Library/Mobile Documents/com~apple~CloudDocs/Notes Inbox`. |

Then on the Mac:

> convert the notes in my iCloud Drive Notes Inbox folder to markdown

If you start Claude Code sessions from your phone that run on your Mac, the skill works there too, because the work still happens on the Mac.

## Tips for better results

- Shoot straight on with even light. Avoid shadows across the page.
- Fill most of the frame with the page, and leave a little background around the edges so the page can be detected.
- Dark pen on plain or lightly ruled paper reads best. Pencil and colored paper are harder.
- One page per photo.
- Name your photos in page order (`01.jpg`, `02.jpg`, ...) if order matters. Files are processed in Finder name order.

## What you get

- **One `.md` file** saved next to your input. A folder called `lecture-3` becomes `lecture-3.md` beside it. A single photo `IMG_1234.heic` becomes `IMG_1234.md`. Existing files are never overwritten; a `-2` is added instead.
- **A `## Page N` marker** for each page, in filename order.
- **A short report** at the end: how many pages were processed, how many `[unclear]` lines there are and on which pages, which pages were mostly unreadable, and where the file was saved.

You can ask for a different location or title in your request:

> convert ~/Desktop/scans.pdf to markdown and save it in my Obsidian vault as "Chem week 4"

## Settings

Mention these in your request if you want to change them:

| Setting | Default | What it does |
| --- | --- | --- |
| Confidence threshold | `0.5` | Lines below this score are marked `[unclear]`. Raise it to be stricter. |
| Image size | `2000` px | Long side of each processed page. Bigger can help with tiny writing. |
| Languages | `en-US` | For example `en-US,fr-FR`. Vision supports English, French, Italian, German, Spanish, Portuguese, Chinese, Cantonese, Korean, Japanese, Russian, Ukrainian, Thai, Vietnamese, and Arabic. |

## Running the script by itself

You can use the recognition step without Claude:

```bash
swift ~/.claude/skills/notes-to-md/scripts/notes_ocr.swift <photo, folder, or pdf> <output folder>
```

It writes a processed image, a `.txt` file, and a `.json` file with confidence scores for each page, plus a `manifest.json`.

## Troubleshooting

### "swift: command not found"

Run `xcode-select --install` and try again.

### Claude doesn't use the skill

Check that `~/.claude/skills/notes-to-md/SKILL.md` exists, then restart Claude Code. Using the words "handwritten notes" and "markdown" in your request helps.

### A page came out mostly `[unclear]`

Try a sharper photo with better light, or the iPhone's Scan Documents feature. Some handwriting just won't read well, and the skill tells you so instead of guessing.

### Page edges got cut off

Retake the photo with more background visible around the page.

## How it works

1. **Prepare** (on your Mac): detect the page and correct the angle, shrink it to 2,000 px, and convert it to grayscale.
2. **Recognize** (on your Mac): Vision text recognition in accurate mode, with a confidence score for every line.
3. **Format** (Claude): reads only the text files and turns them into markdown, without adding anything that wasn't in your notes.
4. **Report**: a summary of pages, unclear lines, and where the file went.

Only step 3 uses tokens.

## License

MIT. Free to use, change, and share. See [LICENSE](LICENSE).
