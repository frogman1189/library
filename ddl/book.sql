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
       f_name varchar(128),
       l_name varchar(128),
       email varchar(128),
       ph_number varchar(32),
       PRIMARY KEY (person_id)
);

CREATE TABLE author (
       isbn isbn_t,
       author_name varchar(256),
       PRIMARY KEY (isbn, author_name),
       FOREIGN KEY (isbn) REFERENCES meta_data
);

CREATE TABLE subject (
	   isbn isbn_t,
	   subject_name varchar(64),
	   PRIMARY KEY(isbn, subject_name),
	   FOREIGN KEY (isbn) REFERENCES meta_data
);

CREATE TABLE publisher (
	   isbn isbn_t,
       publisher_name varchar(256),
       PRIMARY KEY(isbn, publisher_name),
	   FOREIGN KEY (isbn) REFERENCES meta_data
);

CREATE TABLE excerpt (
	   isbn isbn_t,
	   excerpt varchar(8092),
	   PRIMARY KEY (isbn, excerpt),
	   FOREIGN KEY (isbn) REFERENCES meta_data
);

CREATE TABLE meta_data (
       isbn isbn_t NOT NULL,
       title varchar(256),
       PRIMARY KEY (isbn)
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
url = 'https://openlibrary.org/api/books?bibkeys=ISBN:' + (
    _isbn + '&jscmd=data')
meta_data_json = plpy.execute("SELECT gen.py_pgrest(%s);" % (plpy.quote_literal(url)))[0]['py_pgrest']
#
# remove garbage from api and convert to json object
json_object = json.loads(meta_data_json[18:-1])['ISBN:' + _isbn]
#
# Update Title
#try:
plpy.execute("UPDATE book.meta_data SET title = %s WHERE isbn = %s" %
(plpy.quote_literal(json_object["title"]), plpy.quote_literal(_isbn)))
#
# Update Authors
for author in json_object['authors']:
    try:
        plpy.execute("INSERT INTO book.author VALUES (%s, %s)" %
        (plpy.quote_literal(_isbn), plpy.quote_literal(author['name'])))
    except:
        """do nothing"""
#
# Update publishers
for publisher in json_object['publishers']:
    try:
        plpy.execute("INSERT INTO book.publisher VALUES (%s, %s)" %
        (plpy.quote_literal(_isbn), plpy.quote_literal(publisher['name'])))
    except:
        """do nothing"""
    #
    # Update Subjects
    for subject in json_object['subjects']:
        try:
            plpy.execute("INSERT INTO book.subject VALUES (%s, %s)" %
            (plpy.quote_literal(_isbn), plpy.quote_literal(subject['name'])))
        except:
            """do nothing"""
    # Update excerpts
if 'excerpts' in json_object.keys():
    for excerpt in json_object['excerpts']:
        try:
            plpy.execute("INSERT INTO book.excerpts VALUES (%s, %s)" %
            (plpy.quote_literal(_isbn), plpy.quote_literal(excerpt['text'])))
        except:
            """do nothing"""
return 'asd'
#except:
#    return ''
$$
;

CREATE OR REPLACE FUNCTION add_book(_isbn text)
  RETURNS text
  LANGUAGE plpgsql
AS $$
   BEGIN
   INSERT INTO book.meta_data VALUES (_isbn, null);
   RETURN get_meta_data(_isbn);
--	 RETURN true;
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
array_agg(author_name) as name
FROM author
GROUP BY isbn;

CREATE OR REPLACE VIEW publisher_agg AS SELECT
isbn,
array_agg(publisher_name) as name
FROM publisher
GROUP BY isbn;

CREATE OR REPLACE VIEW excerpt_agg AS SELECT
isbn,
array_agg(excerpt) as excerpt
FROM excerpt
GROUP BY isbn;

CREATE OR REPLACE VIEW publisher_agg AS SELECT
isbn,
array_agg(publisher_name) as name
FROM publisher
GROUP BY isbn;

CREATE OR REPLACE VIEW book_overview AS SELECT
m.isbn,
m.title,
array_agg(a.author_name) as authors,
array_agg(p.publisher_name) as publishers,
array_agg(e.excerpt) as descriptions,
array_agg(subject_name) as subjects
FROM meta_data m
JOIN author a ON (m.isbn = a.isbn)
JOIN publisher p ON (m.isbn = p.isbn)
LEFT JOIN excerpts e ON (m.isbn = e.isbn)
RIGHT JOIN subject s ON (m.isbn = s.isbn)
GROUP BY m.isbn, a.author_name, p.publisher_name, e.excerpt;

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
