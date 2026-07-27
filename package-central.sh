#!/usr/bin/env bash

set -euo pipefail

readonly CENTRAL_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CENTRAL_PROPERTIES_FILE="$CENTRAL_PROJECT_ROOT/gradle.properties"

central_read_property() {
  local property_name="$1"
  sed -n "s/^${property_name}=//p" "$CENTRAL_PROPERTIES_FILE" | tail -n 1
}

central_require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "Missing required command: $command_name" >&2
    exit 1
  }
}

central_require_artifact() {
  local artifact_path="$1"
  test -s "$artifact_path" || {
    echo "Missing required publication artifact: $artifact_path" >&2
    exit 1
  }
}

central_require_command gpg
central_require_command md5
central_require_command shasum
central_require_command unzip
central_require_command zip

: "${SIGNING_KEY_ID:?Missing SIGNING_KEY_ID}"
: "${SIGNING_PASSWORD:?Missing SIGNING_PASSWORD}"
: "${SIGNING_SECRET_KEY_RING_FILE:?Missing SIGNING_SECRET_KEY_RING_FILE}"

readonly CENTRAL_VERSION="$(central_read_property VERSION_NAME)"
readonly CENTRAL_GROUP_ID="$(central_read_property GROUP_ID)"
readonly CENTRAL_CORE_ARTIFACT="$(central_read_property ARTIFACT_ID)"
readonly CENTRAL_MEDIA3_ARTIFACT="$(central_read_property ARTIFACT_ID_MEDIA3)"
readonly CENTRAL_GROUP_PATH="$(printf '%s' "$CENTRAL_GROUP_ID" | tr '.' '/')"

: "${CENTRAL_VERSION:?gradle.properties is missing VERSION_NAME}"
: "${CENTRAL_GROUP_ID:?gradle.properties is missing GROUP_ID}"
: "${CENTRAL_CORE_ARTIFACT:?gradle.properties is missing ARTIFACT_ID}"
: "${CENTRAL_MEDIA3_ARTIFACT:?gradle.properties is missing ARTIFACT_ID_MEDIA3}"

case "$CENTRAL_VERSION" in
  *-SNAPSHOT)
    echo "Maven Central release versions cannot end with -SNAPSHOT: $CENTRAL_VERSION" >&2
    exit 1
    ;;
esac

readonly CENTRAL_OUTPUT_ROOT="$CENTRAL_PROJECT_ROOT/build/central-publishing"
readonly CENTRAL_MAVEN_REPOSITORY="$CENTRAL_OUTPUT_ROOT/$CENTRAL_VERSION/repository"
readonly CENTRAL_CORE_DIRECTORY="$CENTRAL_MAVEN_REPOSITORY/$CENTRAL_GROUP_PATH/$CENTRAL_CORE_ARTIFACT/$CENTRAL_VERSION"
readonly CENTRAL_MEDIA3_DIRECTORY="$CENTRAL_MAVEN_REPOSITORY/$CENTRAL_GROUP_PATH/$CENTRAL_MEDIA3_ARTIFACT/$CENTRAL_VERSION"
readonly CENTRAL_BUNDLE="$CENTRAL_OUTPUT_ROOT/BigImageViewPager-$CENTRAL_VERSION-central-bundle.zip"

echo "Building Maven Central bundle for $CENTRAL_GROUP_ID:$CENTRAL_CORE_ARTIFACT:$CENTRAL_VERSION"

cd "$CENTRAL_PROJECT_ROOT"
./gradlew clean
mkdir -p "$CENTRAL_MAVEN_REPOSITORY"

./gradlew \
  -Dmaven.repo.local="$CENTRAL_MAVEN_REPOSITORY" \
  :library:publishReleasePublicationToMavenLocal \
  :library-video-media3:publishReleasePublicationToMavenLocal

for publication_directory in "$CENTRAL_CORE_DIRECTORY" "$CENTRAL_MEDIA3_DIRECTORY"; do
  test -d "$publication_directory" || {
    echo "Publication directory was not generated: $publication_directory" >&2
    exit 1
  }
done

for artifact_name in "$CENTRAL_CORE_ARTIFACT" "$CENTRAL_MEDIA3_ARTIFACT"; do
  if [[ "$artifact_name" == "$CENTRAL_CORE_ARTIFACT" ]]; then
    publication_directory="$CENTRAL_CORE_DIRECTORY"
  else
    publication_directory="$CENTRAL_MEDIA3_DIRECTORY"
  fi

  central_require_artifact "$publication_directory/$artifact_name-$CENTRAL_VERSION.aar"
  central_require_artifact "$publication_directory/$artifact_name-$CENTRAL_VERSION.pom"
  central_require_artifact "$publication_directory/$artifact_name-$CENTRAL_VERSION-sources.jar"
  central_require_artifact "$publication_directory/$artifact_name-$CENTRAL_VERSION-javadoc.jar"
done

# Gradle intentionally omits checksums for Maven Local publications. Central
# requires MD5 and SHA-1 for every deployed artifact, but not for .asc files.
while IFS= read -r -d '' component_file; do
  md5 -q "$component_file" >"$component_file.md5"
  shasum -a 1 "$component_file" | awk '{print $1}' >"$component_file.sha1"
done < <(
  find "$CENTRAL_CORE_DIRECTORY" "$CENTRAL_MEDIA3_DIRECTORY" -type f \
    ! -name '*.asc' \
    ! -name '*.md5' \
    ! -name '*.sha1' \
    -print0
)

primary_file_count=0
while IFS= read -r -d '' component_file; do
  central_require_artifact "$component_file.asc"
  central_require_artifact "$component_file.md5"
  central_require_artifact "$component_file.sha1"

  gpg --verify "$component_file.asc" "$component_file" >/dev/null 2>&1 || {
    echo "Invalid or unverifiable signature: $component_file.asc" >&2
    exit 1
  }

  test "$(md5 -q "$component_file")" = "$(tr -d '[:space:]' <"$component_file.md5")" || {
    echo "MD5 verification failed: $component_file" >&2
    exit 1
  }
  test "$(shasum -a 1 "$component_file" | awk '{print $1}')" = "$(tr -d '[:space:]' <"$component_file.sha1")" || {
    echo "SHA-1 verification failed: $component_file" >&2
    exit 1
  }

  primary_file_count=$((primary_file_count + 1))
done < <(
  find "$CENTRAL_CORE_DIRECTORY" "$CENTRAL_MEDIA3_DIRECTORY" -type f \
    ! -name '*.asc' \
    ! -name '*.md5' \
    ! -name '*.sha1' \
    -print0
)

(
  cd "$CENTRAL_MAVEN_REPOSITORY"
  zip -q -r "$CENTRAL_BUNDLE" \
    "$CENTRAL_GROUP_PATH/$CENTRAL_CORE_ARTIFACT/$CENTRAL_VERSION" \
    "$CENTRAL_GROUP_PATH/$CENTRAL_MEDIA3_ARTIFACT/$CENTRAL_VERSION"
)

unzip -tq "$CENTRAL_BUNDLE" >/dev/null
if unzip -Z1 "$CENTRAL_BUNDLE" | grep -q 'maven-metadata-local\.xml'; then
  echo "Bundle must not contain maven-metadata-local.xml" >&2
  exit 1
fi

echo
echo "Maven Central bundle created successfully."
echo "Version: $CENTRAL_VERSION"
echo "Primary artifacts verified: $primary_file_count"
echo "Bundle: $CENTRAL_BUNDLE"
echo
echo "Upload manually in Central Portal, or run:"
echo "  ./upload-central.sh '$CENTRAL_BUNDLE'"
