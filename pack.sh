#!/bin/bash

echo -n Packaging all Eclipse metadata in pack.tar .
rm -f pack.tar
rm -f pack.tar.gz
rm .metadata/.lock

tar cf pack.tar .metadata/ 

echo -n .
find . -name ".project" | xargs tar rf pack.tar

echo -n .
find . -name ".cproject" | xargs tar rf pack.tar

echo -n .
find . -name ".settings" | xargs tar rf pack.tar

echo
echo Zipping pack.tar ...
gzip pack.tar
ls -lh pack.tar.gz



