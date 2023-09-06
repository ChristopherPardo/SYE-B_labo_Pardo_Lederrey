#!/bin/bash

echo Updating Eclipse metadata.

rm -rf .metadata
find . -name ".project" | xargs rm -rf
find . -name ".cproject" | xargs rm -rf
find . -name ".settings" | xargs rm -rf

echo Extracting metadata...
tar xf pack.tar.gz


