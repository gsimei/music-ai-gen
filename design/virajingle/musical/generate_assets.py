"""Reproduce the approved musical logo as outlined SVG and transparent PNG.

Design-only dependencies: Pillow 13.0.0, vtracer 0.6.15 and ImageMagick.
The approved image is traced once; the white version and J reuse its exact paths.
"""
from copy import deepcopy
from pathlib import Path
import subprocess
import shutil
import tempfile
import xml.etree.ElementTree as ET
from zipfile import ZipFile, ZIP_DEFLATED

from PIL import Image
import vtracer

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / "public/brand/musical"
NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", NS)
FOREST = "#173E32"
CREAM = "#F6F5ED"


def trace(source, crop, temp):
    image = source.crop(crop).convert("RGB")
    mask = Image.new("RGB", image.size, "white")
    mask.putdata([(0, 0, 0) if max(pixel) < 150 else (255, 255, 255)
                  for pixel in image.get_flattened_data()])
    mask.save(temp / "mask.png")
    vtracer.convert_image_to_svg_py(
        str(temp / "mask.png"), str(temp / "trace.svg"),
        colormode="binary", mode="spline", filter_speckle=12,
        corner_threshold=60, length_threshold=4, max_iterations=10,
        splice_threshold=45, path_precision=3,
    )
    root = ET.parse(temp / "trace.svg").getroot()
    paths = list(root.findall(f"{{{NS}}}path"))
    assert paths, "The trace must contain real vector paths"
    for path in paths:
        path.attrib.pop("fill", None)
    return paths, image.size


def svg(paths, size, color, title, padding):
    width, height = size
    root = ET.Element(f"{{{NS}}}svg", {
        "width": str(width + 2 * padding),
        "height": str(height + 2 * padding),
        "viewBox": f"0 0 {width + 2 * padding} {height + 2 * padding}",
        "role": "img", "aria-label": title,
    })
    ET.SubElement(root, f"{{{NS}}}title").text = title
    group = ET.SubElement(root, f"{{{NS}}}g", {
        "fill": color, "transform": f"translate({padding} {padding})",
    })
    group.extend(deepcopy(paths))
    return root


def write_svg(root, path):
    ET.ElementTree(root).write(path, encoding="unicode", xml_declaration=False)


def png(svg_path, output_path, width):
    subprocess.run([
        "magick", "-background", "none", "-density", "288", str(svg_path),
        "-resize", f"{width}x", "-strip", f"PNG32:{output_path}",
    ], check=True)
    with Image.open(output_path) as image:
        assert image.mode == "RGBA"
        assert image.getchannel("A").getextrema() == (0, 255)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    source = Image.open(HERE / "source-approved.png")
    assert source.size == (1536, 1024), "Crop coordinates target the approved board"
    with tempfile.TemporaryDirectory() as temporary:
        temp = Path(temporary)
        logo, logo_size = trace(source, (77, 368, 1468, 663), temp)
        # Use the very same J path from the logo, including its curl.
        # The J is wholly inside this isolated bounding region of the approved image.
        j_paths, j_size = trace(source, (643, 368, 815, 661), temp)
        assert len(j_paths) == 1
        assert any(path.get("d") == j_paths[0].get("d") for path in logo), \
            "The isolated J must match the logo's exact vector contour"
    assets = [
        ("virajingle-logo", logo, logo_size, FOREST, "ViraJingle", 24, 3200),
        ("virajingle-logo-white", logo, logo_size, "#FFFFFF", "ViraJingle — branca", 24, 3200),
        ("virajingle-j", j_paths, j_size, FOREST, "ViraJingle — símbolo J", 24, 1024),
    ]
    for name, paths, size, color, title, padding, width in assets:
        root = svg(paths, size, color, title, padding)
        target = OUT / f"{name}.svg"
        write_svg(root, target)
        png(target, OUT / f"{name}.png", width)
        # Confirm no fonts or embedded raster images are required.
        assert not root.findall(f".//{{{NS}}}text")
        assert not root.findall(f".//{{{NS}}}image")

    # Square, opaque icon: the J fits entirely inside the maskable safe circle.
    icon = ET.Element(f"{{{NS}}}svg", {
        "width": "512", "height": "512", "viewBox": "0 0 512 512",
        "role": "img", "aria-label": "ViraJingle",
    })
    ET.SubElement(icon, f"{{{NS}}}title").text = "ViraJingle"
    ET.SubElement(icon, f"{{{NS}}}rect", {"width": "512", "height": "512", "fill": FOREST})
    icon_j = ET.SubElement(icon, f"{{{NS}}}g", {
        "fill": "#FFFFFF", "transform": "translate(170 109.5)",
    })
    icon_j.extend(deepcopy(j_paths))
    write_svg(icon, OUT / "virajingle-icon.svg")
    subprocess.run([
        "magick", "-background", "none", str(OUT / "virajingle-icon.svg"),
        "-strip", str(OUT / "virajingle-icon.png"),
    ], check=True)
    for extension in ("svg", "png"):
        shutil.copyfile(OUT / f"virajingle-icon.{extension}", ROOT / f"public/icon.{extension}")

    preview = ET.Element(f"{{{NS}}}svg", {
        "width": "1600", "height": "1000", "viewBox": "0 0 1600 1000",
    })
    ET.SubElement(preview, f"{{{NS}}}rect", {"width": "1600", "height": "1000", "fill": CREAM})
    ET.SubElement(preview, f"{{{NS}}}rect", {"y": "420", "width": "1600", "height": "360", "fill": FOREST})
    for paths, color, x, y, scale in [
        (logo, FOREST, 105, 70, 1),
        (logo, "#FFFFFF", 105, 452, 1),
        (j_paths, FOREST, 748, 810, 0.55),
    ]:
        group = ET.SubElement(preview, f"{{{NS}}}g", {
            "fill": color, "transform": f"translate({x} {y}) scale({scale})",
        })
        group.extend(deepcopy(paths))
    write_svg(preview, HERE / "preview.svg")
    subprocess.run(["magick", str(HERE / "preview.svg"), str(HERE / "preview.png")], check=True)
    with ZipFile(HERE / "virajingle-musical-kit.zip", "w", ZIP_DEFLATED) as archive:
        for path in sorted(OUT.glob("*")):
            archive.write(path, path.name)
        archive.write(HERE / "README.md", "README.md")
    for path in sorted(OUT.glob("*")):
        print(f"{path.relative_to(ROOT)} ({path.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
