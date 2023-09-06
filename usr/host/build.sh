#!/bin/bash

rm -rf build > /dev/null
mkdir build
cd build
cmake ..
make

cp *.elf ../
cd ..