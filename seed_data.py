"""
seed_data.py — Synthetic data generator for the Public Library Management System.

Generates realistic data using Faker + numpy:
  - 15 branches
  - 2,000 books across 12 genres
  - ~5,000 copies (popular books: 5-10 copies, rare: 1-2)
  - ~60 staff (3-5 per branch)
  - 3,000 patrons
  - ~20,000 loans spanning 3 years with seasonal peaks
  - ~1,500 holds
  - Fines from overdue loans

Usage:
    python seed_data.py --host localhost --user root --password yourpassword --database public_library
"""

import argparse
import random
from datetime import date, timedelta

import mysql.connector
from faker import Faker
from tqdm import tqdm

# ── reproducibility ──────────────────────────────────────────────────────────
SEED = 42
random.seed(SEED)
fake = Faker("en_US")
Faker.seed(SEED)

# ── constants ────────────────────────────────────────────────────────────────
NUM_BRANCHES    = 15
NUM_BOOKS       = 2_000
NUM_PATRONS     = 3_000
TARGET_COPIES   = 5_000
TARGET_LOANS    = 20_000
TARGET_HOLDS    = 1_500
FINE_PER_DAY    = 0.25   # $0.25 / overdue day
MAX_FINE        = 25.00  # cap per loan

LOAN_PERIOD_DAYS = 21    # standard 3-week loan
SIMULATION_START = date(2023, 1, 1)
SIMULATION_END   = date(2025, 12, 31)

GENRES = [
    "Fiction", "Mystery", "Science Fiction", "Fantasy", "Biography",
    "History", "Self-Help", "Romance", "Horror", "Thriller",
    "Children", "Young Adult",
]

# Weighted genre distribution (popular genres get more books)
GENRE_WEIGHTS = [0.16, 0.12, 0.11, 0.10, 0.08,
                 0.08, 0.07, 0.07, 0.06, 0.06,
                 0.05, 0.04]

CONDITIONS         = ["new", "good", "fair", "poor", "damaged"]
CONDITION_WEIGHTS  = [0.05, 0.45, 0.30, 0.15, 0.05]

HOLD_STATUSES      = ["waiting", "ready", "fulfilled", "cancelled"]
HOLD_STATUS_WEIGHTS= [0.20, 0.05, 0.55, 0.20]

STAFF_ROLES        = ["librarian", "assistant", "manager", "technician"]
STAFF_ROLE_WEIGHTS = [0.35, 0.40, 0.10, 0.15]

BRANCH_CITIES = [
    ("Central Branch",         "123 Main St",          "Springfield"),
    ("Westside Branch",        "456 Oak Ave",           "Shelbyville"),
    ("Northgate Branch",       "789 Pine Rd",           "Capital City"),
    ("Eastwood Branch",        "321 Elm Dr",            "Ogdenville"),
    ("Southpark Branch",       "654 Maple Blvd",        "North Haverbrook"),
    ("Riverside Branch",       "987 River Ln",          "Brockway"),
    ("Hilltop Branch",         "246 Summit Way",        "Waverly Hills"),
    ("Lakewood Branch",        "135 Shore Dr",          "Lake Wobegon"),
    ("Downtown Branch",        "801 Commerce St",       "Centerville"),
    ("University Branch",      "500 Campus Rd",         "Collegeville"),
    ("Parkview Branch",        "77 Greenway Blvd",      "Maplewood"),
    ("Harborlight Branch",     "30 Harbor View",        "Portside"),
    ("Sunridge Branch",        "1200 Sunrise Blvd",     "Sunridge"),
    ("Valley Creek Branch",    "88 Valley Rd",          "Valley Creek"),
    ("Meadowbrook Branch",     "210 Meadow Ln",         "Meadowbrook"),
]

OPENING_YEARS = [
    1965, 1978, 1982, 1990, 1994,
    1999, 2001, 2005, 2008, 2010,
    2012, 2015, 2017, 2019, 2022,
]

# ── helper functions ─────────────────────────────────────────────────────────

