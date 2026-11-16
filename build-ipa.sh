#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
if [[ "$(uname -s)" != Darwin ]]; then
    printf '%s\n' 'Caleb must be built with Xcode on macOS.' >&2
    exit 1
fi
xcodebuild -version
if ! command -v xcodegen >/dev/null; then
    printf '%s\n' 'Install XcodeGen with brew install xcodegen.' >&2
    exit 1
fi

version=b12248
archive="llama-$version-xcframework.zip"
digest=fe38916b41f2a144115db39df860cb2f6f98a476589d5072b0cc3f51dbaf8c10
download=""
staging=""
cleanup() {
    [[ -z "$download" ]] || rm -rf -- "$download"
    [[ -z "$staging" ]] || rm -rf -- "$staging"
}
trap cleanup EXIT
if [[ ! -f "Vendor/.$version" || ! -d Vendor/llama.xcframework ]]; then
    download="$(mktemp -d)"
    curl -fLSs --retry 3 -o "$download/$archive" \
        "https://github.com/ggml-org/llama.cpp/releases/download/$version/$archive"
    (cd "$download" && printf '%s  %s\n' "$digest" "$archive" | shasum -a 256 -c -)
    ditto -x -k "$download/$archive" "$download/unpacked"
    framework="$(find "$download/unpacked" -type d -name llama.xcframework -print -quit)"
    if [[ -z "$framework" ]]; then
        printf '%s\n' 'The llama.cpp archive does not contain llama.xcframework.' >&2
        exit 1
    fi
    mkdir -p Vendor
    ditto "$framework" Vendor/llama.xcframework
    touch "Vendor/.$version"
fi

xcodegen generate
if [[ "${1:-}" == "--project-only" ]]; then
    exit 0
fi
xcodebuild -project Caleb.xcodeproj -scheme Caleb -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "$PWD/build" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

staging="$(mktemp -d)"
mkdir -p "$staging/Payload" dist
ditto build/Build/Products/Release-iphoneos/Caleb.app "$staging/Payload/Caleb.app"
ditto -c -k --keepParent "$staging/Payload" dist/Caleb-unsigned.ipa
printf '\n%s\n' "$PWD/dist/Caleb-unsigned.ipa"
