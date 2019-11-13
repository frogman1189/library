-- -*- mode: sql; sql-product: postgres; -*-

CREATE SCHEMA IF NOT EXISTS app;

SET search_path = app;

CREATE TABLE state (
	   id bool DEFAULT true,
	   action int,
	   person int,
	   book book.isbn_t,
	   PRIMARY KEY(id),
	   CONSTRAINT single_row CHECK(id)
);
INSERT INTO state (action, person, book) VALUES (null, null, null);

CREATE TABLE prefix (
	   id SERIAL,
	   name text,
	   prefix text,
	   func text,
	   PRIMARY KEY(id, prefix)
);

INSERT INTO prefix (name, prefix, func) VALUES
	   ('ACTION', 'A:', 'set_state_action'),
	   ('USER', 'U:', 'set_state_user'),
	   ('FOO', 'F:', 'foo')
;

CREATE TABLE action (
	   id SERIAL,
	   name text,
	   func text,
	   PRIMARY KEY(id)
);

INSERT INTO action VALUES
	   -- (1, 'ADD', 'add_book')
	   -- (2, 'ISSUE', 'issue_book')
	   -- (3, 'RETURN', 'return_book')
	    (4, 'RELOAD_METADATA', 'reload_metadata')
	   -- (5, 'REVOKE'),
	   -- (6, 'MODIFY'),
	   -- (7, 'MISSING')
;

--------------------------------------------------------------------------------
-- Functions
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION barcode_scan(_barcode text)
RETURNS text
LANGUAGE plpgsql SET search_path = app
AS $$
DECLARE
_func text;
_prefix text;
_return text;
BEGIN
SELECT func, prefix INTO _func, _prefix FROM prefix WHERE _barcode LIKE prefix.prefix || '%';
IF _func IS NULL THEN
  IF (SELECT action FROM state WHERE action IS NOT NULL AND person IS NOT NULL) IS NOT NULL THEN
	UPDATE state set book = _barcode;
	SELECT a.func INTO _func FROM action a, state s WHERE a.id = s.action;
	EXECUTE 'SELECT ' || _func || '()' INTO _return;
  ELSE
	RAISE 'missing action or person';
  END IF;
ELSE
  EXECUTE 'SELECT ' || _func || '($1)'
    USING substring(_barcode, char_length(_prefix) + 1, char_length(_barcode)) INTO _return;
END IF;
RETURN _return;
END;
$$;

CREATE OR REPLACE FUNCTION reload_metadata()
RETURNS text
LANGUAGE plpgsql SET search_path = book
AS $$
DECLARE
_isbn isbn_t;
BEGIN
SELECT book INTO _isbn FROM app.state;
--SELECT add_book(_isbn);
RETURN _isbn;
END;
$$;

CREATE OR REPLACE FUNCTION return_book()
RETURNS text
LANGUAGE plpgsql SET search_path = app, book
AS $$
DECLARE
_book isbn_t;
_person int;
_book_id int;
BEGIN
SELECT book, person INTO _book, _person FROM state;
SELECT book_id into _book_id FROM borrowers_table b
WHERE b.isbn = _book
AND b.person_id = _person
AND b.return_date IS NULL
LIMIT 1;
IF _book_id IS NOT NULL THEN
  UPDATE borrowers_table SET return_date = current_timestamp
  WHERE book_id = _book_id
  AND person_id = _person
  AND return_date IS NULL;
  UPDATE book SET state = 'available' WHERE book_id = _book_id;
ELSE
  RAISE 'book is not borrowed by this person';
END IF;
RETURN _book_id;
END;
$$;

CREATE OR REPLACE FUNCTION issue_book()
RETURNS text
LANGUAGE plpgsql SET search_path = app, book
AS $$
DECLARE
_book isbn_t;
_person int;
_book_id int;
BEGIN
SELECT book, person INTO _book, _person FROM state;
SELECT book_id INTO _book_id FROM book WHERE state = 'available' AND isbn = _book LIMIT 1;
IF _book_id IS NOT NULL THEN
  INSERT INTO borrowers_table (book_id, person_id) VALUES
    (_book_id, _person);
  UPDATE book SET state = 'borrowed' WHERE book_id = _book_id;
  RETURN 'Issued book ' || _book_id || ' (isbn:' || _book || ')';
ELSE
  RAISE 'no book with given isbn available';
  RETURN 'Failed to issue book';
END IF;
END;
$$;



CREATE OR REPLACE FUNCTION add_book()
RETURNS text
LANGUAGE plpgsql SET search_path = app, book
AS $$
DECLARE
_book isbn_t;
_person int;
_copies int;
BEGIN
	SELECT book, person INTO _book, _person FROM state;
	PERFORM book.add_book(_book);
    INSERT INTO book.book (isbn, state) VALUES (_book, 'available');
	IF _person IS NOT NULL THEN
	  IF (SELECT copies FROM ownership_table
	    WHERE person_id = _person AND isbn = _book) IS NOT NULL THEN
		SELECT copies INTO _copies FROM ownership_table WHERE person_id = _person AND isbn = _book;
		UPDATE ownership_table SET copies = _copies + 1 WHERE person_id = _person AND isbn = _book;
	  ELSE
	    INSERT INTO ownership_table (person_id, isbn, copies) VALUES
		  (_person, _book, 1);
		END IF;
	END IF;
	RETURN '';
END;
$$;

CREATE OR REPLACE FUNCTION set_state_action(_action_id text)
RETURNS text
LANGUAGE plpgsql SET search_path = app, book
AS $$
DECLARE
_a_id integer;
BEGIN
SELECT id into _a_id
FROM action
WHERE _action_id::integer = id;
IF _a_id IS NOT NULL THEN
  UPDATE state SET action = _action_id::integer;
ELSE
  RAISE 'action does not exist';
END IF;
RETURN _a_id;
END;
$$;

CREATE OR REPLACE FUNCTION set_state_user(_id text)
RETURNS text
LANGUAGE plpgsql SET search_path = app, book
AS $$
DECLARE
_p_id integer;
_name text;
BEGIN
SELECT person_id,
f_name || ' ' || l_name
INTO _p_id, _name
FROM book.person
WHERE _id::integer = person_id;
--IF _p_id IS NOT NULL THEN
  UPDATE state SET person = _p_id;
--ELSE
--  RAISE 'Person id does not exist';
--END IF;
RETURN _name;
END;
$$;

CREATE OR REPLACE FUNCTION foo()
RETURNS text
LANGUAGE plpgsql
AS $$
BEGIN
RETURN 'foo';
END;
$$;