def seasonal_date(start: date, end: date) -> date:
    """
    Return a random date between start and end with seasonal peaks:
      - Summer (Jun-Aug): 2.2× base probability
      - Winter break (Dec-Jan): 1.9× base probability
      - Spring/Fall: 1× base probability
    Uses acceptance-rejection sampling.
    """
    delta = (end - start).days
    peak = 2.2
    while True:
        offset = random.randint(0, delta)
        candidate = start + timedelta(days=offset)
        m = candidate.month
        if m in (6, 7, 8):
            weight = 2.2
        elif m in (12, 1):
            weight = 1.9
        else:
            weight = 1.0
        if random.random() < weight / peak:
            return candidate


def rand_date(start: date, end: date) -> date:
    """Uniform random date in [start, end]."""
    return start + timedelta(days=random.randint(0, (end - start).days))


def batch_insert(cursor, table: str, columns: list[str], rows: list[tuple], batch_size: int = 1000):
    """Insert rows in batches to avoid memory issues."""
    placeholders = ", ".join(["%s"] * len(columns))
    col_str = ", ".join(columns)
    sql = f"INSERT INTO {table} ({col_str}) VALUES ({placeholders})"
    for i in range(0, len(rows), batch_size):
        cursor.executemany(sql, rows[i : i + batch_size])


# ── data generation functions ────────────────────────────────────────────────

def generate_branches() -> list[tuple]:
    rows = []
    for i, (name, address, city) in enumerate(BRANCH_CITIES):
        phone = fake.numerify("(###) ###-####")
        rows.append((name, address, city, phone, OPENING_YEARS[i]))
    return rows


def generate_title(genre: str) -> str:
    """Generate a realistic-sounding book title based on its genre."""
    if genre == "Fiction":
        return random.choice([
            f"The {fake.word().title()} of {fake.first_name()}",
            f"{fake.first_name()}'s {fake.word().title()}",
            f"A Tale of Two {fake.word().title()}s"
        ])
    elif genre == "Mystery":
        return random.choice([
            f"The {fake.last_name()} Mystery",
            f"Murder at {fake.city()}",
            f"The Case of the {fake.color_name().title()} {fake.word().title()}"
        ])
    elif genre == "Science Fiction":
        return random.choice([
            f"Beyond the {fake.word().title()} Star",
            f"The {fake.city()} Experiment",
            f"Return to {fake.word().title()} Prime"
        ])
    elif genre == "Fantasy":
        return random.choice([
            f"The {fake.color_name().title()} {fake.word().title()}",
            f"Sword of {fake.first_name()}",
            f"The Magic of {fake.city()}"
        ])
    elif genre == "Biography":
        return f"The Life of {fake.name()}"
    elif genre == "History":
        return random.choice([
            f"A History of {fake.city()}",
            f"The Fall of the {fake.last_name()} Empire",
            f"{fake.year()}: The Year of the {fake.word().title()}"
        ])
    elif genre == "Self-Help":
        return random.choice([
            f"How to {fake.word().title()} Your Life",
            f"The {fake.word().title()} Habit",
            f"Mastering the Art of {fake.word().title()}"
        ])
    elif genre == "Romance":
        return random.choice([
            f"Love in {fake.city()}",
            f"The {fake.color_name().title()} Rose",
            f"Meeting {fake.first_name()}"
        ])
    elif genre == "Horror":
        return random.choice([
            f"The {fake.word().title()} in the Dark",
            f"Terror at {fake.city()}",
            f"The Haunting of {fake.last_name()} House"
        ])
    elif genre == "Thriller":
        return random.choice([
            f"Escape from {fake.city()}",
            f"The {fake.word().title()} Conspiracy",
            f"Target: {fake.last_name()}"
        ])
    elif genre == "Children":
        return random.choice([
            f"The Magic {fake.word().title()}",
            f"{fake.first_name()} and the Giant {fake.word().title()}",
            f"Where the {fake.word().title()} Goes"
        ])
    elif genre == "Young Adult":
        return random.choice([
            f"The {fake.word().title()} Academy",
            f"Rebel of {fake.city()}",
            f"The {fake.color_name().title()} Mark"
        ])
    else:
        return fake.sentence(nb_words=3)[:-1].title()

