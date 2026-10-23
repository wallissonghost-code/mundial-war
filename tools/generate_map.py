"""Compatibility entry point: rebuild from the committed traced reference grid."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).with_name('build_release.py')))
