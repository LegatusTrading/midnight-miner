import json
import os
from typing import List, Optional, Sequence, Tuple, Union
from urllib.parse import quote

import requests
from requests.auth import _basic_auth_str
from requests.exceptions import RequestException

ROTATING_RETRY_STATUS_CODES = {407, 408, 409, 425, 429, 500, 502, 503, 504}


def _normalize_proxy_entry(entry: dict) -> Optional[dict]:
    if not isinstance(entry, dict):
        return None

    server = str(entry.get("server") or "").strip()
    port = str(entry.get("port") or "").strip()

    if not server or not port:
        return None

    user = entry.get("user")
    password = entry.get("password")

    user_enc = quote(str(user), safe="") if user not in (None, "") else None
    password_enc = quote(str(password), safe="") if password not in (None, "") else None

    if user_enc is not None and password_enc is not None:
        credentials = f"{user_enc}:{password_enc}@"
    elif user_enc is not None:
        credentials = f"{user_enc}@"
    else:
        credentials = ""

    proxy_url = f"http://{credentials}{server}:{port}"
    display = entry.get("label") or f"{server}:{port}"

    auth_header = None
    if user not in (None, ""):
        auth_header = _basic_auth_str(str(user), "" if password in (None, "") else str(password))

    return {
        "proxies": {
            "http": proxy_url,
            "https": proxy_url,
        },
        "display": display,
        "auth_header": auth_header,
    }


def load_proxy_config(config_path: str = "proxy.json") -> Sequence[dict]:
    """
    Load proxy configuration from a JSON file.

    Supports either a single proxy object or a list of proxies. Example formats:

    Single proxy:
    {
        "server": "proxy.example.com",
        "port": 8080,
        "user": "username",
        "password": "secret"
    }

    Multiple proxies:
    [
        {"server": "...", "port": 3128, "user": "...", "password": "..."},
        {"server": "...", "port": 8080}
    ]

    or

    {
        "proxies": [
            {"server": "...", "port": 3128},
            {"server": "...", "port": 8080, "user": "...", "password": "..."}
        ]
    }
    """
    if not os.path.exists(config_path):
        return []

    try:
        with open(config_path, "r", encoding="utf-8") as handler:
            data = json.load(handler)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"⚠ Failed to read proxy config ({config_path}): {exc}")
        return []

    if isinstance(data, list):
        raw_entries = data
    elif isinstance(data, dict) and "proxies" in data:
        raw_entries = data.get("proxies", [])
    elif isinstance(data, dict):
        raw_entries = [data]
    else:
        raw_entries = []

    proxies: List[dict] = []
    for entry in raw_entries:
        normalized = _normalize_proxy_entry(entry)
        if normalized:
            proxies.append(normalized)

    if not proxies:
        print("⚠ Proxy config does not contain valid proxy entries - skipping proxy setup.")
        return []

    return proxies


def create_proxy_session(config_path: str = "proxy.json") -> Tuple[Union[requests.Session, "RotatingSession"], Optional[Sequence[dict]]]:
    """
    Create a requests.Session (or rotating session) configured with proxy settings.

    Returns a tuple of (session_like, proxy_entries or None).
    """
    proxies = load_proxy_config(config_path)

    if not proxies:
        session = requests.Session()
        session.trust_env = False
        return session, None

    if len(proxies) == 1:
        session = requests.Session()
        session.trust_env = False
        session.proxies.update(proxies[0]["proxies"])
        if proxies[0]["auth_header"]:
            session.headers["Proxy-Authorization"] = proxies[0]["auth_header"]
        else:
            session.headers.pop("Proxy-Authorization", None)
        print(f"Proxy enabled ({proxies[0]['display']})")
        return session, proxies

    rotator = RotatingSession(proxies)
    print(f"Proxy rotation enabled ({len(proxies)} proxies)")
    return rotator, proxies


class RotatingSession:
    """
    Lightweight proxy-rotating drop-in replacement for requests.Session.

    Attempts to resend failed requests (proxy/network errors or retryable HTTP statuses)
    through the next proxy in the list until all proxies are exhausted.
    """

    def __init__(self, proxy_entries: Sequence[dict]):
        if not proxy_entries:
            raise ValueError("proxy_entries must not be empty.")

        self._sessions: List[Tuple[requests.Session, str]] = []
        self._index: int = 0

        for entry in proxy_entries:
            session = requests.Session()
            session.trust_env = False
            session.proxies.update(entry["proxies"])
            if entry["auth_header"]:
                session.headers["Proxy-Authorization"] = entry["auth_header"]
            self._sessions.append((session, entry["display"]))

    def _rotate(self):
        if self._sessions:
            self._index = (self._index + 1) % len(self._sessions)

    def _current(self) -> Tuple[requests.Session, str]:
        return self._sessions[self._index]

    def request(self, method: str, url: str, **kwargs):
        attempts = len(self._sessions)
        last_error: Optional[Exception] = None

        for _ in range(attempts):
            session, display = self._current()
            try:
                response = session.request(method, url, **kwargs)
                if response.status_code in ROTATING_RETRY_STATUS_CODES:
                    print(f"Proxy {display} returned HTTP {response.status_code}, rotating...")
                    last_error = RequestException(f"HTTP {response.status_code}", response=response)
                    self._rotate()
                    continue
                return response
            except RequestException as exc:
                print(f"Proxy {display} failed ({exc}). Rotating to next proxy...")
                last_error = exc
                self._rotate()
                continue

        if last_error:
            raise last_error
        raise RuntimeError("Failed to perform request via proxy rotation.")

    def get(self, url: str, **kwargs):
        return self.request("GET", url, **kwargs)

    def post(self, url: str, **kwargs):
        return self.request("POST", url, **kwargs)

    def put(self, url: str, **kwargs):
        return self.request("PUT", url, **kwargs)

    def delete(self, url: str, **kwargs):
        return self.request("DELETE", url, **kwargs)

    def head(self, url: str, **kwargs):
        return self.request("HEAD", url, **kwargs)
