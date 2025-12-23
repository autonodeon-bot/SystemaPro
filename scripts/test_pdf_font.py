import json
import urllib.parse
import urllib.request


def post_form(url: str, data: dict) -> dict:
    payload = urllib.parse.urlencode(data).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    return json.loads(urllib.request.urlopen(req).read().decode("utf-8"))


def post_json(url: str, token: str, data: dict) -> dict:
    payload = json.dumps(data).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        return json.loads(urllib.request.urlopen(req).read().decode("utf-8"))
    except urllib.error.HTTPError as e:  # type: ignore[attr-defined]
        body = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {e.code} {e.reason} body={body}") from e


def get_bytes(url: str, token: str) -> bytes:
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    return urllib.request.urlopen(req).read()


def main():
    base = "http://5.129.203.182:8000"
    login = post_form(f"{base}/api/auth/login", {"username": "engineer", "password": "engineer123"})
    token = login["access_token"]

    gen = post_json(
        f"{base}/api/reports/generate",
        token,
        {"inspection_id": "61fc1884-c3fa-467d-9850-545130c0ab56", "report_type": "TECHNICAL_REPORT"},
    )
    rid = gen["id"]
    print("report_id:", rid)

    pdf = get_bytes(f"{base}/api/reports/{rid}/download", token)
    print("pdf_len:", len(pdf))
    print("has_DejaVu:", b"DejaVu" in pdf)


if __name__ == "__main__":
    main()


