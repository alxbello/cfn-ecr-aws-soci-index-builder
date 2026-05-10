#!/usr/bin/env bash
# build-lambdas.sh — Package Lambda functions for deployment.
# Works with Docker, Finch, or any OCI-compatible container runtime.
# After running this, `taskcat upload` will skip the Docker build step
# since the zip files already exist in functions/packages/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME="${CONTAINER_RUNTIME:-$(command -v finch || command -v docker)}"

if [ -z "$RUNTIME" ]; then
  echo "Error: No container runtime found. Install Docker or Finch." >&2
  exit 1
fi

echo "Using container runtime: $RUNTIME"

# Build the Go Lambda
LAMBDA_DIR="functions/source/soci-index-generator-lambda"
OUTPUT_DIR="functions/packages/soci-index-generator-lambda"

echo "Building soci-index-generator-lambda..."
mkdir -p "$SCRIPT_DIR/$OUTPUT_DIR"

"$RUNTIME" build --platform linux/amd64 -t soci-index-builder "$SCRIPT_DIR/$LAMBDA_DIR"
CONTAINER_ID=$("$RUNTIME" create soci-index-builder /bin/sh -c "mkdir -p /output && mv /build/soci_index_generator_lambda.zip /output/")
"$RUNTIME" start "$CONTAINER_ID"
"$RUNTIME" wait "$CONTAINER_ID" >/dev/null
"$RUNTIME" cp "$CONTAINER_ID:/output/soci_index_generator_lambda.zip" "$SCRIPT_DIR/$OUTPUT_DIR/soci_index_generator_lambda.zip"
"$RUNTIME" rm -f "$CONTAINER_ID" >/dev/null

# Package the Python Lambda (just zip it, no dependencies)
PYTHON_DIR="functions/source/ecr-image-action-event-filtering"
PYTHON_OUTPUT="functions/packages/ecr-image-action-event-filtering"

echo "Packaging ecr-image-action-event-filtering..."
mkdir -p "$SCRIPT_DIR/$PYTHON_OUTPUT"
(cd "$SCRIPT_DIR/$PYTHON_DIR" && zip -q "$SCRIPT_DIR/$PYTHON_OUTPUT/lambda.zip" ./*.py)

# Move Dockerfiles aside so taskcat upload skips Docker builds and uses our zips
echo "Hiding Dockerfiles so taskcat uses pre-built packages..."
find "$SCRIPT_DIR/functions/source" -name "Dockerfile" -exec mv {} {}.disabled \;

echo ""
echo "Done. Lambda packages:"
ls -la "$SCRIPT_DIR/$OUTPUT_DIR/soci_index_generator_lambda.zip"
ls -la "$SCRIPT_DIR/$PYTHON_OUTPUT/lambda.zip"
echo ""
echo "Run 'taskcat upload' to upload artifacts to S3."
echo "To restore Dockerfiles: find functions/source -name 'Dockerfile.disabled' -exec sh -c 'mv \"\$1\" \"\${1%.disabled}\"' _ {} \\;"
