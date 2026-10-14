import os

import psycopg
from psycopg.rows import dict_row


class Database:
    """PostgreSQL connection manager for the library platform."""

    def connect(self):
        """Create a PostgreSQL connection using environment variables."""
        required = ("DB_HOST", "DB_NAME", "DB_USER", "DB_PASSWORD")
        missing = [name for name in required if not os.environ.get(name)]

        if missing:
            raise RuntimeError(
                "Missing required database environment variables: "
                + ", ".join(missing)
            )

        return psycopg.connect(
            host=os.environ["DB_HOST"],
            port=os.environ.get("DB_PORT", "5432"),
            dbname=os.environ["DB_NAME"],
            user=os.environ["DB_USER"],
            password=os.environ["DB_PASSWORD"],
            connect_timeout=5,
            row_factory=dict_row,
        )


db = Database()
