# -*- coding: utf-8 -*-
import json
from pathlib import Path

import fitz

pdf_path = (
    Path(r"c:\RUSTAM\DIATEKS\sys\SystemaPro\docs\Замечания2")
    / "Отчет с замечаниями 20.08.2026 (Вер. моб. прил. 3.7.24).pdf"
)
out_dir = Path(r"c:\RUSTAM\DIATEKS\sys\SystemaPro\backend\scripts")

doc = fitz.open(pdf_path)
print("pages", doc.page_count)
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
            clip.x0 -= 80
            clip.y0 -= 50
            clip.x1 += 280
            clip.y1 += 80
            nearby = page.get_text("text", clip=clip).strip()[:800]
        except Exception:
            pass
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

notes = [a for a in anns if a["content"]]
(out_dir / "_pdf_annots_2026-08-20.json").write_text(
    json.dumps(anns, ensure_ascii=False, indent=2), encoding="utf-8"
)
(out_dir / "_pdf_annots_notes_2026-08-20.json").write_text(
    json.dumps(notes, ensure_ascii=False, indent=2), encoding="utf-8"
)
print(f"total={len(anns)} with_notes={len(notes)}")
for a in notes:
    print(f"--- p{a['page']} [{a['type']}] ---")
    print(a["content"])
    print()
