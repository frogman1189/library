-- -*- mode: sql; sql-product: postgres; -*-


-- NOTE: need to add trigger to book so that if a book instance is
-- removed it is removed from one of the owners - as typically there
-- will only be one book and owner this should typically not cause
-- problems. When there is more than one then problems can occur, but
-- only in traceability in saying that the one that was removed was
-- definately this persons.
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
	   cover_link text,
	   cover_data bytea,
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
       book_id SERIAL,
	   isbn isbn_t,
       person_id SERIAL,
       borrow_date timestamp DEFAULT current_timestamp NOT NULL,
       return_date timestamp,
       PRIMARY KEY(person_id, book_id, borrow_date),
       FOREIGN KEY(person_id) REFERENCES person(person_id),
       FOREIGN KEY(book_id) REFERENCES book(book_id),
	   FOREIGN KEY(isbn) REFERENCES meta_data(isbn)
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
       date_obtained timestamp DEFAULT current_timestamp NOT NULL, 
       date_released timestamp,
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
import json, requests
url = 'https://www.googleapis.com/books/v1/volumes?q=isbn:' + _isbn
meta_data_json = plpy.execute("SELECT gen.py_pgrest(%s);" % (plpy.quote_literal(url)))[0]['py_pgrest']
#
# remove garbage from api and convert to json object
json_object = json.loads(meta_data_json)['items'][0]['volumeInfo']
#
# Update Title
title = ''
description = ''
publisher = ''
cover_link = ''
cover_data = ''
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
try:
	cover_link = json_object['imageLinks']['thumbnail']
except:
	"""do nothing"""
try:
	cover_data = requests.request('GET', cover_link).content
except:
	"""do nothing"""
plpy.execute("UPDATE book.meta_data SET title = %s, description = %s, publisher = %s, cover_link = %s WHERE isbn = %s" %
(plpy.quote_literal(title), plpy.quote_literal(description), plpy.quote_literal(publisher), plpy.quote_literal(cover_link), plpy.quote_literal(_isbn)))
#
# Update Authors
for author in json_object['authors']:
    try:
        plpy.execute("INSERT INTO book.author VALUES (%s, %s)" %
        (plpy.quote_literal(_isbn), plpy.quote_literal(author)))
    except:
        """do nothing"""
return ''
#except:
#    return ''
$$
;

CREATE OR REPLACE FUNCTION add_book(_isbn text)
  RETURNS TABLE (isbn isbn_t, title text, author text[], publisher text, description text, cover_link text, cover_data bytea)
  LANGUAGE plpgsql
AS $$
   BEGIN
   IF (SELECT b.isbn FROM book.meta_data b WHERE b.isbn = _isbn) IS NULL THEN
	INSERT INTO book.meta_data VALUES (_isbn, null);
   END IF;
   --INSERT INTO book.book (isbn, state) VALUES (_isbn, 'available');
   PERFORM book.get_meta_data(_isbn);
   RETURN QUERY SELECT * FROM book.book_overview asd WHERE asd.isbn = _isbn;
   END;
$$;

CREATE TRIGGER update_borrowers_table_isbn_trigger
AFTER INSERT ON borrowers_table
FOR EACH ROW
EXECUTE PROCEDURE update_borrowers_table_isbn();

CREATE OR REPLACE FUNCTION update_borrowers_table_isbn()
RETURNS trigger
LANGUAGE plpgsql set search_path = book
AS $$
DECLARE
_isbn isbn_t;
BEGIN
SELECT isbn INTO _isbn FROM book WHERE book_id = NEW.book_id;
UPDATE borrowers_table SET isbn = _isbn WHERE book_id = NEW.book_id;
RETURN NEW;
END;
$$;

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
subString(m.description, 0, 100) as description,
substring(m.cover_link, 0, 20) as cover_link,
substring(m.cover_data, 0, 20) as cover_data
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
