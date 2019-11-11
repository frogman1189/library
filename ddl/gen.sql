-- -*- mode: sql; sql-product: postgres; -*-

CREATE SCHEMA gen;

SET SEARCH_PATH = gen;

CREATE EXTENSION plpython3u;

--https://openlibrary.org/ap/ibooks?bibkeys=ISBN:0451526538&jscmd=data

CREATE OR REPLACE FUNCTION py_pgrest(
  p_url text,
  p_method text DEFAULT 'GET'::text,
  p_data text DEFAULT ''::text,
  p_headers text DEFAULT '{"Content-Type": "application/json"}'::text
)
 RETURNS text
 LANGUAGE plpython3u
AS $$
	import requests, json
	try:
		r = requests.request(method=p_method, url=p_url, data=p_data, headers=json.loads(p_headers))
	except Exception as e:
		return e
	else:
		return r.content.decode('utf-8')
$$
;

CREATE TYPE book_meta_data_record_t AS (
  title varchar(128),
  author varchar(128)
);


/* DATA we want to obtain:
publishers X\
title X\
authors X\
excerpts X
cover
subject X
isbn_10, isbn_13
*/
/*plpy.execute("UPDATE tbl SET %s = %s WHERE key = %s" % (
	plpy.quote_ident(colname),
	plpy.quote_nullable(newvalue),
	plpy.quote_literal(keyvalue)))*/

CREATE OR REPLACE FUNCTION foo(_isbn text)
  RETURNS text
  LANGUAGE plpython3u
AS $$
import json
url = 'https://openlibrary.org/api/books?bibkeys=ISBN:' + (
    _isbn + '&jscmd=data')
meta_data_json = plpy.execute("SELECT py_pgrest(%s);" % (plpy.quote_literal(url)))[0]['py_pgrest']
#
# remove garbage from api and convert to json object
json_object = json.loads(meta_data_json[18:-1])['ISBN:' + _isbn]
#
# Update Title
try:
    plpy.execute("UPDATE book.meta_data SET title = %s WHERE isbn = %s" %
		 (plpy.quote_literal(json_object["title"]), plpy.quote_literal(_isbn)))
except:
    """do nothing"""
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
        # Update excerpts
	for excerpt in json_object['excerpts']:
	    try:
		plpy.execute("INSERT INTO book.excerpts VALUES (%s, %s)" %
			     (plpy.quote_literal(_isbn), plpy.quote_literal(excerpt['text'])))
	    except:
		"""do nothing"""
	return json_object['excerpts']
$$
;

CREATE OR REPLACE FUNCTION add_book(_isbn text)
  RETURNS text
  LANGUAGE plpgsql
AS $$
   BEGIN
   INSERT INTO book.meta_data VALUES (_isbn, null);
   RETURN foo(_isbn);
--	 RETURN true;
   END;
$$;
