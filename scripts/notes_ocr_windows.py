#!/usr/bin/env python3
"""
notes_ocr_windows.py  --  OCR handwritten notes on Windows using Tesseract.
Produces the same summary + page text output as the macOS notes-ocr script.

Required:
  Tesseract OCR  https://github.com/UB-Mannheim/tesseract/wiki  (install, add to PATH)
  pip install pytesseract pymupdf Pillow

Optional (HEIC/HEIF from iPhone):
  pip install pillow-heif

Usage:
  python notes_ocr_windows.py <input file or folder> [output folder] [--no-text] [--no-spellcheck]
"""

import json
import re
import sys
import tempfile
import uuid
from pathlib import Path

try:
    import pytesseract
    from PIL import Image
    import fitz  # pymupdf
except ImportError as e:
    print(
        f"Missing dependency: {e}\n"
        "Run: pip install pytesseract pymupdf Pillow\n"
        "Also install Tesseract: https://github.com/UB-Mannheim/tesseract/wiki",
        file=sys.stderr,
    )
    sys.exit(1)

# Try the default Tesseract install path on Windows if it is not on PATH.
if sys.platform == "win32":
    import shutil

    _default = r"C:\Program Files\Tesseract-OCR\tesseract.exe"
    if not shutil.which("tesseract") and Path(_default).is_file():
        pytesseract.pytesseract.tesseract_cmd = _default

SUPPORTED_IMG = {".heic", ".heif", ".jpg", ".jpeg", ".png", ".tif", ".tiff"}
LONG_SIDE = 2000
UNCLEAR_THRESHOLD = 50  # Tesseract 0-100; 50 ≈ Vision's 0.5
MARKER = ".notes-ocr-tmp"
PAGE_RE = re.compile(r"^(page-\d{3,}\.(jpg|txt|json)|manifest\.json|\.notes-ocr-tmp)$")


def fail(msg: str) -> None:
    print(msg, file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

def parse_args():
    args = sys.argv[1:]
    positional = []
    no_text = False

    for a in args:
        if a in ("--no-text",):
            no_text = True
        elif a in ("--no-spellcheck",):
            pass  # accepted but unused; Tesseract has no built-in dictionary check
        elif a.startswith("--"):
            fail(f"unknown option {a}\nusage: notes_ocr_windows.py <input> [output] [--no-text]")
        else:
            positional.append(a)

    if len(positional) not in (1, 2):
        fail("usage: notes_ocr_windows.py <input file or folder> [output folder] [--no-text]")

    inp = Path(positional[0]).expanduser().resolve()
    if len(positional) == 2:
        out = Path(positional[1]).expanduser().resolve()
        made_output = False
    else:
        out = Path(tempfile.gettempdir()) / f"notes-to-md-{str(uuid.uuid4())[:8]}"
        made_output = True

    return inp, out, no_text, made_output


# ---------------------------------------------------------------------------
# Input discovery
# ---------------------------------------------------------------------------

def collect_inputs(inp: Path):
    if not inp.exists():
        fail(f"input not found: {inp}")
    if inp.is_file():
        ext = inp.suffix.lower()
        if ext not in SUPPORTED_IMG and ext != ".pdf":
            fail(f"not a supported file type (HEIC, JPG, PNG, TIFF, or PDF): {inp}")
        return [inp], []

    items = sorted(inp.iterdir(), key=lambda p: p.name.casefold())
    wanted, ignored = [], []
    for f in items:
        if not f.is_file():
            ignored.append(f.name)
            continue
        ext = f.suffix.lower()
        if ext in SUPPORTED_IMG or ext == ".pdf":
            wanted.append(f)
        else:
            ignored.append(f.name)
    return wanted, ignored


# ---------------------------------------------------------------------------
# Output folder management
# ---------------------------------------------------------------------------

def prepare_output(out: Path, inp: Path) -> None:
    inp_dir = inp.parent if inp.is_file() else inp
    if out.resolve() == inp_dir.resolve():
        fail(f"output folder must not be the input folder: {out}")

    if out.exists():
        if not out.is_dir():
            fail(f"output path is a file, not a folder: {out}")
        names = [p.name for p in out.iterdir()]
        if MARKER not in names:
            visible = [n for n in names if n not in (".DS_Store", "Thumbs.db")]
            if visible:
                fail(
                    f"output folder already has other files ({', '.join(visible[:3])}). "
                    "Use a new or empty folder."
                )
            (out / MARKER).touch()
            return
        foreign = [n for n in names if not PAGE_RE.match(n)]
        if foreign:
            fail(
                f"output folder has other files ({', '.join(foreign[:3])}). "
                "Use a new or empty folder."
            )
        for p in out.iterdir():
            if p.name != MARKER:
                p.unlink()
    else:
        out.mkdir(parents=True)
        (out / MARKER).touch()


# ---------------------------------------------------------------------------
# Image helpers
# ---------------------------------------------------------------------------

def resize_to_long_side(img: Image.Image, long_side: int) -> Image.Image:
    w, h = img.size
    longest = max(w, h)
    if longest <= long_side:
        return img
    scale = long_side / longest
    return img.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS)


