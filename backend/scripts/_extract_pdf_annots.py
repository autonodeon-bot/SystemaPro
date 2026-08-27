# -*- coding: utf-8 -*-
import fitz
import json
from pathlib import Path

pdf_path = Path(r"c:\Users\Mariya\Downloads\report (5).pdf")
out_path = Path(r"c:\RUSTAM\DIATEKS\sys\SystemaPro\backend\scripts\_pdf_annots.json")

doc = fitz.open(pdf_path)
anns = []
for i, page in enumerate(doc):
    for a in page.annots() or []:
        info = a.info or {}
        content = (info.get("content") or "").strip()
        title = info.get("title") or ""
        subject = info.get("subject") or ""
        try:
            rect = [round(x, 1) for x in a.rect]
        except Exception:
            rect = None
        nearby = ""
        try:
            clip = fitz.Rect(a.rect)
            clip.x0 -= 50
            clip.y0 -= 40
            clip.x1 += 240
            clip.y1 += 60
            nearby = page.get_text("text", clip=clip).strip()[:500]
        except Exception:
            pass
        # Only keep annotations that have useful notes, or group squares with notes
        anns.append(
            {
                "page": i + 1,
                "type": a.type[1] if a.type else None,
                "title": title,
                "subject": subject,
                "content": content,
                "nearby": nearby,
                "rect": rect,
            }
        )

# Prefer notes with content for summary
notes = [a for a in anns if a["content"]]
out_path.write_text(json.dumps(anns, ensure_ascii=False, indent=2), encoding="utf-8")
summary = Path(r"c:\RUSTAM\DIATEKS\sys\SystemaPro\backend\scripts\_pdf_annots_notes_only.json")
summary.write_text(json.dumps(notes, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"total={len(anns)} with_notes={len(notes)} saved={out_path}")
for a in notes:
    line = f"p{a['page']}: {a['content']}"
    print(line.encode("utf-8", errors="replace").decode("utf-8"))
