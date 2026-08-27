# -*- coding: utf-8 -*-
from pathlib import Path
import re

root = Path(r"c:\RUSTAM\DIATEKS\sys\SystemaPro")
pj = root / "package.json"
pj.write_text(pj.read_text(encoding="utf-8").replace('"version": "3.7.8"', '"version": "3.7.9"'), encoding="utf-8")
c = root / "constants.ts"
ct = c.read_text(encoding="utf-8")
ct = ct.replace("APP_VERSION = '3.7.8'", "APP_VERSION = '3.7.9'")
ct = ct.replace("MOBILE_APP_VERSION = '3.7.8'", "MOBILE_APP_VERSION = '3.7.9'")
ct = re.sub(r"MOBILE_APP_BUILD = '\d+'", "MOBILE_APP_BUILD = '46'", ct)
c.write_text(ct, encoding="utf-8")
m = root / "backend" / "main.py"
m.write_text(m.read_text(encoding="utf-8").replace("3.7.8", "3.7.9"), encoding="utf-8")
pub = root / "mobile" / "pubspec.yaml"
pub.write_text(pub.read_text(encoding="utf-8").replace("version: 3.7.8+45", "version: 3.7.9+46"), encoding="utf-8")

ch = root / "pages" / "Changelog.tsx"
t = ch.read_text(encoding="utf-8")
if "version: '3.7.9'" not in t:
    needle = "  const versions: Version[] = [\n    {\n      version: '3.7.8',"
    insert = """  const versions: Version[] = [
    {
      version: '3.7.9',
      date: '17.07.2026',
      type: 'patch',
      changes: [
        {
          type: 'added',
          description:
            'Задание: поля договора, периода работ, основания и № техкарты; выбор формы ТО при создании; данные уходят в отчёт.',
        },
        {
          type: 'added',
          description:
            'Мобильное: выпадающие формулировки разд. 14–15 и оперативной диагностики; поля класса опасности и расчётной толщины элементов.',
        },
        {
          type: 'improved',
          description:
            'Форма ТО to-1: заполнение титула/разд.1–15, «Не предоставлено», местонахождение в шапке приложений, приборы ВИК (шероховатость/освещённость).',
        },
      ],
    },
    {
      version: '3.7.8',"""
    if needle not in t:
        raise SystemExit("changelog needle missing")
    ch.write_text(t.replace(needle, insert, 1), encoding="utf-8")
print("ok 3.7.9")