def open_image(path: Path) -> "Image.Image | None":
    ext = path.suffix.lower()
    if ext in (".heic", ".heif"):
        try:
            import pillow_heif  # noqa: PLC0415

            pillow_heif.register_heif_opener()
        except ImportError:
            print(
                f"Skipping {path.name}: HEIC support needs pillow-heif  "
                "(run: pip install pillow-heif)",
                file=sys.stderr,
            )
            return None
    try:
        img = Image.open(path)
        img.load()
        # Flatten transparency onto white so OCR sees paper, not black.
        if img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info):
            bg = Image.new("RGB", img.size, (255, 255, 255))
            bg.paste(img.convert("RGBA"), mask=img.convert("RGBA").split()[3])
            return bg
        return img.convert("RGB")
    except Exception:
        return None


# ---------------------------------------------------------------------------
# OCR
# ---------------------------------------------------------------------------

def ocr_image(img: Image.Image) -> list[dict]:
    """Return a list of {text, confidence, unclear, suspectWords} dicts, one per line."""
    gray = img.convert("L")
    try:
        data = pytesseract.image_to_data(
            gray,
            lang="eng",
            output_type=pytesseract.Output.DICT,
            config="--oem 1 --psm 6",
        )
    except pytesseract.TesseractNotFoundError:
        fail(
            "Tesseract is not installed or not on PATH.\n"
            "Install from https://github.com/UB-Mannheim/tesseract/wiki\n"
            "Then add it to your PATH or reinstall with 'Add to PATH' checked."
        )
    except Exception as e:
        print(f"OCR error: {e}", file=sys.stderr)
        return []

    # Group words into lines by (block, par, line) key, in reading order (top → left).
    groups: dict[tuple, dict] = {}
    for i, word in enumerate(data["text"]):
        word = word.strip()
        if not word:
            continue
        conf = int(data["conf"][i])
        if conf < 0:  # -1 means the entry is a container, not a word
            continue
        key = (data["block_num"][i], data["par_num"][i], data["line_num"][i])
        if key not in groups:
            groups[key] = {
                "words": [],
                "confs": [],
                "top": data["top"][i],
                "left": data["left"][i],
            }
        groups[key]["words"].append(word)
        groups[key]["confs"].append(conf)

    sorted_groups = sorted(groups.values(), key=lambda g: (g["top"], g["left"]))

    lines = []
    for g in sorted_groups:
        text = " ".join(g["words"])
        conf = min(g["confs"])  # worst word drives the line confidence
        lines.append({
            "text": text,
            "confidence": round(conf / 100, 3),
            "unclear": conf < UNCLEAR_THRESHOLD,
            "suspectWords": [],
        })
    return lines


# ---------------------------------------------------------------------------
# Page processing
# ---------------------------------------------------------------------------

