"""Normalize user-entered API bases without guessing providers from model names."""
from urllib.parse import urlsplit, urlunsplit


def endpoint(protocol: str, address: str) -> tuple[str, str | None]:
    value = urlsplit(address.strip())
    if value.scheme not in ("http", "https") or not value.netloc or value.username or value.password or value.query or value.fragment:
        raise ValueError("服务地址应为 http/https API 地址，不包含账号、查询参数或片段")
    path = value.path.rstrip("/")
    api_version = None
    if protocol in ("openai_chat", "openai_responses"):
        for suffix in ("/chat/completions", "/responses"):
            if path.endswith(suffix):
                path = path[:-len(suffix)]
    return urlunsplit((value.scheme, value.netloc, path, "", "")), api_version
