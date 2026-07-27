#!/usr/bin/env bash

set -euo pipefail

readonly CENTRAL_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CENTRAL_PROPERTIES_FILE="$CENTRAL_PROJECT_ROOT/gradle.properties"
readonly CENTRAL_PUBLISHER_ENDPOINT="https://central.sonatype.com/api/v1/publisher/upload"

central_read_property() {
  local property_name="$1"
  sed -n "s/^${property_name}=//p" "$CENTRAL_PROPERTIES_FILE" | tail -n 1
}

central_usage() {
  cat <<'USAGE'
Usage: ./upload-central.sh [--yes] [bundle.zip]

Uploads a bundle as USER_MANAGED. This creates a Central Portal deployment and
starts validation, but never performs the final Maven Central publish action.

Credentials:
  CENTRAL_USERNAME / CENTRAL_PASSWORD (preferred)
  OSSRH_USERNAME / OSSRH_PASSWORD       (fallback)

Options:
  --yes    Skip the interactive upload confirmation.
  -h, --help
USAGE
}

central_confirm_upload() {
  local bundle_path="$1"
  local answer

  if [[ ! -t 0 ]]; then
    echo "Interactive confirmation is unavailable; rerun with --yes." >&2
    exit 1
  fi

  read -r -p "Upload $(basename "$bundle_path") as USER_MANAGED? [y/N] " answer
  case "$answer" in
    y | Y | yes | YES) ;;
    *)
      echo "Upload cancelled."
      exit 0
      ;;
  esac
}

assume_yes=false
bundle_argument=""

while (($# > 0)); do
  case "$1" in
    --yes)
      assume_yes=true
      ;;
    -h | --help)
      central_usage
      exit 0
      ;;
    -* )
      echo "Unknown option: $1" >&2
      central_usage >&2
      exit 1
      ;;
    *)
      if [[ -n "$bundle_argument" ]]; then
        echo "Only one bundle path may be provided." >&2
        exit 1
      fi
      bundle_argument="$1"
      ;;
  esac
  shift
done

command -v base64 >/dev/null 2>&1 || {
  echo "Missing required command: base64" >&2
  exit 1
}
command -v curl >/dev/null 2>&1 || {
  echo "Missing required command: curl" >&2
  exit 1
}

readonly CENTRAL_VERSION="$(central_read_property VERSION_NAME)"
: "${CENTRAL_VERSION:?gradle.properties is missing VERSION_NAME}"

if [[ -n "$bundle_argument" ]]; then
  readonly CENTRAL_BUNDLE="$(cd "$(dirname "$bundle_argument")" && pwd)/$(basename "$bundle_argument")"
else
  readonly CENTRAL_BUNDLE="$CENTRAL_PROJECT_ROOT/build/central-publishing/BigImageViewPager-$CENTRAL_VERSION-central-bundle.zip"
fi

test -s "$CENTRAL_BUNDLE" || {
  echo "Bundle does not exist or is empty: $CENTRAL_BUNDLE" >&2
  echo "Run ./package-central.sh first." >&2
  exit 1
}

readonly CENTRAL_UPLOAD_USERNAME="${CENTRAL_USERNAME:-${OSSRH_USERNAME:-}}"
readonly CENTRAL_UPLOAD_PASSWORD="${CENTRAL_PASSWORD:-${OSSRH_PASSWORD:-}}"
: "${CENTRAL_UPLOAD_USERNAME:?Missing CENTRAL_USERNAME (or OSSRH_USERNAME)}"
: "${CENTRAL_UPLOAD_PASSWORD:?Missing CENTRAL_PASSWORD (or OSSRH_PASSWORD)}"

readonly CENTRAL_DEPLOYMENT_LABEL="${CENTRAL_DEPLOYMENT_NAME:-BigImageViewPager-$CENTRAL_VERSION}"
if [[ ! "$CENTRAL_DEPLOYMENT_LABEL" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "CENTRAL_DEPLOYMENT_NAME may contain only letters, numbers, dot, underscore, and hyphen." >&2
  exit 1
fi

if [[ "$assume_yes" != true ]]; then
  central_confirm_upload "$CENTRAL_BUNDLE"
fi

# Keep the Bearer value out of shell history, command-line arguments, and logs.
central_curl_config="$(mktemp "${TMPDIR:-/tmp}/bigimage-central-curl.XXXXXX")"
chmod 600 "$central_curl_config"
central_cleanup() {
  rm -f "$central_curl_config"
}
trap central_cleanup EXIT
trap 'exit 130' HUP INT TERM

central_bearer="$(printf '%s:%s' "$CENTRAL_UPLOAD_USERNAME" "$CENTRAL_UPLOAD_PASSWORD" | base64 | tr -d '\r\n')"
printf 'header = "Authorization: Bearer %s"\n' "$central_bearer" >"$central_curl_config"
unset central_bearer

echo "Uploading $(basename "$CENTRAL_BUNDLE") as USER_MANAGED..."
deployment_id="$({
  curl \
    --silent \
    --show-error \
    --fail-with-body \
    --request POST \
    --config "$central_curl_config" \
    --form "bundle=@${CENTRAL_BUNDLE};type=application/octet-stream" \
    --url "$CENTRAL_PUBLISHER_ENDPOINT?publishingType=USER_MANAGED&name=$CENTRAL_DEPLOYMENT_LABEL"
} | tr -d '[:space:]')"

if [[ ! "$deployment_id" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
  echo "Upload returned an unexpected deployment ID: $deployment_id" >&2
  exit 1
fi

echo
echo "Upload accepted."
echo "Deployment ID: $deployment_id"
echo "Portal: https://central.sonatype.com/publishing/deployments"
echo "Wait for validation, inspect the results, then publish or drop it in Portal."
