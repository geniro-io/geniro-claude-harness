import os


class Settings:
    database_url = os.environ.get("DATABASE_URL", "")
    page_size = int(os.environ.get("PAGE_SIZE", "50"))


settings = Settings()
