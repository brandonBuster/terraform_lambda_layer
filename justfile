# justfile
# Usage:
#   just --list
#   just setup
#   just test
#   just deploy
#   just logs

set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# -----------------------------
# Configs
# -----------------------------
project_name := "terraform-lambda"
aws_region := "us-west-2"
aws_profile := ""
aws_profile_flag := ""
runtime := "python3.12"
lambda_handler := "app.handler"

# Paths
src_dir := "src"
layer_dir := "layer"
tf_dir := "terraform"
build_dir := "build"
fn_build_dir := build_dir + "/function"
layer_build_dir := build_dir + "/layer"
fn_zip := build_dir + "/function.zip"
layer_zip := build_dir + "/layer.zip"

# Docker image to build linux-compatible wheels for Lambda
lambda_build_image := "public.ecr.aws/lambda/python:3.12"

# Show effective config
config:
  @echo "project_name:     {{project_name}}"
  @echo "aws_region:       {{aws_region}}"
  @echo "runtime:          {{runtime}}"
  @echo "lambda_handler:   {{lambda_handler}}"
  @echo "aws_profile:      {{aws_profile}}"
  @echo "lambda_build_image: {{lambda_build_image}}"

# -----------------------------
# Setup / Tooling
# -----------------------------
setup:
  @echo "Creating venv + installing dev deps..."
  python3 -m venv .venv
  . .venv/bin/activate && \
    pip install -U pip wheel setuptools && \
    if [ -f "{{src_dir}}/requirements-dev.txt" ]; then pip install -r "{{src_dir}}/requirements-dev.txt"; fi
  @echo "Done. Activate with: source .venv/bin/activate"

clean:
  rm -rf "{{build_dir}}" .pytest_cache .ruff_cache .mypy_cache
  find . -type d -name "__pycache__" -prune -exec rm -rf {} +
  @echo "Cleaned build artifacts and caches."

# -----------------------------
# Local run / quick checks
# -----------------------------
run-local:
  @echo "Running handler locally (smoke test)..."
  @if [ -f .venv/bin/python3 ]; then \
    .venv/bin/python3 -c "import json; import sys; sys.path.insert(0, '{{src_dir}}'); from app import handler; result = handler({}, None); print(json.dumps(result, indent=2))"; \
  else \
    echo "Note: Virtual environment not found. Install dependencies first with: just setup"; \
    PYTHONPATH={{src_dir}} python3 -c "import json; import sys; from app import handler; result = handler({}, None); print(json.dumps(result, indent=2))"; \
  fi

# Run handler with custom event JSON file
# Usage: just run-local-event test-event.json
run-local-event event_file:
  @echo "Running handler with event from {{event_file}}..."
  @if [ -f .venv/bin/python3 ]; then \
    .venv/bin/python3 -c "import json; import sys; sys.path.insert(0, '{{src_dir}}'); from app import handler; event = json.load(open('{{event_file}}')); result = handler(event, None); print(json.dumps(result, indent=2))"; \
  else \
    PYTHONPATH={{src_dir}} python3 -c "import json; import sys; from app import handler; event = json.load(open('{{event_file}}')); result = handler(event, None); print(json.dumps(result, indent=2))"; \
  fi

# Install function dependencies locally (for testing)
install-local:
  @echo "Installing dependencies for local testing..."
  @if [ ! -f .venv/bin/pip ]; then \
    echo "Creating virtual environment..."; \
    python3 -m venv .venv; \
  fi
  . .venv/bin/activate && pip install -q -r {{layer_dir}}/requirements.txt
  @if [ -f {{src_dir}}/requirements.txt ] && [ -s {{src_dir}}/requirements.txt ]; then \
    . .venv/bin/activate && pip install -q -r {{src_dir}}/requirements.txt; \
  fi
  @echo "Dependencies installed. Use: source .venv/bin/activate"

# -----------------------------
# Build: Layer
# -----------------------------
build-layer:
  @echo "Building Lambda layer (Linux-compatible) using Docker..."
  rm -rf "{{layer_build_dir}}" "{{layer_zip}}"
  mkdir -p "{{layer_build_dir}}/python"
  docker run --rm \
    -v "$(pwd)":/var/task \
    -w /var/task \
    "{{lambda_build_image}}" \
    /bin/bash -lc "\
      pip install -r {{layer_dir}}/requirements.txt \
        -t {{layer_build_dir}}/python \
        --no-cache-dir \
      && find {{layer_build_dir}}/python -name '__pycache__' -type d -prune -exec rm -rf {} + \
    "
  (cd "{{layer_build_dir}}" && zip -qr "../layer.zip" .)
  @echo "Layer built: {{layer_zip}}"

