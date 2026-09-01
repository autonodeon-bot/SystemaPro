#!/usr/bin/env python3
"""Find where section 15 text lives in to-1.docx."""
from __future__ import annotations

import sys
from docx import Document
from docx.oxml.ns import qn

sys.path.insert(0, "/app")
from report_forms_registry import resolve_form_path


def main():
    path = resolve_form_path("to-1")
    doc = Document(str(path))
    body = doc.element.body
    needles = ("Фактическое", "фактическое", "Выводы по результатам", "Техническое состояние объекта")
    print("template", path)
    # All w:p with text
    hits = 0
    for i, p_el in enumerate(body.iter(qn("w:p"))):
        texts = [t.text or "" for t in p_el.iter(qn("w:t"))]
        joined = "".join(texts)
        if not any(n in joined for n in needles):
            continue
        hits += 1
        parent = p_el.getparent()
        ptag = parent.tag.split("}")[-1] if parent is not None else "?"
        # walk up for sdt/tbl/txbx
        chain = []
        el = p_el
        for _ in range(8):
            el = el.getparent()
            if el is None:
                break
            chain.append(el.tag.split("}")[-1])
        print(f"--- hit {hits} parent={ptag} chain={chain}")
        print(f"    text={joined[:220]!r}")
        print(f"    n_t={len(texts)} pieces={texts[:12]!r}")
    print("HITS", hits)

    # Also check if text is only in document.xml as single run elsewhere
    xml = body.xml
    for n in needles:
        print(f"xml contains {n!r}:", n in xml)


if __name__ == "__main__":
    main()
