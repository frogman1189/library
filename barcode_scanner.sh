#!/bin/bash

while true
do
	read barcode
	psql -c "SELECT app.barcode_scan('$barcode');" -h 127.0.0.1 -U postgres library_test
done
