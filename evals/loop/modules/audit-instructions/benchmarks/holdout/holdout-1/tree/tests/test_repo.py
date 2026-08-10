from app.repo import get


def test_get_returns_item():
    assert get("abc").sku == "abc"
