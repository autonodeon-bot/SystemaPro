def fill_missing_attributes(current, incoming):
    """Offline observations may fill blanks, never overwrite an operator's value."""
    merged = dict(current or {})
    conflicts = []
    for key, value in (incoming or {}).items():
        if value is None or (isinstance(value, str) and not value.strip()):
            continue
        previous = merged.get(key)
        if previous is None or (isinstance(previous, str) and not previous.strip()):
            merged[key] = value
        elif str(previous).strip() != str(value).strip():
            conflicts.append(key)
    return merged, conflicts
