#!/usr/bin/env bash

rm -rf build/function
mkdir -p build/function
cp -R src/* build/function/

cd build/function
zip -r ../function.zip .
cd ../..