#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_PATH="$ROOT_DIR/SwiftOpenCC/SwiftyOpenCC.xcodeproj"
SCHEME="OpenCCBridge"
SCHEME_PATH="$PROJECT_PATH/xcshareddata/xcschemes/$SCHEME.xcscheme"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVES_DIR="$BUILD_DIR/archives"
DERIVED_DATA_DIR="$BUILD_DIR/DerivedData"
OUTPUT_PATH="$ROOT_DIR/OpenCCBridge.xcframework"
GENERATED_SCHEME=0

rm -rf "$OUTPUT_PATH" "$BUILD_DIR"
mkdir -p "$ARCHIVES_DIR" "$DERIVED_DATA_DIR"

cleanup() {
  if [[ "$GENERATED_SCHEME" == "1" ]]; then
    rm -f "$SCHEME_PATH"
  fi
}

trap cleanup EXIT

ensure_archive_scheme() {
  if [[ -f "$SCHEME_PATH" ]]; then
    return
  fi

  mkdir -p "$(dirname "$SCHEME_PATH")"
  GENERATED_SCHEME=1
  cat <<'EOF' > "$SCHEME_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "9999"
   version = "1.3">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "SwiftyOpenCC::OpenCCBridge"
               BuildableName = "OpenCCBridge.framework"
               BlueprintName = "OpenCCBridge"
               ReferencedContainer = "container:SwiftyOpenCC.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <MacroExpansion>
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "SwiftyOpenCC::OpenCCBridge"
            BuildableName = "OpenCCBridge.framework"
            BlueprintName = "OpenCCBridge"
            ReferencedContainer = "container:SwiftyOpenCC.xcodeproj">
         </BuildableReference>
      </MacroExpansion>
      <AdditionalOptions>
      </AdditionalOptions>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
EOF
}

ensure_archive_scheme

archive_framework() {
  local archive_name="$1"
  local sdk="$2"
  local destination="$3"
  shift 3

  echo "Build $archive_name"

  xcodebuild archive \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -sdk "$sdk" \
    -destination "$destination" \
    -archivePath "$ARCHIVES_DIR/$archive_name.xcarchive" \
    -derivedDataPath "$DERIVED_DATA_DIR/$archive_name" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
    ONLY_ACTIVE_ARCH=NO \
    "$@"
}

framework_path() {
  local archive_name="$1"
  echo "$ARCHIVES_DIR/$archive_name.xcarchive/Products/Library/Frameworks/OpenCCBridge.framework"
}

dsym_path() {
  local archive_name="$1"
  echo "$ARCHIVES_DIR/$archive_name.xcarchive/dSYMs/OpenCCBridge.framework.dSYM"
}

ensure_bundle_version() {
  local plist_path="$1"

  if /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist_path" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion 1.0.0" "$plist_path"
  else
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string '1.0.0'" "$plist_path"
  fi
}

archive_framework ios iphoneos "generic/platform=iOS" \
  IPHONEOS_DEPLOYMENT_TARGET=12.0 \
  OTHER_CFLAGS=-fembed-bitcode \
  BITCODE_GENERATION_MODE=bitcode

archive_framework ios-simulator iphonesimulator "generic/platform=iOS Simulator" \
  IPHONEOS_DEPLOYMENT_TARGET=12.0 \
  OTHER_CFLAGS=-fembed-bitcode \
  BITCODE_GENERATION_MODE=bitcode

archive_names=(ios ios-simulator)

archive_framework macos macosx "generic/platform=macOS" \
  MACOSX_DEPLOYMENT_TARGET=12.0
archive_names+=(macos)

for archive_name in "${archive_names[@]}"; do
  ensure_bundle_version "$(framework_path "$archive_name")/Info.plist"
done

xcframework_args=()
for archive_name in "${archive_names[@]}"; do
  xcframework_args+=(-framework "$(framework_path "$archive_name")")
  if [[ -d "$(dsym_path "$archive_name")" ]]; then
    xcframework_args+=(-debug-symbols "$(dsym_path "$archive_name")")
  fi
done

xcodebuild -create-xcframework \
  "${xcframework_args[@]}" \
  -output "$OUTPUT_PATH"
