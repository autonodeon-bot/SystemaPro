from report_forms_registry import resolve_form_path, load_forms_catalog

load_forms_catalog.cache_clear()
for fid in ("to-1", "to-13", "to-25"):
    p = resolve_form_path(fid)
    print(fid, p, bool(p and p.exists()), (p.stat().st_size if p else 0))
