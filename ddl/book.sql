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
-- Fill With Values
--------------------------------------------------------------------------------

INSERT INTO book (isbn, copies, state, title, author, description, cur_borrower, cur_owner)
VALUES
       (9780375843679, 1, 'available', 'Brain Jack', 'Brian Falkner', null, null, null)
;

INSERT INTO person (f_name, l_name, email, ph_number) VALUES
       ('Logan', 'Warner', 'frogman1189@gmail.com', '0220489876')
       ('Holly', 'Warner', null, null)
;

--------------------------------------------------------------------------------
-- Alterations made to ddl
--------------------------------------------------------------------------------
ALTER TABLE book
  ADD COLUMN author varchar(128)
;

ALTER TABLE book
  ALTER COLUMN isbn SET DATA TYPE isbn_t;

