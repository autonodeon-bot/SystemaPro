"""Run the bundled document renderer with the task-local LibreOffice runtime."""
import os
import runpy
from pathlib import Path
root = Path(__file__).resolve().parents[1]
os.environ['PATH'] = str(root / 'tools/libreoffice/program') + os.pathsep + os.environ.get('PATH', '')
renderer = os.getenv('DOCX_RENDERER_PATH')
if not renderer:
    candidates = sorted((Path.home() / '.codex/plugins/cache/openai-primary-runtime/documents').glob('*/skills/documents/render_docx.py'))
    if not candidates:
        raise SystemExit('Set DOCX_RENDERER_PATH to the installed documents skill renderer')
    renderer = str(candidates[-1])
runpy.run_path(renderer, run_name='__main__')
