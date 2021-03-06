#!/bin/bash
set -euo pipefail

# This is the top-level test script:
#
# - Check code formatting.
# - Perform checks on Python code.
# - Make a debug build.
# - Make a release build.
# - Run unit tests for all Rust crates (including the filetests)
# - Build API documentation.
# - Optionally, run fuzzing.
#
# All tests run by this script should be passing at all times.

# Disable generation of .pyc files because they cause trouble for vendoring
# scripts, and this is a build step that isn't run very often anyway.
export PYTHONDONTWRITEBYTECODE=1

# Repository top-level directory.
topdir=$(dirname "$0")
cd "$topdir"

function banner {
    echo "======  $*  ======"
}

# Run rustfmt if we have it.
banner "Rust formatting"
if cargo +stable fmt -- --version > /dev/null ; then
    if ! "$topdir/format-all.sh" --check ; then
        echo "Formatting diffs detected! Run \"cargo fmt --all\" to correct."
        exit 1
    fi
else
    echo "cargo-fmt not available; formatting not checked!"
    echo
    echo "If you are using rustup, rustfmt can be installed via"
    echo "\"rustup component add --toolchain=stable rustfmt-preview\", or see"
    echo "https://github.com/rust-lang-nursery/rustfmt for more information."
fi

# Check if any Python files have changed since we last checked them.
tsfile="$topdir/target/meta-checked"
meta_python="$topdir/lib/codegen/meta-python"
if [ -f "$tsfile" ]; then
    needcheck=$(find "$meta_python" -name '*.py' -newer "$tsfile")
else
    needcheck=yes
fi
if [ -n "$needcheck" ]; then
    banner "Checking python source files"
    "$meta_python/check.sh"
    touch "$tsfile" || echo no target directory
fi

# Make sure the code builds in release mode.
banner "Rust release build"
cargo build --release

# Make sure the code builds in debug mode.
banner "Rust debug build"
cargo build

# Run the tests. We run these in debug mode so that assertions are enabled.
banner "Rust unit tests"
RUST_BACKTRACE=1 cargo test --all

# Make sure the documentation builds.
banner "Rust documentation: $topdir/target/doc/cranelift/index.html"
cargo doc

# Ensure fuzzer works by running it with a single input
# Note LSAN is disabled due to https://github.com/google/sanitizers/issues/764
banner "cargo fuzz check"
if rustup toolchain list | grep -q nightly; then
    if cargo install --list | grep -q cargo-fuzz; then
        echo "cargo-fuzz found"
    else
        echo "installing cargo-fuzz"
        cargo +nightly install cargo-fuzz
    fi

    fuzz_module="ffaefab69523eb11935a9b420d58826c8ea65c4c"
    ASAN_OPTIONS=detect_leaks=0 \
    cargo +nightly fuzz run fuzz_translate_module \
        "$topdir/fuzz/corpus/fuzz_translate_module/$fuzz_module"
else
    echo "nightly toolchain not found, skipping fuzz target integration test"
fi

banner "OK"
