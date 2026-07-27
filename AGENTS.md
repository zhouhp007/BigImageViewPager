# Repository Guidelines

## Project Structure & Module Organization

This is a Gradle Kotlin DSL Android project with three modules:

- `library/`: the core image-preview library, including Kotlin/Java APIs, Android resources, and bundled WebP JNI sources under `src/main/jni/`.
- `library-video-media3/`: the optional Media3/ExoPlayer integration. Keep Media3-specific implementation here so the core module can retain compile-only video dependencies.
- `sample/`: the demonstration app used for manual verification.

Shared dependency versions live in `gradle/libs.versions.toml`. Documentation is under `doc/`, while README assets are in `image/`. Production code follows the standard `src/main/java` and `src/main/res` layout.

## Build, Test, and Development Commands

Use the checked-in Gradle wrapper with JDK 17 and an Android SDK; native builds also require NDK `25.2.9519653`.

- `./gradlew assembleDebug` — build debug artifacts for all modules.
- `./gradlew :sample:installDebug` — install the sample app on a connected device or emulator.
- `./gradlew :library:assembleRelease :library-video-media3:assembleRelease` — build both release AARs.
- `./gradlew test` — run local unit tests when present.
- `./gradlew lint` — run Android lint across the project.
- `./gradlew clean` — remove generated build outputs.

Publishing scripts require Sonatype and GPG credentials; do not run them during routine development.

## Coding Style & Naming Conventions

Use four-space indentation, Java/Kotlin conventions, and the existing package prefix `cc.shinichi`. Name classes and interfaces in `PascalCase`, functions and properties in `camelCase`, and Android resources in `lower_snake_case`. Keep public APIs compatible where possible and document behavior-changing additions. Match surrounding source style; this repository does not configure ktlint, detekt, or Checkstyle. Avoid reformatting bundled third-party WebP and gesture-view sources unless the change requires it.

## Testing Guidelines

The repository currently has no committed automated tests. Add JVM tests to `<module>/src/test/` and device tests to `<module>/src/androidTest/`, naming classes with a `Test` suffix. For UI, gestures, media playback, or JNI changes, manually exercise the relevant flow in `sample` on supported ABIs. Before opening a PR, run the affected module build, `./gradlew test lint`, and `git diff --check`.

## Commit & Pull Request Guidelines

Follow the history's Conventional Commit style: `feat:`, `fix:`, `docs:`, and `release:` followed by a concise imperative summary. Keep commits focused. PRs should explain the problem and solution, list validation performed, link related issues, and include screenshots or recordings for visible UI changes. Call out API, dependency, ABI, or publishing impacts explicitly; never commit signing keys or repository credentials.