def generate_books() -> list[tuple]:
    rows = []
    seen_isbns: set[str] = set()

    authors = [fake.name() for _ in range(200)]   # pool of ~200 authors

    for _ in range(NUM_BOOKS):
        genre = random.choices(GENRES, weights=GENRE_WEIGHTS, k=1)[0]
        author = random.choice(authors)
        title = generate_title(genre)
        pub_year = random.randint(1950, 2024)

        # unique ISBN-13
        while True:
            isbn = fake.isbn13(separator="")
            if isbn not in seen_isbns:
                seen_isbns.add(isbn)
                break

        description = fake.paragraph(nb_sentences=3)
        rows.append((title, author, genre, pub_year, isbn, description))
    return rows


def generate_staff(branch_ids: list[int]) -> list[tuple]:
    rows = []
    seen_emails: set[str] = set()
    for branch_id in branch_ids:
        count = random.randint(3, 5)
        for _ in range(count):
            name  = fake.name()
            while True:
                email = fake.unique.email()
                if email not in seen_emails:
                    seen_emails.add(email)
                    break
            role      = random.choices(STAFF_ROLES, weights=STAFF_ROLE_WEIGHTS, k=1)[0]
            hire_date = rand_date(date(2000, 1, 1), date(2024, 1, 1))
            rows.append((name, email, branch_id, role, str(hire_date)))
    return rows


def generate_patrons(branch_ids: list[int]) -> list[tuple]:
    rows = []
    seen_emails: set[str] = set()
    for _ in range(NUM_PATRONS):
        name    = fake.name()
        while True:
            email = fake.unique.email()
            if email not in seen_emails:
                seen_emails.add(email)
                break
        phone       = fake.numerify("(###) ###-####")
        signup_date = rand_date(date(2015, 1, 1), date(2025, 6, 1))
        home_branch = random.choice(branch_ids)
        is_active   = random.random() < 0.90    # 90% active
        rows.append((name, email, phone, str(signup_date), home_branch, is_active))
    return rows


def generate_copies(book_ids: list[int], branch_ids: list[int]) -> list[tuple]:
    """
    Distribute copies across branches.
    ~20% of books (popular) get 5-10 copies, ~30% get 2-4, ~50% (rare) get 1-2.
    Total target: ~5,000.
    """
    rows = []
    for book_id in book_ids:
        r = random.random()
        if r < 0.20:          # popular
            n_copies = random.randint(5, 10)
        elif r < 0.50:        # mid-tier
            n_copies = random.randint(2, 4)
        else:                 # rare
            n_copies = random.randint(1, 2)

        selected_branches = random.choices(branch_ids, k=n_copies)
        for branch_id in selected_branches:
            condition = random.choices(CONDITIONS, weights=CONDITION_WEIGHTS, k=1)[0]
            acq_date  = rand_date(date(2010, 1, 1), date(2024, 6, 1))
            rows.append((book_id, branch_id, condition, str(acq_date)))
    return rows


def generate_loans(
    copy_ids: list[int],
    patron_ids: list[int],
    staff_ids: list[int],
) -> list[tuple]:
    """
    Generate ~20,000 loans over 3 years with seasonal peaks.
    ~12% of loans are still unreturned (open).
    ~15% of returned loans were returned late.
    """
    rows = []
    for _ in range(TARGET_LOANS):
        copy_id    = random.choice(copy_ids)
        patron_id  = random.choice(patron_ids)
        staff_id   = random.choice(staff_ids) if random.random() < 0.85 else None

        checkout_date = seasonal_date(SIMULATION_START, SIMULATION_END)
        due_date      = checkout_date + timedelta(days=LOAN_PERIOD_DAYS)

        r = random.random()
        if r < 0.12:
            # Still checked out (open loan)
            return_date = None
        elif r < 0.27:
            # Returned late (overdue)
            days_late   = random.randint(1, 90)
            return_date = due_date + timedelta(days=days_late)
        else:
            # Returned on time
            days_early  = random.randint(0, LOAN_PERIOD_DAYS)
            return_date = checkout_date + timedelta(days=days_early)
            if return_date > due_date:
                return_date = due_date

        # Ensure return_date not in the future for closed loans
        if return_date and return_date > date.today():
            return_date = date.today()

        rows.append((
            copy_id,
            patron_id,
            str(checkout_date),
            str(due_date),
            str(return_date) if return_date else None,
            staff_id,
        ))
    return rows


