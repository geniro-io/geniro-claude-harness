from concurrent.futures import ThreadPoolExecutor

import requests

_pool = ThreadPoolExecutor(max_workers=8)


def fetch_status(url: str) -> int:
    return requests.get(url, timeout=10).status_code


def submit(url: str):
    return _pool.submit(fetch_status, url)