def _process_page(
    img: Image.Image,
    out: Path,
    n: int,
    source: str,
    pdf_page: "int | None",
    stats: list,
    page_texts: list,
    skipped: list,
) -> None:
    base = f"page-{n:03d}"
    label = f"{source} page {pdf_page}" if pdf_page else source

    gray = img.convert("L")
    try:
        gray.save(str(out / f"{base}.jpg"), "JPEG", quality=85)
    except Exception:
        skipped.append(label)
        return

    lines = ocr_image(img)
    text = "\n".join(
        ("[unclear] " + ln["text"] if ln["unclear"] else ln["text"]) for ln in lines
    )

    try:
        (out / f"{base}.txt").write_text(text + "\n", encoding="utf-8")
        (out / f"{base}.json").write_text(json.dumps(lines, indent=2), encoding="utf-8")
    except Exception:
        (out / f"{base}.jpg").unlink(missing_ok=True)
        skipped.append(label)
        return

    unclear_count = sum(1 for ln in lines if ln["unclear"])
    mean_conf = (
        round(sum(ln["confidence"] for ln in lines) / len(lines), 4) if lines else 0.0
    )
    words = sum(len(ln["text"].split()) for ln in lines)
    doubtful = sum(len(ln["text"].split()) for ln in lines if ln["unclear"])
    mostly = words > 0 and doubtful / words >= 0.5

    stats.append({
        "page": n,
        "source": source,
        "pdfPage": pdf_page,
        "documentDetected": False,
        "columns": 1,
        "lines": len(lines),
        "unclearLines": unclear_count,
        "meanConfidence": mean_conf,
        "noText": len(lines) == 0,
        "mostlyUnreadable": mostly,
        "recognitionFailed": False,
        "textFile": f"{base}.txt",
    })
    page_texts.append(text)


def process_pdf(
    path: Path, out: Path, stats: list, page_texts: list, skipped: list
) -> None:
    try:
        doc = fitz.open(str(path))
    except Exception:
        skipped.append(path.name)
        return

    if doc.is_encrypted:
        skipped.append(path.name)
        doc.close()
        return

    if doc.page_count == 0:
        skipped.append(path.name)
        doc.close()
        return

    for i in range(doc.page_count):
        page = doc[i]
        # 2× scale gives better OCR resolution on standard-sized pages.
        pix = page.get_pixmap(matrix=fitz.Matrix(2, 2), colorspace=fitz.csGRAY)
        img = Image.frombytes("L", [pix.width, pix.height], pix.samples).convert("RGB")
        img = resize_to_long_side(img, LONG_SIDE)
        _process_page(
            img, out, len(stats) + 1, path.name, i + 1, stats, page_texts, skipped
        )

    doc.close()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    inp, out, no_text, made_output = parse_args()
    inputs, ignored = collect_inputs(inp)

    if not inputs:
        msg = f"no supported files (HEIC, JPG, PNG, TIFF, or PDF) in {inp}"
        if ignored:
            msg += f"\nignored: {', '.join(ignored)}"
        fail(msg)

    prepare_output(out, inp)

    stats: list[dict] = []
    page_texts: list[str] = []
    skipped: list[str] = []

    for path in inputs:
        if path.suffix.lower() == ".pdf":
            process_pdf(path, out, stats, page_texts, skipped)
        else:
            img = open_image(path)
            if img is None:
                skipped.append(path.name)
            else:
                img = resize_to_long_side(img, LONG_SIDE)
                _process_page(
                    img, out, len(stats) + 1, path.name, None, stats, page_texts, skipped
                )

    manifest = {
        "input": str(inp),
        "threshold": UNCLEAR_THRESHOLD / 100,
        "spellCheck": False,
        "pages": stats,
        "skipped": skipped,
        "ignored": ignored,
    }
    try:
        (out / "manifest.json").write_text(
            json.dumps(manifest, indent=2), encoding="utf-8"
        )
    except Exception as e:
        fail(f"could not write manifest.json: {e}")

    if not stats:
        fail("none of the files could be opened")

    # Summary — same format as the macOS script so SKILL.md parsing works identically.
    for s in stats:
        src = f"{s['source']} p{s['pdfPage']}" if s["pdfPage"] else s["source"]
        flags = ["full-frame"]
        if s["noText"]:
            flags.append("NO TEXT FOUND")
        if s["mostlyUnreadable"]:
            flags.append("MOSTLY UNREADABLE")
        if s["recognitionFailed"]:
            flags.append("RECOGNITION FAILED")
        print(
            f"page {s['page']}  {src}  "
            f"lines={s['lines']} unclear={s['unclearLines']} "
            f"mean={s['meanConfidence']:.2f}  ({', '.join(flags)})"
        )

    if skipped:
        print(f"skipped (could not open): {', '.join(skipped)}")
    if ignored:
        print(f"ignored (not a supported type): {', '.join(ignored)}")
    if made_output:
        print(f"work folder: {out}")

    if not no_text:
        for i, t in enumerate(page_texts):
            if stats[i]["lines"] > 0:
                print(f"\n--- page {i + 1} ---\n{t}")


if __name__ == "__main__":
    main()
