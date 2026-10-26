#!/usr/bin/env python3
"""
Color Breakdown — lists every color in an image with its hex code.

Cross-platform (Windows / macOS / Linux). Requires Python 3.9+ with
Pillow and NumPy:   pip install pillow numpy

Run:   python color_breakdown.py [image]
Build a standalone Windows .exe:  see build-windows.bat
"""

from __future__ import annotations

import csv
import sys
import threading
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

try:                                   # optional: HEIC/HEIF (iPhone photos)
    from pillow_heif import register_heif_opener
    register_heif_opener()
except Exception:
    pass

# --------------------------------------------------------------------------- #
# Analysis engine (no GUI dependencies — importable and testable on its own)
# --------------------------------------------------------------------------- #

PRECISIONS = {           # name -> bits kept per channel
    "Exact": 8,
    "Fine": 6,
    "Medium": 5,
    "Coarse": 4,
}
PRECISION_HELP = {
    "Exact": "Every distinct RGB value is listed separately.",
    "Fine": "Colors within ~4 levels per channel are merged.",
    "Medium": "Colors within ~8 levels per channel are merged.",
    "Coarse": "Colors within ~16 levels per channel are merged.",
}
MAX_DIM = 4096


@dataclass(frozen=True)
class ColorEntry:
    r: int
    g: int
    b: int
    count: int

    @property
    def hex(self) -> str:
        return f"#{self.r:02X}{self.g:02X}{self.b:02X}"


@dataclass
class AnalysisResult:
    entries: list[ColorEntry]   # sorted most -> least common
    total_pixels: int           # non-transparent pixels counted
    width: int
    height: int
    downsampled: bool


def load_image(path: str | Path) -> Image.Image:
    img = Image.open(path)
    img.load()
    return img


def analyze(img: Image.Image, precision: str = "Exact") -> AnalysisResult:
    bits = PRECISIONS[precision]
    w, h = img.size
    downsampled = False
    if max(w, h) > MAX_DIM:
        s = MAX_DIM / max(w, h)
        w, h = max(1, int(w * s)), max(1, int(h * s))
        img = img.resize((w, h), Image.LANCZOS)
        downsampled = True

    rgba = np.asarray(img.convert("RGBA"), dtype=np.uint8).reshape(-1, 4)
    opaque = rgba[rgba[:, 3] != 0][:, :3].astype(np.uint32)
    total = int(opaque.shape[0])
    if total == 0:
        return AnalysisResult([], 0, w, h, downsampled)

    shift = 8 - bits
    mask = np.uint32((0xFF << shift) & 0xFF)
    keys = ((opaque[:, 0] & mask) << 16) | ((opaque[:, 1] & mask) << 8) | (opaque[:, 2] & mask)

    uniq, inverse, counts = np.unique(keys, return_inverse=True, return_counts=True)
    inverse = inverse.ravel()

    if shift == 0:
        r = (uniq >> 16) & 0xFF
        g = (uniq >> 8) & 0xFF
        b = uniq & 0xFF
    else:
        # representative color = mean of the pixels merged into each bucket
        n = len(uniq)
        r = np.bincount(inverse, weights=opaque[:, 0], minlength=n) / counts
        g = np.bincount(inverse, weights=opaque[:, 1], minlength=n) / counts
        b = np.bincount(inverse, weights=opaque[:, 2], minlength=n) / counts

    order = np.lexsort((uniq, -counts))   # count desc, then key asc
    entries = [
        ColorEntry(int(r[i]), int(g[i]), int(b[i]), int(counts[i])) for i in order
    ]
    return AnalysisResult(entries, total, w, h, downsampled)


def qualifying(result: AnalysisResult | None, minimum_percent: float) -> list[ColorEntry]:
    """Entries covering at least `minimum_percent` of the counted pixels."""
    if result is None or result.total_pixels == 0:
        return []
    threshold = result.total_pixels * minimum_percent / 100.0
    return [e for e in result.entries if e.count >= threshold]


# --------------------------------------------------------------------------- #
# GUI
# --------------------------------------------------------------------------- #

