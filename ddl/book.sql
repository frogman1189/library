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

CREATE DOMAIN isbn_t AS varchar(16)
  CHECK(
    VALUE ~ '^\d{9}[\dX]?[\dX]?[\dX][\dX]?$'
);

CREATE DOMAIN ph_number_t AS varchar(32);

CREATE TABLE person (
       person_id SERIAL,
       f_name text,
       l_name text,
       email text,
       ph_number ph_number_t,
       PRIMARY KEY (person_id)
);

CREATE TABLE meta_data (
       isbn isbn_t,
       title text,
	   description text,
	   publisher text,
       PRIMARY KEY (isbn)
);


CREATE TABLE author (
       isbn isbn_t,
       author_name text,
       PRIMARY KEY (isbn, author_name),
       FOREIGN KEY (isbn) REFERENCES meta_data
);

CREATE TABLE book (
       book_id SERIAL,
       isbn isbn_t NOT NULL,
       state book_status_t NOT NULL,
       PRIMARY KEY (book_id),
       FOREIGN KEY (isbn) REFERENCES meta_data
         ON DELETE CASCADE
);

CREATE TABLE borrowers_table (
       borrowed_book_id SERIAL,
       person_id SERIAL,
       book_id SERIAL,
       borrow_date date DEFAULT current_date NOT NULL,
       return_date date,
       PRIMARY KEY(person_id, book_id, borrow_date),
       FOREIGN KEY(person_id) REFERENCES person(person_id)
         ON UPDATE CASCADE ON DELETE CASCADE,
       FOREIGN KEY(book_id) REFERENCES book(book_id)
         ON UPDATE CASCADE ON DELETE CASCADE
);

/***************************** 
 * keeps track of ownership of a certain book isbn
 * it does not distinguish between specific book if there is
 * more than one of that type, but does say how many of that
 * type of book the person owns
 * also it only keeps a record of when the first book of that isbn was
 * obtained, and only when the last one was released does it update
 * date_released.
 *****************************/

CREATE TABLE ownership_table (
       person_id SERIAL NOT NULL,
       isbn isbn_t NOT NULL,
       copies int,
       date_obtained date DEFAULT current_date NOT NULL, 
       date_released date,
       PRIMARY KEY (person_id, isbn, date_obtained),
       FOREIGN KEY (person_id) REFERENCES person(person_id)
         ON DELETE CASCADE ON UPDATE CASCADE,
       FOREIGN KEY (isbn) REFERENCES meta_data(isbn)
         ON DELETE CASCADE ON UPDATE CASCADE
);

--------------------------------------------------------------------------------
-- Functions
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION get_meta_data(_isbn text)
  RETURNS text
  LANGUAGE plpython3u
AS $$
import json
url = 'https://www.googleapis.com/books/v1/volumes?q=isbn:' + _isbn
meta_data_json = plpy.execute("SELECT gen.py_pgrest(%s);" % (plpy.quote_literal(url)))[0]['py_pgrest']
#
# remove garbage from api and convert to json object
json_object = json.loads(meta_data_json)['items'][0]['volumeInfo']
#
# Update Title
title = None
description = None
publisher = None
try:
	title = json_object['title']
except:
	"""do nothing"""
try:
	description = json_object['description']
except:
	"""do nothing"""
try:
	publisher = json_object['publisher']
except:
	"""do nothing"""
plpy.execute("UPDATE book.meta_data SET title = %s, description = %s, publisher = %s WHERE isbn = %s" %
(plpy.quote_literal(title), plpy.quote_literal(title), plpy.quote_literal(title), plpy.quote_literal(_isbn)))
#
# Update Authors
for author in json_object['authors']:
    try:
        plpy.execute("INSERT INTO book.author VALUES (%s, %s)" %
        (plpy.quote_literal(_isbn), plpy.quote_literal(author)))
    except:
        """do nothing"""
try:
    plpy.execute("INSERT INTO book.me VALUES (%s, %s)" %
    (plpy.quote_literal(_isbn), plpy.quote_literal(author)))
except:
    """do nothing"""
return ''
#except:
#    return ''
$$
;

CREATE OR REPLACE FUNCTION add_book(_isbn text)
  RETURNS TABLE (isbn isbn_t, title text, author text[], publisher text, description text)
  LANGUAGE plpgsql
AS $$
   BEGIN
   IF (SELECT b.isbn FROM book.meta_data b WHERE b.isbn = _isbn) IS NULL THEN
	INSERT INTO book.meta_data VALUES (_isbn, null);
   END IF;
   INSERT INTO book.book (isbn, state) VALUES (_isbn, 'available');
   PERFORM book.get_meta_data(_isbn);
   RETURN QUERY SELECT * FROM book.book_overview asd WHERE asd.isbn = _isbn;
   END;
$$;


/*CREATE OR REPLACE FUNCTION issue_book(_person_id person_id_t, _book_id book_id_t)
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

CREATE OR REPLACE FUNCTION add_book(_isbn isbn_t)
RETURNS */

--------------------------------------------------------------------------------
-- Views
--------------------------------------------------------------------------------

/*CREATE OR REPLACE VIEW book_overview AS SELECT
m.isbn,
m.title,
a.author_name,
p.publisher_name,
e.excerpt,
s.subject_name
FROM meta_data m, author a, publisher p, excerpts e, subject s
WHERE m.isbn = a.isbn
AND   m.isbn = p.isbn
AND   m.isbn = e.isbn
AND   m.isbn = s.isbn;*/

CREATE OR REPLACE VIEW author_agg AS SELECT
isbn,
array_agg(author_name) as author
FROM author
GROUP BY isbn;

CREATE OR REPLACE VIEW book_overview AS SELECT
m.isbn,
m.title,
a.author,
m.publisher,
m.description
FROM meta_data m
JOIN author_agg a ON (m.isbn = a.isbn)
GROUP BY m.isbn, a.author;

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


CREATE OR REPLACE VIEW book_owners AS
SELECT
b.book_id,
b.title,
b.author,
p.f_name || ' ' || p.l_name as name
FROM book b, person p
WHERE b.cur_owner = p.person_id;
