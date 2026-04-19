# PicoBox pinned toolchain versions.
# Pure value declarations — no side effects, safe to source from anywhere
# (shell scripts, CI composite actions, Docker build args, etc.).

# Go / gRPC
export GO_VERSION="1.26.1"
export PROTOC_VERSION="34.0"
export PROTOC_GEN_GO_VERSION="v1.36.11"
export PROTOC_GEN_GO_GRPC_VERSION="v1.6.1"

# Node / Web
export NODE_VERSION="24"

# CI / lint
export GOLANGCI_LINT_VERSION="v2.11.3"
