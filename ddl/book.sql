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
       person_id person_id_t,
       book_id book_id_t,
       borrow_date date,
       return_date date,
       PRIMARY KEY(person_id, book_id, borrow_date),
       FOREIGN KEY(person_id) REFERENCES person(person_id) ON UPDATE CASCADE ON DELETE CASCADE,
       FOREIGN KEY(book_id) REFERENCES book(book_id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE owner_history (
       person_id person_id_t,
       book_id book_id_t,
       date_owned date,
       PRIMARY KEY (person_id, book_id, date_owned),
       FOREIGN KEY (person_id) REFERENCES person(person_id) ON DELETE CASCADE ON UPDATE CASCADE,
       FOREIGN KEY (book_id) REFERENCES book(book_id) ON DELETE CASCADE ON UPDATE CASCADE
);

--------------------------------------------------------------------------------
-- Functions
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION issue_book(_book_id book_id_t, _person_id person_id_t)
RETURNS NULL
LANGUAGE sql
AS $$
SELECT


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
--------------------------------------------------------------------------------
-- Fill With Values
--------------------------------------------------------------------------------

INSERT INTO book (isbn, copies, state, title, author, description, cur_borrower, cur_owner)
VALUES
--       (9780375843679, 1, 'available', 'Brain Jack', 'Brian Falkner', null, null, null)
       (9780752866505, 1, 'available', 'Asterix In Belgium', 'Rene Goscinny', null, null, null)
;

INSERT INTO person (f_name, l_name, email, ph_number) VALUES
       ('Logan', 'Warner', 'frogman1189@gmail.com', '0220489876')
       ('Holly', 'Warner', null, null)
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