def main(argv: list[str]) -> None:
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk
    from PIL import ImageTk

    try:                                   # optional drag-and-drop support
        from tkinterdnd2 import DND_FILES, TkinterDnD
        Root = TkinterDnD.Tk
    except Exception:                      # pragma: no cover
        DND_FILES, Root = None, tk.Tk

    IMAGE_TYPES = [
        ("Images", "*.png *.jpg *.jpeg *.gif *.bmp *.tif *.tiff *.webp *.ico *.psd *.heic *.heif"),
        ("All files", "*.*"),
    ]

    class App:
        PAGE = 500          # rows shown before "Show more"

        def __init__(self, root):
            self.root = root
            self.root.title("Color Breakdown")
            self.root.geometry("980x600")
            self.root.minsize(780, 500)

            self.image = None
            self.image_path: Path | None = None
            self.result: AnalysisResult | None = None
            self.visible_limit = self.PAGE
            self._swatches = {}          # hex -> PhotoImage (must keep references)
            self._preview_photo = None
            self._analysis_token = 0

            self.precision = tk.StringVar(value="Exact")
            self.minimum_percent = tk.DoubleVar(value=10.0)
            self.search_text = tk.StringVar()
            self.status = tk.StringVar(value="Drop an image here or press Ctrl+O")

            self._build_ui()
            self._bind()
            if DND_FILES:
                self.root.drop_target_register(DND_FILES)
                self.root.dnd_bind("<<Drop>>", self._on_drop)

        # ---- layout ------------------------------------------------------- #

        def _build_ui(self):
            style = ttk.Style()
            if sys.platform.startswith("win"):
                style.theme_use("vista")
            style.configure("Treeview", rowheight=30)

            bar = ttk.Frame(self.root, padding=(10, 8))
            bar.pack(fill="x")
            ttk.Button(bar, text="Open Image…", command=self.open_dialog).pack(side="left")
            self.export_btn = ttk.Button(bar, text="Export CSV…", command=self.export_csv, state="disabled")
            self.export_btn.pack(side="left", padx=(8, 0))
            ttk.Label(bar, textvariable=self.status, foreground="gray").pack(side="left", padx=16)

            body = ttk.Frame(self.root)
            body.pack(fill="both", expand=True)

            # -- sidebar
            side = ttk.Frame(body, padding=12, width=280)
            side.pack(side="left", fill="y")
            side.pack_propagate(False)

            self.preview = ttk.Label(side, anchor="center", relief="groove")
            self.preview.pack(fill="x", ipady=4)
            self.name_lbl = ttk.Label(side, text="", font=("", 11, "bold"), wraplength=250)
            self.name_lbl.pack(fill="x", pady=(10, 4))

            stats = ttk.Frame(side)
            stats.pack(fill="x")
            self.stat_vars = {}
            for key in ("Size", "Pixels counted", "Unique colors", "Shown"):
                row = ttk.Frame(stats)
                row.pack(fill="x")
                ttk.Label(row, text=key, foreground="gray").pack(side="left")
                v = tk.StringVar(value="–")
                self.stat_vars[key] = v
                ttk.Label(row, textvariable=v, font=("Courier", 10)).pack(side="right")

            ttk.Separator(side).pack(fill="x", pady=10)

            ttk.Label(side, text="Grouping", foreground="gray").pack(anchor="w")
            grp = ttk.Frame(side)
            grp.pack(fill="x", pady=(2, 2))
            for name in PRECISIONS:
                ttk.Radiobutton(grp, text=name, value=name, variable=self.precision,
                                command=self.reanalyze).pack(side="left", padx=(0, 6))
            self.help_lbl = ttk.Label(side, text=PRECISION_HELP["Exact"], foreground="gray",
                                      wraplength=250, font=("", 9))
            self.help_lbl.pack(anchor="w")

            ttk.Separator(side).pack(fill="x", pady=10)

            ttk.Label(side, text="Minimum coverage", foreground="gray").pack(anchor="w")
            mrow = ttk.Frame(side)
            mrow.pack(fill="x", pady=2)
            self.min_spin = ttk.Spinbox(mrow, from_=0, to=100, increment=1, width=6,
                                        textvariable=self.minimum_percent,
                                        command=self.refresh_list)
            self.min_spin.pack(side="left")
            ttk.Label(mrow, text="% of image").pack(side="left", padx=6)
            ttk.Label(side, text="Colors covering less than this are disregarded.",
                      foreground="gray", wraplength=250, font=("", 9)).pack(anchor="w")

            ttk.Separator(side).pack(fill="x", pady=10)
            ttk.Label(side, text="Click any row to copy its hex code.",
                      foreground="gray", font=("", 9)).pack(anchor="w")

            # -- list
            right = ttk.Frame(body, padding=(0, 0, 0, 0))
            right.pack(side="left", fill="both", expand=True)

            srow = ttk.Frame(right, padding=(10, 8))
            srow.pack(fill="x")
            ttk.Label(srow, text="Filter by hex:").pack(side="left")
            ttk.Entry(srow, textvariable=self.search_text, width=18).pack(side="left", padx=6)
            self.count_lbl = ttk.Label(srow, text="", foreground="gray")
            self.count_lbl.pack(side="right")

            cols = ("hex", "percent", "pixels")
            self.tree = ttk.Treeview(right, columns=cols, show="tree headings", selectmode="browse")
            self.tree.heading("#0", text="")
            self.tree.column("#0", width=70, stretch=False, anchor="center")
            self.tree.heading("hex", text="Hex")
            self.tree.column("hex", width=110, stretch=False)
            self.tree.heading("percent", text="% of image")
            self.tree.column("percent", width=110, anchor="e", stretch=False)
            self.tree.heading("pixels", text="Pixels")
            self.tree.column("pixels", width=120, anchor="e", stretch=True)

            vsb = ttk.Scrollbar(right, orient="vertical", command=self.tree.yview)
            self.tree.configure(yscrollcommand=vsb.set)
            vsb.pack(side="right", fill="y")
            self.tree.pack(side="left", fill="both", expand=True)

            self.more_btn = ttk.Button(right, text="", command=self._show_more)

            self.empty_lbl = ttk.Label(right, text="", foreground="gray", anchor="center",
                                       justify="center")

        def _bind(self):
            self.root.bind("<Control-o>", lambda e: self.open_dialog())
            self.root.bind("<Command-o>", lambda e: self.open_dialog())
            self.root.bind("<Control-e>", lambda e: self.export_csv())
            self.root.bind("<Command-e>", lambda e: self.export_csv())
            self.tree.bind("<ButtonRelease-1>", self._on_row_click)
            self.tree.bind("<Return>", self._on_row_click)
            self.search_text.trace_add("write", lambda *_: self.refresh_list())
            self.minimum_percent.trace_add("write", lambda *_: self.refresh_list())
            self.precision.trace_add(
                "write", lambda *_: self.help_lbl.configure(text=PRECISION_HELP[self.precision.get()]))

        # ---- opening images ----------------------------------------------- #

        def open_dialog(self):
            path = filedialog.askopenfilename(title="Choose an image", filetypes=IMAGE_TYPES)
            if path:
                self.open(path)

        def _on_drop(self, event):
            paths = self.root.tk.splitlist(event.data)
            if paths:
                self.open(paths[0])

        def open(self, path):
            try:
                img = load_image(path)
            except Exception as exc:
                messagebox.showerror("Couldn't open image",
                                     f"\"{Path(path).name}\" couldn't be read as an image.\n\n{exc}")
                return
            self.image = img
            self.image_path = Path(path)
            self.root.title(f"{self.image_path.name} — Color Breakdown")
            self.name_lbl.configure(text=self.image_path.name)
            self.search_text.set("")
            self.visible_limit = self.PAGE

            thumb = img.convert("RGBA")
            thumb.thumbnail((250, 200))
            self._preview_photo = ImageTk.PhotoImage(thumb)
            self.preview.configure(image=self._preview_photo)
            self.reanalyze()

        # ---- analysis ----------------------------------------------------- #

        def reanalyze(self):
            if self.image is None:
                return
            self._analysis_token += 1
            token = self._analysis_token
            self.status.set("Analyzing…")
            self._clear_tree()
            precision = self.precision.get()
            img = self.image

            def work():
                try:
                    res = analyze(img, precision)
                except Exception as exc:        # pragma: no cover
                    self.root.after(0, lambda: messagebox.showerror("Analysis failed", str(exc)))
                    return
                self.root.after(0, lambda: self._analysis_done(token, res))

            threading.Thread(target=work, daemon=True).start()

        def _analysis_done(self, token, res: AnalysisResult):
            if token != self._analysis_token:
                return
            self.result = res
            self.export_btn.configure(state="normal")
            size = f"{res.width} × {res.height}" + (" (scaled)" if res.downsampled else "")
            self.stat_vars["Size"].set(size)
            self.stat_vars["Pixels counted"].set(f"{res.total_pixels:,}")
            self.stat_vars["Unique colors"].set(f"{len(res.entries):,}")
            self.status.set("")
            self.refresh_list()

        # ---- list --------------------------------------------------------- #

        def _minimum(self) -> float:
            try:
                return max(0.0, min(100.0, float(self.minimum_percent.get())))
            except (tk.TclError, ValueError):
                return 0.0

        def _filtered(self) -> list[ColorEntry]:
            entries = qualifying(self.result, self._minimum())
            q = self.search_text.get().strip().upper().replace("#", "")
            if q:
                entries = [e for e in entries if q in e.hex[1:]]
            return entries

        def _clear_tree(self):
            self.tree.delete(*self.tree.get_children())
            self._swatches.clear()
            self.more_btn.pack_forget()
            self.empty_lbl.pack_forget()

        def _swatch(self, entry: ColorEntry):
            img = self._swatches.get(entry.hex)
            if img is None:
                img = tk.PhotoImage(width=44, height=22)
                img.put(entry.hex, to=(0, 0, 44, 22))
                self._swatches[entry.hex] = img
            return img

        def refresh_list(self):
            if self.result is None:
                return
            self._clear_tree()
            entries = self._filtered()
            self.stat_vars["Shown"].set(f"{len(qualifying(self.result, self._minimum())):,}")
            self.count_lbl.configure(text=f"{len(entries):,} colors")

            if not entries:
                if self.search_text.get().strip():
                    msg = "No matching colors."
                else:
                    msg = (f"No color covers at least {self._minimum():.0f}% of the image.\n"
                           "Lower the minimum coverage or choose a coarser grouping.")
                self.empty_lbl.configure(text=msg)
                self.empty_lbl.pack(fill="both", expand=True)
                return

            total = max(1, self.result.total_pixels)
            for e in entries[: self.visible_limit]:
                pct = e.count / total * 100
                self.tree.insert("", "end", iid=e.hex, image=self._swatch(e),
                                 values=(e.hex, f"{pct:.2f}%", f"{e.count:,}"))
            remaining = len(entries) - min(len(entries), self.visible_limit)
            if remaining > 0:
                self.more_btn.configure(text=f"Show {remaining:,} more")
                self.more_btn.pack(side="bottom", pady=8)

        def _show_more(self):
            self.visible_limit += 1000
            self.refresh_list()

        def _on_row_click(self, _event=None):
            sel = self.tree.selection()
            if not sel:
                return
            hex_code = sel[0]
            self.root.clipboard_clear()
            self.root.clipboard_append(hex_code)
            self.status.set(f"Copied {hex_code}")
            self.root.after(1500, lambda: self.status.set("") if self.status.get().startswith("Copied") else None)

        # ---- export ------------------------------------------------------- #

        def export_csv(self):
            if self.result is None:
                return
            base = self.image_path.stem if self.image_path else "image"
            path = filedialog.asksaveasfilename(
                title="Export CSV", defaultextension=".csv",
                initialfile=f"{base}-colors.csv",
                filetypes=[("CSV", "*.csv")])
            if not path:
                return
            total = max(1, self.result.total_pixels)
            try:
                with open(path, "w", newline="", encoding="utf-8") as f:
                    wr = csv.writer(f)
                    wr.writerow(["hex", "red", "green", "blue", "pixels", "percent"])
                    for e in qualifying(self.result, self._minimum()):
                        wr.writerow([e.hex, e.r, e.g, e.b, e.count, f"{e.count / total * 100:.4f}"])
            except OSError as exc:
                messagebox.showerror("Couldn't save CSV", str(exc))
                return
            self.status.set(f"Exported {Path(path).name}")

    root = Root()
    try:                                   # window/taskbar icon, if present
        icon = Path(__file__).with_name("AppIcon.png")
        if getattr(sys, "_MEIPASS", None):   # PyInstaller bundle
            icon = Path(sys._MEIPASS) / "AppIcon.png"
        if icon.exists():
            root.iconphoto(True, ImageTk.PhotoImage(Image.open(icon)))
    except Exception:
        pass

    app = App(root)
    if len(argv) > 1:
        root.after(100, lambda: app.open(argv[1]))
    root.mainloop()


if __name__ == "__main__":
    main(sys.argv)
