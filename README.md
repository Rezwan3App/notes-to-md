<p align="center">
  <img src="assets/icon.png" width="128" alt="notes-to-md icon">
</p>

<h1 align="center">notes-to-md</h1>

<p align="center">
  Turn photos of handwritten notes into a markdown file.<br>
  A <a href="https://claude.com/claude-code">Claude Code</a> skill for macOS and Windows.
</p>

---

## Contents

- [What it does](#what-it-does)
- [Limits](#limits)
- [Install on a Mac](#install-on-a-mac)
- [Install on Windows](#install-on-windows)
- [Usage](#usage)
  - [Using your iPhone](#using-your-iphone)
  - [Tips for better scans](#tips-for-better-scans)
  - [What you get](#what-you-get)
- [Running without Claude](#running-the-script-without-claude)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## What it does

Give Claude Code a photo, a folder of photos, or a scanned PDF. You get back one `.md` file, with headings and lists where your notes had them.

Your computer reads the handwriting locally. On Mac, Apple's Vision framework (the same engine as Live Text) recognizes the text. On Windows, Tesseract OCR does the same job. Claude only sees the resulting text, never your photos. Your original files are never changed.

```
~/Notes/lecture-3/            ~/Notes/lecture-3.md
├── IMG_2041.HEIC     ──►      # Lecture 3
├── IMG_2042.HEIC              ## Page 1
└── IMG_2043.HEIC              - Photosynthesis happens in the chloroplast
                               - [unclear] light dep. rxns
                               ...
```

## Limits

| | |
| --- | --- |
| **Messy handwriting** | Comes out marked `[unclear]` rather than guessed. These lines are kept exactly as the OCR engine read them — Claude never guesses or fills in words. |
| **Neat handwriting & printed text** | Both work well. |
| **Language** | English only. |
| **HEIC on Windows** | Needs the optional `pillow-heif` package (see install instructions). |
| **Two-column layout** | Detected automatically on Mac. On Windows, columns are read row by row. |

## Install on a Mac

### 1. Install Claude Code

Follow the [Claude Code setup guide](https://docs.claude.com/en/docs/claude-code/setup).

### 2. Run the installer

Download this repo as a ZIP (green **Code** button → **Download ZIP**), unzip it, then in Terminal:

```bash
bash ~/Downloads/notes-to-md-main/install.sh
```

If Swift isn't installed yet the script opens the Xcode tools dialog for you — click Install, wait for it to finish, then run the script again. That's it, skip to step 3.

<details>
<summary>Manual install (no script)</summary>

### Install Apple's command line tools

These give your Mac the `swift` command the skill needs. Open **Terminal** and run:

```bash
xcode-select --install
```

Click **Install** in the window that opens. If it says the tools are already installed, you're done. To check:

```bash
swift --version
```

The output should include `Apple Swift version`.

### 3. Add the skill

**Option A — with git**

```bash
git clone https://github.com/Rezwan3App/notes-to-md.git ~/.claude/skills/notes-to-md
```

To update later:

```bash
git -C ~/.claude/skills/notes-to-md pull
```

**Option B — download a ZIP**

1. On this page, click the green **Code** button, then **Download ZIP**.
2. Unzip it and rename the folder from `notes-to-md-main` to `notes-to-md`.
3. Make sure the skills folder exists. In Terminal run `mkdir -p ~/.claude/skills`.
4. In Finder, press **Cmd + Shift + G**, type `~/.claude/skills`, and press Return.
5. Drag the `notes-to-md` folder in there.

This file should now exist: `~/.claude/skills/notes-to-md/SKILL.md`

</details>

### 3. Try it

Restart Claude Code and ask:

> turn my handwritten notes in ~/Downloads/lecture-3 into markdown

The first run takes a few extra seconds to compile the script. After that, the compiled program is reused, so later runs start in about a second.

---

## Install on Windows

### 1. Install Claude Code

Follow the [Claude Code setup guide](https://docs.claude.com/en/docs/claude-code/setup).

### 2. Run the installer

Download this repo as a ZIP (green **Code** button → **Download ZIP**), unzip it, then **double-click `install.bat`**.

It automatically installs Python, Tesseract OCR, and the required packages — then copies the skill into place. Takes about 2 minutes on a fresh machine.

> **Tip:** If Windows asks "Do you want to allow this app to make changes?" click Yes — the installer needs it to install software.

That's it, skip to step 3.

<details>
<summary>Manual install (no script)</summary>

### Install Python

Download Python 3.10 or newer from [python.org](https://www.python.org/downloads/windows/).

During install, **check the box that says "Add Python to PATH"** — this is unchecked by default.

To confirm it worked, open a terminal and run:

```powershell
python --version
```

### 3. Install Tesseract OCR

Download the Windows installer from the [Tesseract at UB Mannheim page](https://github.com/UB-Mannheim/tesseract/wiki). Run it and accept the defaults.

Tesseract installs to `C:\Program Files\Tesseract-OCR` by default. The Python script finds it there automatically, so you do not need to add it to PATH manually.

To confirm Tesseract is installed:

```powershell
& "C:\Program Files\Tesseract-OCR\tesseract.exe" --version
```

### 4. Install Python packages

Open a terminal and run:

```powershell
pip install pytesseract pymupdf Pillow
```

If you have iPhone photos in HEIC format, also run:

```powershell
pip install pillow-heif
```

### 5. Add the skill

**Option A — with git**

```powershell
git clone https://github.com/Rezwan3App/notes-to-md.git "$env:USERPROFILE\.claude\skills\notes-to-md"
```

To update later:

```powershell
git -C "$env:USERPROFILE\.claude\skills\notes-to-md" pull
```

**Option B — download a ZIP**

1. On this page, click the green **Code** button, then **Download ZIP**.
2. Unzip it and rename the folder from `notes-to-md-main` to `notes-to-md`.
3. Open File Explorer and navigate to `%USERPROFILE%\.claude\skills`. If that folder doesn't exist, create it.
4. Move the `notes-to-md` folder into it.

This file should now exist: `%USERPROFILE%\.claude\skills\notes-to-md\SKILL.md`

</details>

### 3. Try it

Restart Claude Code and ask:

> turn my handwritten notes in C:\Users\me\Downloads\lecture-3 into markdown

---

## Usage

### Using your iPhone

The skill runs on your computer. Your iPhone is just the camera — get the pictures onto your computer with any of these:

**Mac:**

| Method | How |
| --- | --- |
| **Scan Documents** (recommended) | In the **Notes** or **Files** app, choose **Scan Documents**. The iPhone crops and flattens each page. Save the PDF to iCloud Drive and give the skill that PDF. |
| **AirDrop** | Select the photos, tap Share, and pick your Mac. They arrive in `~/Downloads`. |
| **iCloud Photos** | In Photos on the Mac, drag the pictures into a folder. |

**Windows:**

| Method | How |
| --- | --- |
| **Photos app** | Connect your iPhone with a USB cable. Open the Windows **Photos** app and choose **Import**. |
| **iCloud for Windows** | Install [iCloud for Windows](https://apps.microsoft.com/store/detail/icloud/9PKTQ5699M62) and your photos sync to `%USERPROFILE%\Pictures\iCloud Photos`. |
| **Email or AirDrop to a Mac first** | AirDrop the photos to a nearby Mac, then copy them to a shared folder or USB drive. |

### Tips for better scans

- Shoot straight on, in even light, with no shadow across the page.
- Let the page fill most of the photo, with a little background around the edges.
- Dark pen on plain or lightly ruled paper reads best. Pencil and colored paper are harder.
- One page per photo. Name photos in page order (`01.jpg`, `02.jpg`) — files are read in filename order.
- A line that runs out of room and carries on below is joined back into one line (Mac only).

### What you get

- One `.md` file next to your input. A folder `lecture-3` becomes `lecture-3.md`. A photo `IMG_1234.heic` becomes `IMG_1234.md`. An existing file is never overwritten — a `-2` is added to the name instead.
- A `## Page N` heading for each page.
- A short report: pages processed, how many `[unclear]` lines and on which pages, pages that were mostly unreadable, and where the file was saved.

You can ask for another place or title:

> convert ~/Desktop/scans.pdf to markdown and save it in my Obsidian vault as "Chem week 4"

If your notes are full of names or jargon, ask Claude to turn off the spell check (Mac only) — otherwise those words may mark many lines `[unclear]`.

## Running the script without Claude

**Mac:**

```bash
~/.claude/skills/notes-to-md/scripts/notes-ocr <photo, folder, or pdf>
```

**Windows:**

```powershell
python "$env:USERPROFILE\.claude\skills\notes-to-md\scripts\notes_ocr_windows.py" <photo, folder, or pdf>
```

Both scripts print a short summary and the text of each page. Blank pages are left out of the text. The files they write (a processed image, a `.txt`, and a `.json` per page, plus a `manifest.json`) go into a new temp folder, and the summary shows where.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| **Mac: "swift is not installed"** | Run `xcode-select --install` and try again. |
| **Windows: "Tesseract is not installed"** | Install Tesseract from the [UB Mannheim page](https://github.com/UB-Mannheim/tesseract/wiki) and retry. |
| **Windows: "Missing dependency"** | Run `pip install pytesseract pymupdf Pillow` and retry. |
| **Windows: HEIC file skipped** | Run `pip install pillow-heif` and retry. |
| **Claude doesn't use the skill** | Check that `SKILL.md` exists in the skill folder, then restart Claude Code. Say "handwritten notes" and "markdown" in your request. |
| **A page is mostly `[unclear]`** | Retake it sharper and in better light, or use Scan Documents. Some handwriting won't read well, and the skill tells you so instead of guessing. |
| **Page edges were cut off** | Retake the photo with more background around the page. |

## License

MIT. See [LICENSE](LICENSE).
