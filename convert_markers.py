import os
import re
import subprocess
import sys
import tempfile

SVG_TEMPLATE = '<?xml version="1.0" encoding="UTF-8"?><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {sz} {sz}">{{content}}</svg>'


def convert_one(svg_path: str, bgra_path: str, size: int, png_dir: str | None = None) -> bool:
	"""Convert a single SVG to BGRA via resvg + ffmpeg, then premultiply alpha."""
	name = os.path.basename(svg_path).replace(".svg", "")
	if png_dir:
		png_path = os.path.join(png_dir, name + ".png")
	else:
		png_path = os.path.join(tempfile.gettempdir(), name + ".png")
	try:
		subprocess.run(
			["resvg", "-w", str(size), "-h", str(size), svg_path, png_path],
			check=True,
			capture_output=True,
		)
		subprocess.run(
			["ffmpeg", "-y", "-loglevel", "error", "-i", png_path, "-f", "image2", "-c:v", "rawvideo", "-pix_fmt", "bgra", bgra_path],
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

	hex_colors = set(re.findall(r'#[0-9a-fA-F]{6}', raw))
	hex_colors |= set(re.findall(r'#[0-9a-fA-F]{3}', raw))
	hex_colors.discard('#000000')
	hex_colors.discard('#000')
	hex_colors.discard('#FFFFFF')
	hex_colors.discard('#FFF')
	if hex_colors:
		return False

	return True


def preprocess_single(raw: str) -> str:
	"""Apply white-color transform to a single-icon SVG if needed."""
	if not _needs_color_transform(raw):
		return raw

	raw = re.sub(
		r"<svg([^>]*)>",
		lambda m: "<svg" + re.sub(r'\s*color="[^"]*"', "", re.sub(r'\s*fill="[^"]*"', "", m.group(1))) + ' color="white" fill="white">',
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

		template = SVG_TEMPLATE.format(sz=size)

		for fname in sorted(os.listdir(markers_dir)):
			if not fname.endswith(".svg"):
				continue

			fpath = os.path.join(markers_dir, fname)
			with open(fpath, "r", encoding="utf-8") as f:
				raw = f.read()

			group_count = len(re.findall(r'<g id="', raw))

			if group_count >= 3:
				extracted = extract_groups(raw, template, sprite_dir)
				sprite_count += extracted
				print(f"  [{fname}] sprite sheet -> {extracted} icons")
			else:
				processed = preprocess_single(raw)
				out_path = os.path.join(single_dir, fname)
				with open(out_path, "w", encoding="utf-8") as f:
					f.write(processed)
				single_count += 1

		print(f"  Single icons: {single_count}  |  Sprite icons extracted: {sprite_count}")

		print(f"==> Converting single icons to BGRA...")
		converted = 0
		for fname in sorted(os.listdir(single_dir)):
			svg_path = os.path.join(single_dir, fname)
			name = fname[:-4]
			bgra_path = os.path.join(markers_dir, name + ".bgra")
			print(f"  {name} -> {name}.bgra")
			if convert_one(svg_path, bgra_path, size):
				converted += 1
		print(f"  Converted {converted} icons")

		print(f"==> Converting sprite icons to BGRA...")
		converted = 0
		for fname in sorted(os.listdir(sprite_dir)):
			svg_path = os.path.join(sprite_dir, fname)
			name = fname[:-4]
			bgra_path = os.path.join(markers_dir, name + ".bgra")
			print(f"  {name} -> {name}.bgra")
			if convert_one(svg_path, bgra_path, size, png_dir=markers_dir):
				converted += 1
		print(f"  Converted {converted} sprite icons")

	print("==> Done!")


if __name__ == "__main__":
	main()