def generate_holds(book_ids: list[int], patron_ids: list[int]) -> list[tuple]:
    rows = []
    for _ in range(TARGET_HOLDS):
        book_id    = random.choice(book_ids)
        patron_id  = random.choice(patron_ids)
        request_date = rand_date(SIMULATION_START, SIMULATION_END)
        status       = random.choices(HOLD_STATUSES, weights=HOLD_STATUS_WEIGHTS, k=1)[0]

        if status in ("fulfilled", "ready"):
            wait_days      = random.randint(1, 30)
            fulfilled_date = request_date + timedelta(days=wait_days)
            if fulfilled_date > date.today():
                fulfilled_date = date.today()
        else:
            fulfilled_date = None

        rows.append((
            book_id, patron_id,
            str(request_date), status,
            str(fulfilled_date) if fulfilled_date else None,
        ))
    return rows


def generate_fines(cursor) -> list[tuple]:
    """
    Query overdue loans from DB (already inserted) and create fines.
    Fine = $0.25/day overdue, capped at $25.00.
    ~60% of fines are paid.
    """
    cursor.execute("""
        SELECT id, due_date, return_date
        FROM loans
        WHERE
            -- returned late
            (return_date IS NOT NULL AND return_date > due_date)
            -- still out and past due date
            OR (return_date IS NULL AND due_date < CURDATE())
    """)
    overdue = cursor.fetchall()

    rows = []
    for loan_id, due_date_val, return_date_val in overdue:
        # Convert if they come back as strings
        if isinstance(due_date_val, str):
            due_date_val = date.fromisoformat(due_date_val)
        if isinstance(return_date_val, str):
            return_date_val = date.fromisoformat(return_date_val)

        ref_date    = return_date_val if return_date_val else date.today()
        days_late   = (ref_date - due_date_val).days
        amount      = min(round(days_late * FINE_PER_DAY, 2), MAX_FINE)
        if amount <= 0:
            continue

        paid = random.random() < 0.60
        if paid:
            paid_date = ref_date + timedelta(days=random.randint(0, 180))
            if paid_date > date.today():
                paid_date = date.today()
        else:
            paid_date = None

        rows.append((
            loan_id, amount, paid,
            str(paid_date) if paid_date else None,
        ))
    return rows


# ── main ─────────────────────────────────────────────────────────────────────

