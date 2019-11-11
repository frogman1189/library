#!/bin/bash

while true
do
	read barcode
	psql -c "SELECT book.add_book('$barcode');" -h 127.0.0.1 -U postgres library_test
	echo $barcode
done
