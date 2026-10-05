<p align="center">
  <img src="assets/icon.png" width="128" alt="notes-to-md icon">
</p>

<h1 align="center">notes-to-md</h1>

<p align="center">
  Turn photos of handwritten notes into a markdown file.<br>
  A <a href="https://claude.com/claude-code">Claude Code</a> skill for macOS.
</p>

---

## What it does

Give Claude Code a photo, a folder of photos, or a scanned PDF. You get back one `.md` file, with headings and lists where your notes had them.

Your Mac reads the handwriting. Apple's Vision framework (the same engine as Live Text) finds the page, straightens it, and recognizes the text on your Mac. Claude only sees that text, never your photos. This uses few tokens, and your images stay on your Mac. Your original files are never changed.

```
~/Notes/lecture-3/            ~/Notes/lecture-3.md
├── IMG_2041.HEIC     ──►      # Lecture 3
├── IMG_2042.HEIC              ## Page 1
└── IMG_2043.HEIC              - Photosynthesis happens in the chloroplast
                               - [unclear] light dep. rxns
                               ...
```

## Limits

- **Mac only.** It needs macOS 13 (Ventura) or newer. It does not run on Windows, Linux, iPhone, or Android. Your iPhone can still be the camera (see below).
- **Messy handwriting does not come out well.** A line is marked `[unclear]` when the Mac is not sure about it, or when it has a word the macOS dictionary does not know. These lines are kept exactly as the Mac read them. Claude never guesses or fills in words.
- **Neat and average handwriting works well.** So does printed text.
- **English only.**

## Install on a Mac

### 1. Install Claude Code

Follow the [Claude Code setup guide](https://docs.claude.com/en/docs/claude-code/setup).

### 2. Install Apple's command line tools

These give your Mac the `swift` command the skill needs. Open **Terminal** and run:

```bash
xcode-select --install
```

Click **Install** in the window that opens. If it says the tools are already installed, you are done. To check:

```bash
swift --version
```

The output should include `Apple Swift version`.

### 3. Add the skill

**Option A: with git**

```bash
git clone https://github.com/Rezwan3App/notes-to-md.git ~/.claude/skills/notes-to-md
```

To update later:

```bash
git -C ~/.claude/skills/notes-to-md pull
```

**Option B: download a ZIP**

1. On this page, click the green **Code** button, then **Download ZIP**.
2. Unzip it and rename the folder from `notes-to-md-main` to `notes-to-md`.
3. Make sure the skills folder exists. In Terminal run `mkdir -p ~/.claude/skills`
4. In Finder, press **Cmd + Shift + G**, type `~/.claude/skills`, and press Return.
5. Drag the `notes-to-md` folder in there.

This file should now exist: `~/.claude/skills/notes-to-md/SKILL.md`

### 4. Try it

Restart Claude Code and ask:

> turn my handwritten notes in ~/Downloads/lecture-3 into markdown

The first run takes a few extra seconds to compile the script. After that the compiled program is reused, so later runs start in about a second.

## Using your iPhone

The skill runs on the Mac. Your iPhone is the camera. Get the pictures onto your Mac in any of these ways:

| Method | How |
| --- | --- |
| **Scan Documents** (recommended) | In the **Notes** or **Files** app, choose **Scan Documents**. The iPhone crops and flattens each page. Save the PDF to iCloud Drive and give the skill that PDF. |
| **AirDrop** | Select the photos, tap Share, and pick your Mac. They arrive in `~/Downloads`. |
| **iCloud Photos** | In Photos on the Mac, drag the pictures into a folder. |
| **Shortcuts inbox** | Make a Shortcut that takes photos and uses **Save File** to put them in an iCloud Drive folder, for example `Notes Inbox`. On the Mac it is at `~/Library/Mobile Documents/com~apple~CloudDocs/Notes Inbox`. |

Then ask Claude Code on your Mac:

> convert the notes in my iCloud Drive Notes Inbox folder to markdown

## Tips

- Shoot straight on, in even light, with no shadow across the page.
- Let the page fill most of the photo, with a little background around the edges.
- Dark pen on plain or lightly ruled paper reads best. Pencil and colored paper are harder.
- One page per photo. Name photos in page order (`01.jpg`, `02.jpg`) because files are read in Finder name order.
- Two-column pages are supported. When the rows line up across the page, the left column is read first, then the right.
- A line that runs out of room and carries on below is joined back into one line.

## What you get

- One `.md` file next to your input. A folder `lecture-3` becomes `lecture-3.md`. A photo `IMG_1234.heic` becomes `IMG_1234.md`. An existing file is never overwritten. A `-2` is added to the name instead.
- A `## Page N` heading for each page.
- A short report: pages processed, how many `[unclear]` lines and on which pages, pages that were mostly unreadable, and where the file was saved.

You can ask for another place or title:

> convert ~/Desktop/scans.pdf to markdown and save it in my Obsidian vault as "Chem week 4"

If your notes are full of names or jargon, ask Claude to turn off the spell check. Otherwise those words make many lines `[unclear]`.

## Running the script without Claude

```bash
~/.claude/skills/notes-to-md/scripts/notes-ocr <photo, folder, or pdf>
```

It prints a short summary and the text of each page. Blank pages are left out of the text, and lines that ran onto the next line are joined back together. The files it makes (a cleaned-up image, a `.txt`, and a `.json` with confidence scores for each page, plus a `manifest.json`) go into a new temp folder, and the summary shows where. To pick the folder yourself, add it after the input. `--no-text` prints only the summary. The compiled program is cached in `~/Library/Caches/notes-to-md`.

To run the tests (they make their own sample pages):

```bash
~/.claude/skills/notes-to-md/tests/run_tests.sh
```

## Troubleshooting

- **"swift is not installed"** Run `xcode-select --install` and try again.
- **Claude does not use the skill.** Check that `~/.claude/skills/notes-to-md/SKILL.md` exists, then restart Claude Code. Say "handwritten notes" and "markdown" in your request.
- **A page is mostly `[unclear]`.** Retake it sharper and in better light, or use Scan Documents. Some handwriting will not read well, and the skill tells you so instead of guessing.
- **Page edges were cut off.** Retake the photo with more background around the page.

## License

MIT. See [LICENSE](LICENSE).
