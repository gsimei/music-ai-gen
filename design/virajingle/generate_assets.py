"""Compatibility entry point for the current musical ViraJingle identity."""
from pathlib import Path
import runpy

runpy.run_path(str(Path(__file__).resolve().parent / "musical/generate_assets.py"), run_name="__main__")
