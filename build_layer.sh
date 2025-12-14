#!/usr/bin/env bash

docker run --rm \
    --entrypoint /bin/bash \
    -v "$PWD":/var/task \
    -w /var/task \
    public.ecr.aws/lambda/python:3.12 \
    -c "\
    pip install -r layer/requirements.txt \
        -t build/layer/python \
        --no-cache-dir \
        && python -c \"import os, shutil; [shutil.rmtree(os.path.join(root, d)) for root, dirs, files in os.walk('build/layer/python') for d in dirs if d == '__pycache__']\" "

cd build/layer
zip -r ../layer.zip .
cd ../..