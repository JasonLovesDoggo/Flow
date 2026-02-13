# Flow build tasks

# Default: build everything
default: build

# Build helper and main app
build: build-helper build-app

# Build just the helper
build-helper:
    cd FlowHelper && swift build

# Build just the main app
build-app:
    swift build

# Build release versions
release: release-helper release-app

release-helper:
    cd FlowHelper && swift build -c release

release-app:
    swift build -c release

# Run the app (builds helper first if needed)
run: build-helper
    swift run

# Clean all build artifacts
clean:
    rm -rf .build
    rm -rf FlowHelper/.build

# Build and run
dev: build run

# Format code (if swift-format available)
fmt:
    swift-format -i -r Sources/ || echo "swift-format not installed"
    swift-format -i -r FlowHelper/Sources/ || echo "swift-format not installed"

# Check the Rust core builds
rust:
    cd flow-core && cargo build

rust-release:
    cd flow-core && cargo build --release

# Full release build (Rust + Swift)
full-release: rust-release release