# -----------------------------
# Build: Function
# -----------------------------
build-fn:
  @echo "Packaging Lambda function code..."
  rm -rf "{{fn_build_dir}}" "{{fn_zip}}"
  mkdir -p "{{fn_build_dir}}"
  cp -R "{{src_dir}}/"* "{{fn_build_dir}}/"
  (cd "{{fn_build_dir}}" && zip -qr "../function.zip" .)
  @echo "Function built: {{fn_zip}}"

  # Build everything
build: build-layer build-fn
  @echo "Build complete."

# -----------------------------
# Deploy: Terraform
# -----------------------------
deploy-tf:
  @echo "Deploying with Terraform..."
  cd "{{tf_dir}}"
  terraform init
  terraform apply -auto-approve
  @echo "Deployment complete."

# -----------------------------
# Tests / Lint / Format (optional)
# -----------------------------
# If you add pytest, ruff, black, mypy, etc. these will run.
# Otherwise they’ll print a helpful message and succeed.

test:
  @if [ -f .venv/bin/pytest ]; then \
    echo "Running pytest..."; \
    ./run_pytest.sh .venv/bin/pytest; \
  elif command -v pytest >/dev/null 2>&1; then \
    echo "Running pytest..."; \
    ./run_pytest.sh pytest; \
  else \
    echo "pytest not installed. Add it to requirements-dev.txt and run: just setup"; \
  fi

lint:
  @if command -v ruff >/dev/null 2>&1; then \
    echo "Running ruff..."; ruff check .; \
  else \
    echo "ruff not installed. Add it to requirements-dev.txt and run: just setup"; \
  fi

format:
  @if command -v ruff >/dev/null 2>&1; then \
    echo "Running ruff format..."; ruff format .; \
  else \
    echo "ruff not installed. Add it to requirements-dev.txt and run: just setup"; \
  fi

typecheck:
  @if command -v mypy >/dev/null 2>&1; then \
    echo "Running mypy..."; mypy .; \
  else \
    echo "mypy not installed. Add it to requirements-dev.txt and run: just setup"; \
  fi

# One command CI-ish gate
check: format lint typecheck test
  @echo "Checks complete."

# -----------------------------
# Terraform
# -----------------------------
tf-init:
  cd "{{tf_dir}}" && terraform init

tf-plan: build tf-init
  cd "{{tf_dir}}" && terraform plan

tf-apply: build tf-init
  cd "{{tf_dir}}" && terraform apply

tf-destroy: tf-init
  cd "{{tf_dir}}" && terraform destroy

deploy: tf-apply
  @echo "Deployed."

destroy: tf-destroy
  @echo "Destroyed."

# -----------------------------
# AWS helpers (logs / invoke)
# -----------------------------
# These assume your Lambda name is: "${project_name}-fn"
lambda-name:
  @echo "{{project_name}}-fn"

# Tail CloudWatch logs (requires AWS CLI v2)
logs:
  @fn="{{project_name}}-fn"; \
  echo "Tailing logs for $$fn in {{aws_region}}..."; \
  aws {{aws_profile_flag}} logs tail "/aws/lambda/$$fn" --region "{{aws_region}}" --follow

# Invoke with an optional JSON payload file:
#   just invoke payload.json
invoke payload_file="":
  @fn="{{project_name}}-fn"; \
  if [ "{{payload_file}}" = "" ]; then \
    echo "Invoking $$fn with empty payload..."; \
    aws {{aws_profile_flag}} lambda invoke --region "{{aws_region}}" --function-name "$$fn" --payload '{}' /tmp/lambda_out.json >/dev/null; \
  else \
    echo "Invoking $$fn with payload file: {{payload_file}}"; \
    aws {{aws_profile_flag}} lambda invoke --region "{{aws_region}}" --function-name "$$fn" --payload "fileb://{{payload_file}}" /tmp/lambda_out.json >/dev/null; \
  fi; \
  echo "Response:"; cat /tmp/lambda_out.json; echo

# Show Terraform outputs (helpful for ARNs, etc.)
outputs: tf-init
  cd "{{tf_dir}}" && terraform output
