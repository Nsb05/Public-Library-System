-- =============================================================================
-- PUBLIC LIBRARY MANAGEMENT SYSTEM — schema.sql
-- Database: MySQL 8.0+
-- Encoding: UTF8MB4
-- Description: Full DDL for a multi-branch public library system.
--              Normalized to 3NF with proper FK constraints and CHECK constraints.
-- =============================================================================

-- WARNING: Drops and recreates the database for a clean install.
--          Comment out the next line if you want to preserve existing data.
DROP DATABASE IF EXISTS public_library;

CREATE DATABASE IF NOT EXISTS public_library
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE public_library;

-- =============================================================================
-- TABLE: branches
-- Represents physical library branches in the system.
-- =============================================================================
CREATE TABLE IF NOT EXISTS branches (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    name         VARCHAR(100)  NOT NULL,
    address      VARCHAR(200)  NOT NULL,
    city         VARCHAR(100)  NOT NULL,
    phone        VARCHAR(20),
    opening_year SMALLINT      NOT NULL,
    created_at   TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_branches_opening_year
        CHECK (opening_year BETWEEN 1800 AND 2100)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- =============================================================================
-- TABLE: books
-- Represents unique bibliographic titles. One title can have many physical copies.
-- =============================================================================
CREATE TABLE IF NOT EXISTS books (
    id               INT AUTO_INCREMENT PRIMARY KEY,
    title            VARCHAR(300)  NOT NULL,
    author           VARCHAR(200)  NOT NULL,
    genre            VARCHAR(50)   NOT NULL,
    publication_year SMALLINT      NOT NULL,
    isbn             VARCHAR(20)   NOT NULL,
    description      TEXT,
    created_at       TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_books_isbn
        UNIQUE (isbn),
    CONSTRAINT chk_books_publication_year
        CHECK (publication_year BETWEEN 1000 AND 2100)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- =============================================================================
-- TABLE: staff
-- Library employees, each assigned to a branch.
-- =============================================================================
CREATE TABLE IF NOT EXISTS staff (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    name       VARCHAR(200)  NOT NULL,
    email      VARCHAR(200)  NOT NULL,
    branch_id  INT           NOT NULL,
    role       ENUM('librarian', 'assistant', 'manager', 'technician') NOT NULL,
    hire_date  DATE          NOT NULL,
    created_at TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_staff_email
        UNIQUE (email),
    CONSTRAINT fk_staff_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- =============================================================================
-- TABLE: patrons
-- Library card holders. Each has a home branch.
-- =============================================================================
CREATE TABLE IF NOT EXISTS patrons (
    id             INT AUTO_INCREMENT PRIMARY KEY,
    name           VARCHAR(200)  NOT NULL,
    email          VARCHAR(200)  NOT NULL,
    phone          VARCHAR(20),
    signup_date    DATE          NOT NULL,
    home_branch_id INT           NOT NULL,
    is_active      BOOL          NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_patrons_email
        UNIQUE (email),
    CONSTRAINT fk_patrons_home_branch
        FOREIGN KEY (home_branch_id) REFERENCES branches (id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- =============================================================================
-- TABLE: copies
-- A physical copy of a book held at a specific branch.
-- One book can have many copies across many branches (one-to-many).
-- =============================================================================
CREATE TABLE IF NOT EXISTS copies (
    id               INT AUTO_INCREMENT PRIMARY KEY,
    book_id          INT           NOT NULL,
    branch_id        INT           NOT NULL,
    copy_condition   ENUM('new', 'good', 'fair', 'poor', 'damaged') NOT NULL DEFAULT 'good',
    acquisition_date DATE          NOT NULL,

    CONSTRAINT fk_copies_book
        FOREIGN KEY (book_id) REFERENCES books (id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT fk_copies_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- =============================================================================
-- TABLE: loans
-- A patron checking out a physical copy. return_date is NULL if not returned.
-- =============================================================================
CREATE TABLE IF NOT EXISTS loans (
    id            INT AUTO_INCREMENT PRIMARY KEY,
    copy_id       INT  NOT NULL,
    patron_id     INT  NOT NULL,
    checkout_date DATE NOT NULL,
    due_date      DATE NOT NULL,
    return_date   DATE,          -- NULL means currently checked out
    staff_id      INT,           -- staff member who processed checkout (optional)

    CONSTRAINT fk_loans_copy
        FOREIGN KEY (copy_id) REFERENCES copies (id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT fk_loans_patron
        FOREIGN KEY (patron_id) REFERENCES patrons (id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT fk_loans_staff
        FOREIGN KEY (staff_id) REFERENCES staff (id)
        ON DELETE SET NULL
        ON UPDATE CASCADE,
    CONSTRAINT chk_loans_due_after_checkout
        CHECK (due_date > checkout_date),
    CONSTRAINT chk_loans_return_after_checkout
        CHECK (return_date IS NULL OR return_date >= checkout_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- =============================================================================
-- TABLE: holds
-- A reservation a patron places on a book title.
-- status progression: waiting → ready → fulfilled
--                  or waiting → cancelled
-- =============================================================================
CREATE TABLE IF NOT EXISTS holds (
    id             INT AUTO_INCREMENT PRIMARY KEY,
    book_id        INT  NOT NULL,
    patron_id      INT  NOT NULL,
    request_date   DATE NOT NULL,
    status         ENUM('waiting', 'ready', 'fulfilled', 'cancelled') NOT NULL DEFAULT 'waiting',
    fulfilled_date DATE,          -- NULL until status = 'fulfilled' or 'ready'

    CONSTRAINT fk_holds_book
        FOREIGN KEY (book_id) REFERENCES books (id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT fk_holds_patron
        FOREIGN KEY (patron_id) REFERENCES patrons (id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- =============================================================================
-- TABLE: fines
-- A fine issued for an overdue loan. One fine per loan (UNIQUE on loan_id).
-- =============================================================================
CREATE TABLE IF NOT EXISTS fines (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    loan_id    INT            NOT NULL,
    amount     DECIMAL(8, 2)  NOT NULL,
    paid       BOOL           NOT NULL DEFAULT FALSE,
    paid_date  DATE,                    -- NULL until paid = TRUE
    created_at TIMESTAMP      DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_fines_loan
        UNIQUE (loan_id),
    CONSTRAINT fk_fines_loan
        FOREIGN KEY (loan_id) REFERENCES loans (id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT chk_fines_amount_positive
        CHECK (amount > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- =============================================================================
-- INDEXES
-- Added on all FKs (MySQL doesn't auto-index all of them) and
-- frequently filtered columns (checkout_date, due_date, return_date, status).
-- =============================================================================

-- copies
CREATE INDEX idx_copies_book_id        ON copies   (book_id);
CREATE INDEX idx_copies_branch_id      ON copies   (branch_id);

-- loans
CREATE INDEX idx_loans_copy_id         ON loans    (copy_id);
CREATE INDEX idx_loans_patron_id       ON loans    (patron_id);
CREATE INDEX idx_loans_staff_id        ON loans    (staff_id);
CREATE INDEX idx_loans_checkout_date   ON loans    (checkout_date);
CREATE INDEX idx_loans_due_date        ON loans    (due_date);
CREATE INDEX idx_loans_return_date     ON loans    (return_date);

-- holds
CREATE INDEX idx_holds_book_id         ON holds    (book_id);
CREATE INDEX idx_holds_patron_id       ON holds    (patron_id);
CREATE INDEX idx_holds_status          ON holds    (status);
CREATE INDEX idx_holds_request_date    ON holds    (request_date);

-- fines
CREATE INDEX idx_fines_paid            ON fines    (paid);

-- staff
CREATE INDEX idx_staff_branch_id       ON staff    (branch_id);

-- patrons
CREATE INDEX idx_patrons_home_branch   ON patrons  (home_branch_id);
CREATE INDEX idx_patrons_signup_date   ON patrons  (signup_date);

-- books
CREATE INDEX idx_books_genre           ON books    (genre);
CREATE INDEX idx_books_author          ON books    (author);


-- =============================================================================
-- VIEWS (Stretch Goals)
-- Reusable query logic surfaced as views for dashboards and reporting.
-- =============================================================================

-- View 1: active_loans
-- All currently checked-out loans (not yet returned), with patron and book details.
CREATE OR REPLACE VIEW active_loans AS
SELECT
    l.id                                      AS loan_id,
    l.checkout_date,
    l.due_date,
    DATEDIFF(CURDATE(), l.due_date)           AS days_overdue,    -- negative = not yet due
    p.id                                      AS patron_id,
    p.name                                    AS patron_name,
    p.email                                   AS patron_email,
    b.id                                      AS book_id,
    b.title                                   AS book_title,
    b.author                                  AS book_author,
    br.id                                     AS branch_id,
    br.name                                   AS branch_name
FROM loans l
JOIN copies  c  ON c.id  = l.copy_id
JOIN books   b  ON b.id  = c.book_id
JOIN patrons p  ON p.id  = l.patron_id
JOIN branches br ON br.id = c.branch_id
WHERE l.return_date IS NULL;


-- View 2: overdue_loans
-- Subset of active_loans where the due date has passed.
CREATE OR REPLACE VIEW overdue_loans AS
SELECT *
FROM active_loans
WHERE days_overdue > 0;


-- View 3: branch_summary
-- Per-branch aggregate snapshot: copies, active loans, holds, staff count.
CREATE OR REPLACE VIEW branch_summary AS
SELECT
    br.id                                     AS branch_id,
    br.name                                   AS branch_name,
    br.city,
    br.opening_year,
    COUNT(DISTINCT c.id)                      AS total_copies,
    COUNT(DISTINCT s.id)                      AS total_staff,
    COUNT(DISTINCT p.id)                      AS total_patrons,
    COUNT(DISTINCT al.loan_id)                AS active_loans,
    COUNT(DISTINCT h.id)                      AS pending_holds
FROM branches br
LEFT JOIN copies   c  ON c.branch_id  = br.id
LEFT JOIN staff    s  ON s.branch_id  = br.id
LEFT JOIN patrons  p  ON p.home_branch_id = br.id
LEFT JOIN active_loans al ON al.branch_id = br.id
LEFT JOIN holds    h  ON h.book_id IN (
                            SELECT book_id FROM copies WHERE branch_id = br.id
                         ) AND h.status IN ('waiting', 'ready')
GROUP BY br.id, br.name, br.city, br.opening_year;
