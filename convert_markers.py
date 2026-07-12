import os
import re
import subprocess
import sys
import tempfile

SVG_TEMPLATE = '<?xml version="1.0" encoding="UTF-8"?><svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 {sz} {sz}">{{content}}</svg>'


def _content_bbox(svg_path: str):
    """Return the tight (x0, y0, x1, y1) bounding box of an SVG's drawn content
    via `resvg --query-all`, or None if it can't be determined."""
    try:
        out = subprocess.run(
            ["resvg", "--query-all", svg_path],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    except subprocess.CalledProcessError:
        return None

    xs, ys, xe, ye = [], [], [], []
    for line in out.strip().splitlines():
        parts = line.split(",")
        if len(parts) < 5:
            continue
        try:
            x, y, w, h = (float(v) for v in parts[1:5])
        except ValueError:
            continue
        if w <= 0 or h <= 0:
            continue
        xs.append(x)
        ys.append(y)
        xe.append(x + w)
        ye.append(y + h)

    if not xs:
        return None
    return min(xs), min(ys), max(xe), max(ye)


def fit_square_viewbox(svg_path: str, pad: float = 0.10) -> None:
    """Rewrite the SVG's viewBox to a centered square around its content so a
    square (w == h) raster render preserves the icon's aspect ratio instead of
    stretching wide/tall icons (e.g. the CS2 zeus/taser icon). `pad` adds a
    transparent margin as a fraction of the icon's longest side per edge."""
    bb = _content_bbox(svg_path)
    if not bb:
        return

    x0, y0, x1, y1 = bb
    w, h = x1 - x0, y1 - y0
    side = max(w, h) * (1 + pad * 2)
    if side <= 0:
        return

    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    vx, vy = cx - side / 2, cy - side / 2
    viewbox = f'viewBox="{vx:.3f} {vy:.3f} {side:.3f} {side:.3f}"'

    raw = open(svg_path, encoding="utf-8").read()
    if "viewBox=" in raw:
        raw = re.sub(r'viewBox="[^"]*"', viewbox, raw, count=1)
    else:
        raw = re.sub(r"<svg", "<svg " + viewbox, raw, count=1)
    with open(svg_path, "w", encoding="utf-8") as f:
        f.write(raw)


def convert_one(
    svg_path: str, bgra_path: str, size: int, png_dir: str | None = None
) -> bool:
    """Convert a single SVG to BGRA via resvg + ffmpeg, then premultiply alpha."""
    name = os.path.basename(svg_path).replace(".svg", "")
    if png_dir:
        png_path = os.path.join(png_dir, name + ".png")
    else:
        png_path = os.path.join(tempfile.gettempdir(), name + ".png")
    try:
        fit_square_viewbox(svg_path)
        subprocess.run(
            ["resvg", "-w", str(size), "-h", str(size), svg_path, png_path],
            check=True,
            capture_output=True,
        )
        subprocess.run(
            [
                "ffmpeg",
                "-y",
                "-loglevel",
                "error",
                "-i",
                png_path,
                "-f",
                "image2",
                "-c:v",
                "rawvideo",
                "-pix_fmt",
                "bgra",
                bgra_path,
            ],
            check=True,
            capture_output=True,
        )
        with open(bgra_path, "r+b") as f:
            data = bytearray(f.read())
            for i in range(0, len(data), 4):
                a = data[i + 3] / 255.0
                data[i] = int(data[i] * a)
                data[i + 1] = int(data[i + 1] * a)
                data[i + 2] = int(data[i + 2] * a)
            f.seek(0)
            f.write(data)
            f.truncate()
        return True
    except subprocess.CalledProcessError as e:
        print(f"    ERROR: {e.stderr.decode().strip() or e}", file=sys.stderr)
        return False
    finally:
        if not png_dir and os.path.exists(png_path):
            os.remove(png_path)


def _needs_color_transform(raw: str) -> bool:
    """Check whether an SVG icon needs white-color transform."""
    if 'color="white"' in raw:
        return False

    hex_colors = set(re.findall(r"#[0-9a-fA-F]{6}", raw))
    hex_colors |= set(re.findall(r"#[0-9a-fA-F]{3}", raw))
    hex_colors.discard("#000000")
    hex_colors.discard("#000")
    hex_colors.discard("#FFFFFF")
    hex_colors.discard("#FFF")
    if hex_colors:
        return False

    return True


def preprocess_single(raw: str) -> str:
    """Apply white-color transform to a single-icon SVG if needed."""
    if not _needs_color_transform(raw):
        return raw

    raw = re.sub(
        r"<svg([^>]*)>",
        lambda m: (
            "<svg"
            + re.sub(
                r'\s*color="[^"]*"', "", re.sub(r'\s*fill="[^"]*"', "", m.group(1))
            )
            + ' color="white" fill="white">'
        ),
        raw,
        count=1,
    )
    raw = raw.replace('fill="black"', 'fill="white"')
    raw = raw.replace('fill="#000000"', 'fill="#FFFFFF"')
    return raw


def extract_groups(raw: str, svg_template: str, out_dir: str) -> int:
    """Extract all <g id="..."> groups from a sprite sheet into individual SVGs."""
    count = 0
    for m in re.finditer(r'<g id="([^"]+)"', raw):
        name = m.group(1)
        start = m.start()
        depth = 1
        pos = m.end()
        while depth > 0 and pos < len(raw):
            nxt_open = raw.find("<g", pos)
            nxt_close = raw.find("</g>", pos)
            if nxt_close == -1:
                break
            if nxt_open != -1 and nxt_open < nxt_close:
                depth += 1
                pos = nxt_open + 2
            else:
                depth -= 1
                pos = nxt_close + 4
        if depth != 0:
            print(f"    WARNING: cannot find closing </g> for {name}", file=sys.stderr)
            continue
        content = raw[start:pos]
        svg = svg_template.format(content=content)
        out_path = os.path.join(out_dir, name + ".svg")
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(svg)
        count += 1
    return count


def main():
    size = int(sys.argv[1]) if len(sys.argv) > 1 else 32

    script_dir = os.path.dirname(os.path.abspath(__file__))
    markers_dir = os.path.join(script_dir, "markers")

    with tempfile.TemporaryDirectory(prefix="convert_markers_") as tmp:
        single_dir = os.path.join(tmp, "single")
        sprite_dir = os.path.join(tmp, "sprite")
        os.makedirs(single_dir)
        os.makedirs(sprite_dir)

        single_count = 0
        sprite_count = 0
        sheet_idx = 0

        template = SVG_TEMPLATE.format(sz=size)

        # Each job is (svg_path, out_dir) so the BGRA lands in the same
        # (sub)folder as its source SVG, letting you sort markers by game into
        # markers/<game>/ subfolders. Sprite sheets get their own temp subdir so
        # identically named icons across games (e.g. dota2 & deadlock both have
        # `death`) don't overwrite each other.
        single_jobs = []
        sprite_jobs = []

        for root, _dirs, files in os.walk(markers_dir):
            for fname in sorted(files):
                if not fname.endswith(".svg"):
                    continue

                fpath = os.path.join(root, fname)
                with open(fpath, "r", encoding="utf-8") as f:
                    raw = f.read()

                group_count = len(re.findall(r'<g id="', raw))
                rel = os.path.relpath(root, markers_dir)

                if group_count >= 3:
                    sheet_dir = os.path.join(sprite_dir, str(sheet_idx))
                    os.makedirs(sheet_dir)
                    sheet_idx += 1
                    extracted = extract_groups(raw, template, sheet_dir)
                    for sfname in sorted(os.listdir(sheet_dir)):
                        sprite_jobs.append((os.path.join(sheet_dir, sfname), root))
                    sprite_count += extracted
                    print(
                        f"  [{os.path.join(rel, fname)}] sprite sheet -> {extracted} icons"
                    )
                else:
                    out_path = os.path.join(single_dir, fname)
                    with open(out_path, "w", encoding="utf-8") as f:
                        f.write(preprocess_single(raw))
                    single_jobs.append((out_path, root))
                    single_count += 1

        print(
            f"  Single icons: {single_count}  |  Sprite icons extracted: {sprite_count}"
        )

        print(f"==> Converting single icons to BGRA...")
        converted = 0
        for svg_path, out_dir in sorted(single_jobs):
            name = os.path.basename(svg_path)[:-4]
            bgra_path = os.path.join(out_dir, name + ".bgra")
            print(
                f"  {name} -> {os.path.join(os.path.relpath(out_dir, markers_dir), name)}.bgra"
            )
            if convert_one(svg_path, bgra_path, size):
                converted += 1
        print(f"  Converted {converted} icons")

        print(f"==> Converting sprite icons to BGRA...")
        converted = 0
        for svg_path, out_dir in sorted(sprite_jobs):
            name = os.path.basename(svg_path)[:-4]
            bgra_path = os.path.join(out_dir, name + ".bgra")
            print(
                f"  {name} -> {os.path.join(os.path.relpath(out_dir, markers_dir), name)}.bgra"
            )
            if convert_one(svg_path, bgra_path, size, png_dir=out_dir):
                converted += 1
        print(f"  Converted {converted} sprite icons")

    print("==> Done!")


if __name__ == "__main__":
    main()