def main(host: str, user: str, password: str, database: str, port: int):
    print(f"\n  Public Library Seed Data Generator")
    print(f"    Target: {host}:{port} / {database}\n")

    conn = mysql.connector.connect(
        host=host, user=user, password=password,
        database=database, port=port,
        autocommit=False,
    )
    cur = conn.cursor()

    # ── branches ──────────────────────────────────────────────────────────────
    print("  Inserting branches …")
    branch_rows = generate_branches()
    batch_insert(cur, "branches",
                 ["name", "address", "city", "phone", "opening_year"],
                 branch_rows)
    conn.commit()

    cur.execute("SELECT id FROM branches")
    branch_ids = [r[0] for r in cur.fetchall()]
    print(f"    - {len(branch_ids)} branches inserted")

    # ── books ─────────────────────────────────────────────────────────────────
    print("  Inserting books …")
    book_rows = generate_books()
    batch_insert(cur, "books",
                 ["title", "author", "genre", "publication_year", "isbn", "description"],
                 book_rows)
    conn.commit()

    cur.execute("SELECT id FROM books")
    book_ids = [r[0] for r in cur.fetchall()]
    print(f"    - {len(book_ids)} books inserted")

    # ── staff ─────────────────────────────────────────────────────────────────
    print("  Inserting staff …")
    staff_rows = generate_staff(branch_ids)
    batch_insert(cur, "staff",
                 ["name", "email", "branch_id", "role", "hire_date"],
                 staff_rows)
    conn.commit()

    cur.execute("SELECT id FROM staff")
    staff_ids = [r[0] for r in cur.fetchall()]
    print(f"    - {len(staff_ids)} staff inserted")

    # ── patrons ───────────────────────────────────────────────────────────────
    print("  Inserting patrons …")
    patron_rows = generate_patrons(branch_ids)
    batch_insert(cur, "patrons",
                 ["name", "email", "phone", "signup_date", "home_branch_id", "is_active"],
                 patron_rows)
    conn.commit()

    cur.execute("SELECT id FROM patrons")
    patron_ids = [r[0] for r in cur.fetchall()]
    print(f"    - {len(patron_ids)} patrons inserted")

    # ── copies ────────────────────────────────────────────────────────────────
    print("  Inserting copies …")
    copy_rows = generate_copies(book_ids, branch_ids)
    batch_insert(cur, "copies",
                 ["book_id", "branch_id", "copy_condition", "acquisition_date"],
                 copy_rows)
    conn.commit()

    cur.execute("SELECT id FROM copies")
    copy_ids = [r[0] for r in cur.fetchall()]
    print(f"    - {len(copy_ids)} copies inserted")

    # ── loans ─────────────────────────────────────────────────────────────────
    print("  Inserting loans …")
    loan_rows = generate_loans(copy_ids, patron_ids, staff_ids)
    batch_insert(cur, "loans",
                 ["copy_id", "patron_id", "checkout_date", "due_date", "return_date", "staff_id"],
                 loan_rows)
    conn.commit()
    print(f"    - {len(loan_rows)} loans inserted")

    # ── holds ─────────────────────────────────────────────────────────────────
    print("  Inserting holds …")
    hold_rows = generate_holds(book_ids, patron_ids)
    batch_insert(cur, "holds",
                 ["book_id", "patron_id", "request_date", "status", "fulfilled_date"],
                 hold_rows)
    conn.commit()
    print(f"    - {len(hold_rows)} holds inserted")

    # ── fines (derived from DB) ───────────────────────────────────────────────
    print("  Generating fines from overdue loans …")
    fine_rows = generate_fines(cur)
    batch_insert(cur, "fines",
                 ["loan_id", "amount", "paid", "paid_date"],
                 fine_rows)
    conn.commit()
    print(f"    - {len(fine_rows)} fines inserted")

    cur.close()
    conn.close()

    print("\n  Seed data generation complete!\n")
    print("    Run verification:")
    print("    SELECT 'branches', COUNT(*) FROM branches")
    print("    UNION ALL SELECT 'books',   COUNT(*) FROM books")
    print("    UNION ALL SELECT 'copies',  COUNT(*) FROM copies")
    print("    UNION ALL SELECT 'patrons', COUNT(*) FROM patrons")
    print("    UNION ALL SELECT 'loans',   COUNT(*) FROM loans")
    print("    UNION ALL SELECT 'holds',   COUNT(*) FROM holds")
    print("    UNION ALL SELECT 'fines',   COUNT(*) FROM fines;\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Seed the public_library database")
    parser.add_argument("--host",     default="localhost",      help="MySQL host")
    parser.add_argument("--port",     default=3306, type=int,   help="MySQL port")
    parser.add_argument("--user",     default="root",           help="MySQL username")
    parser.add_argument("--password", default="",               help="MySQL password")
    parser.add_argument("--database", default="public_library", help="Target database name")
    args = parser.parse_args()

    main(
        host=args.host,
        user=args.user,
        password=args.password,
        database=args.database,
        port=args.port,
    )
