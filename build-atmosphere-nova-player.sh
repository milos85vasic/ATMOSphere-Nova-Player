#!/usr/bin/env bash
# build-atmosphere-nova-player.sh — build the ATMOSphere-Nova-Player APK
# from source and copy it into the parent ATMOSphere prebuilt-apps tree.
#
# Usage:
#     bash device/rockchip/atmosphere/nova-player/build-atmosphere-nova-player.sh
#
# Output:
#     device/rockchip/rk3588/prebuilt_apps/nova-video-player.apk
#     (replaces the upstream Archos PRESIGNED prebuilt that previously
#     shipped with package=org.courville.nova; the rebuilt APK has
#     package=atmosphere.nova.player + label="ATMOSphere Nova Player".)
#
# Native libraries: the native rebuild (:MediaLib:ndkBuild) IS run so the
# FIND-12 stream_video.c NULL-guard is compiled into libavos.so (§11.4.108
# SOURCE→ARTIFACT — the prior committed .so predated that fix). The upstream
# Nova ".player" Android.mk templates are activated (copied to Android.mk)
# just before gradle so ndk-build can discover the four native projects
# (libyuv, libnativehelper, avos, torrentd). FFmpeg/dav1d/opus/openssl/
# libmysofa self-skip on their committed prebuilts; only dav1d (no prebuilt)
# + avos/libyuv/libnativehelper/torrentd actually compile.
# See docs/research/1_2_0_dev_d3_findings/FIX_nova_ndkbuild_blocker.md.
#
# Signing: AOSP re-signs at image-assembly time via LOCAL_CERTIFICATE :=
# platform in prebuilt_apps/Android.mk. We debug-sign the gradle output
# first because AOSP's re-sign mechanism requires the input APK to carry
# at least a v1 jar manifest (same trap as MPV — see Fix #124 commit
# 99ffdad in mpv-player submodule).
#
# JDK: gradle 8.13 + AGP 8.13.2 + JavaVersion.VERSION_17 source compat.
# Java 21 with javac is sufficient (javac --release 17). The Java 17
# install on alt-linux is JRE-only (no javac), so we explicitly pick 21.
#
# Skippable via SKIP_NOVA=1.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

cd "$SCRIPT_DIR"

echo "[ATMOSphere-Nova] build-atmosphere-nova-player.sh"
echo "  script dir: $SCRIPT_DIR"
echo "  parent:     $PARENT_ROOT"

# Sanity check: native libs must be present in MediaLib/libs/<abi>/
_JNI_ARM64=MediaLib/libs/arm64-v8a
if [ ! -f "$_JNI_ARM64/libavcodec.so" ]; then
    echo "[ATMOSphere-Nova] ERROR: $_JNI_ARM64/libavcodec.so missing."
    echo "  Run 'make' inside this submodule first to populate MediaLib/libs/"
    echo "  from the FFmpeg + libavos sources. That is a one-time, expensive"
    echo "  operation; once the .so files exist they are committed."
    exit 2
fi

# Pick a JDK with javac (gradle 8.13 + AGP 8.13.2 require Java 17+ source
# compat; the JVM toolchain used to compile must have javac, not just JRE).
_pick_jdk() {
    if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/javac" ]; then
        return 0
    fi
    for cand in \
        "$PARENT_ROOT/prebuilts/jdk/jdk21/linux-x86" \
        "$PARENT_ROOT/prebuilts/jdk/jdk21" \
        /usr/lib/jvm/java-21-openjdk \
        /usr/lib/jvm/java-21-openjdk-*.x86_64 \
        /usr/lib/jvm/jdk-21*; do
        for actual in $cand; do
            if [ -x "$actual/bin/javac" ]; then
                export JAVA_HOME="$actual"
                return 0
            fi
        done
    done
    echo "[ATMOSphere-Nova] WARNING: no JDK with javac found — gradle 8.13 may fail"
    return 1
}
_pick_jdk || true
if [ -n "${JAVA_HOME:-}" ]; then
    echo "[ATMOSphere-Nova] JAVA_HOME=$JAVA_HOME"
    "$JAVA_HOME/bin/java" -version 2>&1 | head -1
fi

# Pick the Android SDK.
_SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"
echo "[ATMOSphere-Nova] ANDROID_SDK_ROOT=$_SDK"

# --- Activate the upstream-Nova ".player" Android.mk templates ----------------
# ndk-build (invoked as `ndk-build -C native/<dir>` by core.mk:204 via the
# :MediaLib:ndkBuild make targets) auto-discovers a project by finding
# jni/Android.mk (or Android.mk in cwd). This checkout ships ONLY the upstream
# Nova ".player" template form (Android.mk.player) with NO active Android.mk,
# so ndk-build fails with "Please define the NDK_PROJECT_PATH variable"
# (build-local.mk:151) — the 1.2.0-dev-0.0.2 blocker. Copy each .player
# template to its active Android.mk name so the four native ndk-build dirs
# (libyuv, libnativehelper, avos, torrentd) become discoverable. Idempotent;
# templates remain the source of truth (we copy, never edit them).
# (cwd here is $SCRIPT_DIR — `cd "$SCRIPT_DIR"` ran above.)
echo "[ATMOSphere-Nova] activating .player Android.mk templates for ndk-build"
_activate_player() {  # $1 = path to an *.player file
    [ -f "$1" ] || return 0
    _dst="${1%.player}"
    cp -f "$1" "$_dst"
}
for _p in \
    native/libyuv/Android.mk.player          native/libyuv/jni/Android.mk.player \
    native/libnativehelper/Android.mk.player native/libnativehelper/jni/Android.mk.player \
    native/avos/jni/Android.mk.player \
    native/torrentd/Android.mk.player        native/torrentd/jni/Android.mk.player; do
    _activate_player "$_p"
