# -*- coding: utf-8 -*-
from pathlib import Path
import re

# Changelog
p = Path("pages/Changelog.tsx")
t = p.read_text(encoding="utf-8")
if "version: '3.7.7'" not in t:
    needle = "  const versions: Version[] = [\n    {\n      version: '3.7.5',"
    insert = """  const versions: Version[] = [
    {
      version: '3.7.7',
      date: '10.07.2026',
      type: 'patch',
      changes: [
        {
          type: 'improved',
          description:
            'Мобильное: схема контроля на карте обследования; блокировка подписания без таблички/схемы/УЗТ/заключения; предупреждение при синхронизации неполных данных.',
        },
        {
          type: 'improved',
          description:
            'Светлая тема: заголовки и текст на панелях читаемы (вместо белого на белом).',
        },
        {
          type: 'added',
          description:
            'Нормативные документы: загрузка и скачивание PDF/DOC/DOCX.',
        },
        {
          type: 'added',
          description:
            'Шаблоны отчётов: просмотр состава разделов шаблона.',
        },
        {
          type: 'improved',
          description:
            'Русские подписи типов обследований и статусов; официальные формы ТО заполняются полями мобильного чек-листа.',
        },
      ],
    },
    {
      version: '3.7.6',
      date: '10.07.2026',
      type: 'patch',
      changes: [
        {
          type: 'added',
          description:
            'Официальные формы ТО: генерация Word по шаблону; to-1/to-13/to-25; PDF через LibreOffice.',
        },
      ],
    },
    {
      version: '3.7.5',"""
    if needle not in t:
        raise SystemExit("changelog needle not found")
    p.write_text(t.replace(needle, insert, 1), encoding="utf-8")
    print("changelog ok")
else:
    print("changelog already has 3.7.7")

# package.json
pj = Path("package.json")
pj.write_text(pj.read_text(encoding="utf-8").replace('"version": "3.7.6"', '"version": "3.7.7"'), encoding="utf-8")

# constants
c = Path("constants.ts")
ct = c.read_text(encoding="utf-8")
ct = ct.replace("APP_VERSION = '3.7.6'", "APP_VERSION = '3.7.7'")
ct = ct.replace("MOBILE_APP_VERSION = '3.7.6'", "MOBILE_APP_VERSION = '3.7.7'")
ct = re.sub(r"MOBILE_APP_BUILD = '\d+'", "MOBILE_APP_BUILD = '44'", ct)
if "Релиз 3.7.7" not in ct:
    ct = ct.replace(
        "'Релиз 3.7.5:",
        "'Релиз 3.7.7: UX мобильного, светлая тема, загрузка НД, просмотр шаблонов; APK 3.7.7+44.',\n  'Релиз 3.7.5:",
    )
c.write_text(ct, encoding="utf-8")

# main.py
m = Path("backend/main.py")
mt = m.read_text(encoding="utf-8")
mt = mt.replace("3.7.6", "3.7.7")
m.write_text(mt, encoding="utf-8")

# mobile_stats if any
ms = Path("backend/mobile_stats_api.py")
if ms.exists():
    mst = ms.read_text(encoding="utf-8")
    if "3.7.6" in mst:
        ms.write_text(mst.replace("3.7.6", "3.7.7"), encoding="utf-8")

# pubspec
pub = Path("mobile/pubspec.yaml")
pub.write_text(pub.read_text(encoding="utf-8").replace("version: 3.7.6+43", "version: 3.7.7+44"), encoding="utf-8")
print("versions bumped to 3.7.7")
