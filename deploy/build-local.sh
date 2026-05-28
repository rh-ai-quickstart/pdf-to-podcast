#!/bin/bash
# Helper script to build images from local files on OpenShift

set -e

NAMESPACE="${NAMESPACE:-pdf-to-podcast}"
BUILD_ALL="${BUILD_ALL:-false}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function print_usage() {
    echo "Usage: $0 [service-name|all]"
    echo ""
    echo "Available services:"
    echo "  api        - API Service"
    echo "  agent      - Agent Service"
    echo "  pdf        - PDF Service"
    echo "  tts        - TTS Service"
    echo "  pdf-api    - PDF Model API"
    echo "  worker     - Celery Worker"
    echo "  all        - Build all services"
    echo ""
    echo "Examples:"
    echo "  $0 tts              # Build TTS service"
    echo "  $0 all              # Build all services"
    echo "  NAMESPACE=my-ns $0 api  # Build in specific namespace"
}

function build_service() {
    local service_name=$1
    local build_config=$2

    echo -e "${YELLOW}Building ${service_name}...${NC}"

    if ! oc get bc "${build_config}" -n "${NAMESPACE}" &>/dev/null; then
        echo -e "${RED}BuildConfig ${build_config} not found in namespace ${NAMESPACE}${NC}"
        echo "Make sure you've installed the Helm chart first"
        return 1
    fi

    # Start build from current directory (repo root)
    if oc start-build "${build_config}" --from-dir=. --follow -n "${NAMESPACE}"; then
        echo -e "${GREEN}✓ ${service_name} built successfully${NC}"
    else
        echo -e "${RED}✗ ${service_name} build failed${NC}"
        return 1
    fi
}

# Check if running from repo root
if [ ! -d "services" ] || [ ! -d "shared" ]; then
    echo -e "${RED}Error: This script must be run from the repository root${NC}"
    echo "Current directory: $(pwd)"
    exit 1
fi

# Check if oc is available
if ! command -v oc &> /dev/null; then
    echo -e "${RED}Error: oc command not found. Please install OpenShift CLI${NC}"
    exit 1
fi

# Check if logged in
if ! oc whoami &>/dev/null; then
    echo -e "${RED}Error: Not logged in to OpenShift. Run 'oc login' first${NC}"
    exit 1
fi

case "${1:-}" in
    api)
        build_service "API Service" "pdf-api-build"
        ;;
    agent)
        build_service "Agent Service" "pdf-agent-build"
        ;;
    pdf)
        build_service "PDF Service" "pdf-service-build"
        ;;
    tts)
        build_service "TTS Service" "pdf-tts-build"
        ;;
    pdf-api)
        build_service "PDF Model API" "pdf-model-api-build"
        ;;
    worker)
        build_service "Celery Worker" "pdf-celery-worker-build"
        ;;
    all)
        echo -e "${YELLOW}Building all services...${NC}"
        build_service "API Service" "pdf-api-build"
        build_service "Agent Service" "pdf-agent-build"
        build_service "PDF Service" "pdf-service-build"
        build_service "TTS Service" "pdf-tts-build"
        build_service "PDF Model API" "pdf-model-api-build"
        build_service "Celery Worker" "pdf-celery-worker-build"
        echo -e "${GREEN}All builds completed!${NC}"
        ;;
    -h|--help|help)
        print_usage
        ;;
    *)
        echo -e "${RED}Error: Invalid service name or missing argument${NC}"
        echo ""
        print_usage
        exit 1
        ;;
esac
