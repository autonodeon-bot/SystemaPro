"""Read-only service checks; temporary PDF conversion does not alter user data."""
import json
import tempfile
import urllib.request
from datetime import timedelta
from pathlib import Path

from auth import create_access_token
from docx import Document
from docx_to_pdf import convert_docx_to_pdf


def get(path, token=None):
    headers = {'Authorization': f'Bearer {token}'} if token else {}
    request = urllib.request.Request('http://127.0.0.1:8000' + path, headers=headers)
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


assert get('/health') == {'status': 'healthy', 'database': 'connected'}
token = create_access_token({'sub': 'deployment-readonly-probe'}, timedelta(seconds=60))
forms = get('/api/report-forms', token)
assert len(forms) == 44, len(forms)
for form in forms:
    schema = get('/api/report-forms/' + form['id'] + '/schema', token)
    assert schema
print('HEALTH_AND_44_SCHEMAS_OK')
with tempfile.TemporaryDirectory(prefix='deployment-pdf-') as directory:
    path = Path(directory) / 'probe.docx'
    document = Document()
    document.add_paragraph('Проверка преобразования отчета в PDF')
    document.save(path)
    pdf = convert_docx_to_pdf(str(path))
    assert pdf and Path(pdf).read_bytes().startswith(b'%PDF')
print('LIBREOFFICE_PDF_OK')
