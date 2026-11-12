"""Load the Olist CSV files into a single SQLite database (data/olist.db).

Run from the project root:  python src/build_db.py
"""
import sqlite3
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw"
DB = ROOT / "data" / "olist.db"

TABLES = {
    "orders": "olist_orders_dataset.csv",
    "order_items": "olist_order_items_dataset.csv",
    "customers": "olist_customers_dataset.csv",
    "products": "olist_products_dataset.csv",
    "order_payments": "olist_order_payments_dataset.csv",
    "order_reviews": "olist_order_reviews_dataset.csv",
    "sellers": "olist_sellers_dataset.csv",
    "category_translation": "product_category_name_translation.csv",
}

INDEXES = [
    "CREATE INDEX IF NOT EXISTS ix_orders_id ON orders(order_id)",
    "CREATE INDEX IF NOT EXISTS ix_orders_customer ON orders(customer_id)",
    "CREATE INDEX IF NOT EXISTS ix_items_order ON order_items(order_id)",
    "CREATE INDEX IF NOT EXISTS ix_items_product ON order_items(product_id)",
    "CREATE INDEX IF NOT EXISTS ix_customers_id ON customers(customer_id)",
    "CREATE INDEX IF NOT EXISTS ix_products_id ON products(product_id)",
    "CREATE INDEX IF NOT EXISTS ix_reviews_order ON order_reviews(order_id)",
]


def build(db_path: Path = DB) -> Path:
    if db_path.exists():
        db_path.unlink()
    with sqlite3.connect(db_path) as con:
        for table, file in TABLES.items():
            df = pd.read_csv(RAW / file)
            df.to_sql(table, con, index=False)
            print(f"{table:<22} {len(df):>8,} rows")
        for sql in INDEXES:
            con.execute(sql)
    return db_path


if __name__ == "__main__":
    build()
    print(f"Database written to {DB}")