done
# -----------------------------------------------------------------------------

# Run gradle from inside Video/ — that's where the gradlew wrapper lives.
# -Puniversal: produce a single multi-ABI APK (not per-ABI splits).
# :MediaLib:ndkBuild is NOT skipped — the native rebuild produces a fresh
# libavos.so carrying the FIND-12 NULL-guard (§11.4.108 SOURCE→ARTIFACT).
echo "[ATMOSphere-Nova] running: cd Video && ./gradlew :assembleNoamazonRelease -Puniversal"
cd Video
chmod +x ./gradlew 2>/dev/null || true
ANDROID_SDK_ROOT="$_SDK" \
    ./gradlew --no-daemon --console=plain :assembleNoamazonRelease -Puniversal

# Locate the resulting universal APK.
APK_PATH=""
for cand in \
    build/outputs/apk/noamazon/release/atmosphere.nova.player-*-universal-release-unsigned.apk \
    build/outputs/apk/noamazon/release/atmosphere.nova.player-*-universal-release.apk; do
    for actual in $cand; do
        if [ -f "$actual" ]; then APK_PATH="$actual"; break 2; fi
    done
done

if [ -z "${APK_PATH:-}" ]; then
    echo "[ATMOSphere-Nova] ERROR: gradle reported success but no universal APK found."
    ls -la build/outputs/apk/noamazon/release/ 2>&1 | head -20
    exit 3
fi
echo "[ATMOSphere-Nova] found APK: $APK_PATH"

cd "$SCRIPT_DIR"

OUT="$PARENT_ROOT/device/rockchip/rk3588/prebuilt_apps/nova-video-player.apk"

# Debug-sign before copying — AOSP's LOCAL_CERTIFICATE := platform re-sign
# mechanism rejects fully-unsigned APKs (no META-INF/MANIFEST.MF). Same
# trap as MPV; same fix.
DEBUG_KS="$HOME/.android/debug.keystore"
if [ ! -f "$DEBUG_KS" ]; then
    echo "[ATMOSphere-Nova] creating $DEBUG_KS (standard debug passwords)"
    mkdir -p "$HOME/.android"
    keytool -genkey -v \
        -keystore "$DEBUG_KS" \
        -storepass android -keypass android \
        -alias androiddebugkey \
        -dname "CN=Android Debug,O=Android,C=US" \
        -keyalg RSA -keysize 2048 -validity 10000 2>&1 | tail -2
fi

APKSIGNER=""
for cand in "$_SDK/build-tools/"*/apksigner \
            "$HOME/Android/Sdk/build-tools/"*/apksigner \
            /opt/android-sdk/build-tools/*/apksigner; do
    for actual in $cand; do
        if [ -x "$actual" ]; then APKSIGNER="$actual"; break 2; fi
    done
done
if [ -z "$APKSIGNER" ] || [ ! -x "$APKSIGNER" ]; then
    echo "[ATMOSphere-Nova] ERROR: apksigner not found"
    exit 6
fi

SIGNED=/tmp/atmosphere-nova-player-signed.apk
cp -f "Video/$APK_PATH" "$SIGNED"
echo "[ATMOSphere-Nova] debug-signing the APK"
"$APKSIGNER" sign --ks "$DEBUG_KS" \
    --ks-pass pass:android --key-pass pass:android \
    --ks-key-alias androiddebugkey \
    "$SIGNED" 2>&1 | tail -3

echo "[ATMOSphere-Nova] copying $SIGNED"
echo "             →  $OUT"
cp -f "$SIGNED" "$OUT"
rm -f "$SIGNED" "${SIGNED}.idsig" 2>/dev/null || true

# Pipe-free aapt verification (same SIGPIPE-safe pattern as MPV helper).
AAPT=""
for cand in "$_SDK/build-tools/"*/aapt \
            "$HOME/Android/Sdk/build-tools/"*/aapt \
            /opt/android-sdk/build-tools/*/aapt; do
    for actual in $cand; do
        if [ -x "$actual" ]; then AAPT="$actual"; break 2; fi
    done
done
if [ -n "$AAPT" ]; then
    RAW=$("$AAPT" dump badging "$OUT" 2>/dev/null) || true
    LABEL=${RAW#*$'\napplication-label:\''}
    [ "$LABEL" = "$RAW" ] && LABEL=${RAW#*application-label:\'}
    LABEL=${LABEL%%\'*}
    PKG=${RAW#*package: name=\'}
    PKG=${PKG%%\'*}
    case "$LABEL" in
        ATMOSphere*)
            echo "[ATMOSphere-Nova] verified package='$PKG' label='$LABEL' ✓" ;;
        *)
            echo "[ATMOSphere-Nova] ERROR: shipped APK label='$LABEL' (expected 'ATMOSphere Nova Player')"
            exit 5 ;;
    esac
else
    echo "[ATMOSphere-Nova] WARNING: aapt not found — skipping post-build label verification"
fi

echo "[ATMOSphere-Nova] done."
