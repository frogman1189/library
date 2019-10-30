-- -*- mode: sql; sql-product: postgres; -*-

CREATE SCHEMA IF NOT EXISTS book;
SET search_path = book;

CREATE TYPE book_status_t AS ENUM(
       'borrowed',
       'overdue',
       'missing',
       'available',
       'revoked'
);

CREATE SEQUENCE book_id_sequence
  start 1
  increment 1
;
CREATE SEQUENCE person_id_sequence
  start 1
  increment 1
;

CREATE DOMAIN isbn_t AS varchar(16)
  CHECK(
    VALUE ~ '^\d{9}[\dX]?[\dX]?[\dX][\dX]?$'
);

CREATE DOMAIN book_id_t AS int;
CREATE DOMAIN person_id_t AS int;
CREATE DOMAIN ph_number_t AS varchar(32);

CREATE TABLE person (
       person_id person_id_t DEFAULT nextval('person_id_sequence') NOT NULL,
       f_name varchar(128),
       l_name varchar(128),
       email varchar(128),
       ph_number varchar(32),
       PRIMARY KEY (person_id)
);

CREATE TABLE book (
       book_id book_id_t DEFAULT nextval('book_id_sequence') NOT NULL,
       isbn isbn_t,
       copies int NOT NULL,
       state book_status_t NOT NULL,
       title varchar(256) NOT NULL,
       author varchar(128),
       description varchar(8192),
       cur_borrower person_id_t,
       cur_owner person_id_t,
       PRIMARY KEY (book_id),
       FOREIGN KEY (cur_borrower) REFERENCES person(person_id),
       FOREIGN KEY (cur_owner) REFERENCES person(person_id)
);

CREATE TABLE borrow_history (
       person_id person_id_t NOT NULL,
       book_id book_id_t NOT NULL,
       borrow_date date DEFAULT current_date NOT NULL,
       return_date date,
       PRIMARY KEY(person_id, book_id, borrow_date),
       FOREIGN KEY(person_id) REFERENCES person(person_id) ON UPDATE CASCADE ON DELETE CASCADE,
       FOREIGN KEY(book_id) REFERENCES book(book_id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE owner_history (
       person_id person_id_t NOT NULL,
       book_id book_id_t NOT NULL,
       date_owned date DEFAULT current_date NOT NULL,
       PRIMARY KEY (person_id, book_id, date_owned),
       FOREIGN KEY (person_id) REFERENCES person(person_id) ON DELETE CASCADE ON UPDATE CASCADE,
       FOREIGN KEY (book_id) REFERENCES book(book_id) ON DELETE CASCADE ON UPDATE CASCADE
);

--------------------------------------------------------------------------------
-- Functions
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION issue_book(_person_id person_id_t, _book_id book_id_t)
RETURNS bool
SET SEARCH_PATH = book
AS $$
DECLARE
  _cur_state  book_status_t;
BEGIN
  SELECT state INTO _cur_state FROM book WHERE book_id = _book_id;
  IF _cur_state = 'available' THEN
    UPDATE book SET state = 'borrowed',
      cur_borrower = _person_id
      WHERE book_id = _book_id;
    INSERT INTO borrow_history (person_id, book_id)
      VALUES (_person_id, _book_id);
    RETURN true;
  ELSE
    RAISE NOTICE 'book is not available';
      return false;
  END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION return_book(_book_id book_id_t)
RETURNS bool
SET SEARCH_PATH = book
AS $$
DECLARE
  _cur_state  book_status_t;
BEGIN
  SELECT state INTO _cur_state FROM book WHERE book_id = _book_id;
  IF _cur_state = 'borrowed' THEN
    UPDATE book SET state = 'available' WHERE book_id = _book_id;
    UPDATE borrow_history SET return_date = current_date
      WHERE book_id = _book_id
      AND   return_date IS NULL;
    RETURN true;
  ELSE
    RAISE NOTICE 'book is not borrowed currently';
    RETURN false;
  END IF;
END;
$$ LANGUAGE plpgsql;

--------------------------------------------------------------------------------
-- Views
--------------------------------------------------------------------------------

CREATE OR REPLACE VIEW available_books AS SELECT
--p.f_name || ' ' || p.l_name as owner,
b.title,
b.author
FROM book b LEFT JOIN person p
ON(b.cur_owner = p.person_id)
WHERE b.state = 'available';

SELECT * FROM available_books;

CREATE OR REPLACE VIEW borrowed_books AS SELECT
p.f_name || ' ' || p.l_name as borrower,
b.title,
b.author
FROM book b JOIN person p
ON(b.cur_borrower = p.person_id)
WHERE b.state = 'borrowed';

SELECT * FROM borrowed_books;

CREATE OR REPLACE VIEW book_owners AS
SELECT
b.book_id,
b.title,
b.author,
p.f_name || ' ' || p.l_name as name
FROM book b, person p
WHERE b.cur_owner = p.person_id;

--------------------------------------------------------------------------------
-- Useful SELECTS
--------------------------------------------------------------------------------

SELECT book_id, title, author, state FROM book ORDER BY book_id;

--------------------------------------------------------------------------------
-- Fill With Values
--------------------------------------------------------------------------------

INSERT INTO book (isbn, copies, state, title, author, description, cur_borrower, cur_owner)
VALUES
       (9780375843679, 1, 'available', 'Brain Jack', 'Brian Falkner', null, null, null),
       (9780752866505, 1, 'available', 'Asterix In Belgium', 'Rene Goscinny', null, null, null)
;

INSERT INTO person (f_name, l_name, email, ph_number) VALUES
       ('Logan', 'Warner', 'frogman1189@gmail.com', '0220489876'),
       ('Holly', 'Warner', null, null),
       ('Ashton', 'Warner', 'drflamemontgomery@gmail.com', null)
;

UPDATE book SET cur_owner = 1 WHERE book_id = 1;

UPDATE book SET cur_borrower = 1 WHERE book_id = 2;
UPDATE book SET state = 'borrowed' WHERE book_id = 2;

INSERT INTO book
--------------------------------------------------------------------------------
-- Alterations made to ddl
--------------------------------------------------------------------------------
ALTER TABLE book
  ADD COLUMN author varchar(128)
;

ALTER TABLE book
  ALTER COLUMN isbn SET DATA TYPE isbn_t;

