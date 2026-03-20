# 0. Load Common Utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# 🟢 Go & gRPC
export GO_VERSION="1.26.1"
export PROTOC_VERSION="34.0"
export PROTOC_GEN_GO_VERSION="v1.36.11"
export PROTOC_GEN_GO_GRPC_VERSION="v1.6.1"

# 🔵 Node.js & Web
export NODE_VERSION="24"

# 🟠 CI/CD Tools
export GOLANGCI_LINT_VERSION="v2.11.3"
