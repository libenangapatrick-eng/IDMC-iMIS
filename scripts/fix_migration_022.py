from pathlib import Path

path = Path(r"C:\Users\liben\Documents\IDMC_iMIS\supabase\migrations\202609150022_finance_integrity_automation.sql")
text = path.read_text(encoding="utf-8")

text = text.replace(
    "i.total,",
    "i.total_amount,"
)

text = text.replace(
    "total = greatest(",
    "total_amount = greatest("
)

text = text.replace(
    "total = greatest(\n            v_total",
    "total_amount = greatest(\n            v_total"
)

path.write_text(text, encoding="utf-8")

# Keep the database/migrations copy synchronized.
database_path = Path(
    r"C:\Users\liben\Documents\IDMC_iMIS\database\migrations\202609150022_finance_integrity_automation.sql"
)
database_path.write_text(text, encoding="utf-8")

print("Migration 022 corrected successfully.")
print(f"Supabase migration size: {path.stat().st_size} bytes")
print(f"Database migration size: {database_path.stat().st_size} bytes")

if "i.total," in text:
    print("WARNING: old i.total reference still exists.")
else:
    print("OK: i.total reference removed.")

if "i.total_amount," in text:
    print("OK: i.total_amount reference exists.")
else:
    print("WARNING: i.total_amount reference not found.")
