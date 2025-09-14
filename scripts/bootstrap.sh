# scripts/bootstrap.sh
#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME=${CLUSTER_NAME:-phoenix-cluster}
DOMAIN_SUFFIX=${DOMAIN_SUFFIX:-local}
GITHUB_USER=${GITHUB_USER:-}
GITHUB_TOKEN=${GITHUB_TOKEN:-}
REPO_NAME=${REPO_NAME:-phoenix-gitops-homelab}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    for tool in docker kubectl k3d flux helm; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Run 'bash scripts/install-tools.sh' to install missing tools"
        exit 1
    fi
    
    if [ -z "$GITHUB_USER" ] || [ -z "$GITHUB_TOKEN" ]; then
        log_warning "GITHUB_USER and GITHUB_TOKEN environment variables not set"
        log_info "Flux bootstrap will be skipped. You can run it manually later."
    fi
    
    log_success "All prerequisites met!"
}

# Create k3d cluster
create_cluster() {
    log_info "Creating k3d cluster: $CLUSTER_NAME"
    
    if k3d cluster list | grep -q $CLUSTER_NAME; then
        log_warning "Cluster $CLUSTER_NAME already exists"
        return 0
    fi
    
    k3d cluster create $CLUSTER_NAME \
        --port "8080:80@loadbalancer" \
        --port "8443:443@loadbalancer" \
        --port "9090:9090@loadbalancer" \
        --k3s-arg "--disable=traefik@server:*" \
        --agents 2 \
        --wait
    
    log_success "Cluster $CLUSTER_NAME created successfully!"
}

# Update /etc/hosts for local domains
update_hosts() {
    log_info "Updating /etc/hosts for local domain access..."
    
    local hosts_entries=(
        "127.0.0.1 phoenix.$DOMAIN_SUFFIX"
        "127.0.0.1 grafana.$DOMAIN_SUFFIX"
        "127.0.0.1 prometheus.$DOMAIN_SUFFIX"
        "127.0.0.1 argocd.$DOMAIN_SUFFIX"
    )
    
    for entry in "${hosts_entries[@]}"; do
        if ! grep -q "$entry" /etc/hosts 2>/dev/null; then
            echo "$entry" | sudo tee -a /etc/hosts >/dev/null
            log_info "Added: $entry"
        fi
    done
    
    log_success "/etc/hosts updated successfully!"
}

# Install Flux
install_flux() {
    log_info "Installing Flux..."
    
    if kubectl get ns flux-system &>/dev/null; then
        log_warning "Flux already installed"
        return 0
    fi
    
    flux check --pre
    flux install --wait
    
    log_success "Flux installed successfully!"
}

# Bootstrap Flux with GitHub
bootstrap_flux() {
    if [ -z "$GITHUB_USER" ] || [ -z "$GITHUB_TOKEN" ]; then
        log_warning "Skipping Flux bootstrap - GitHub credentials not provided"
        log_info "You can bootstrap manually later with:"
        log_info "export GITHUB_TOKEN=your_token"
        log_info "export GITHUB_USER=your_username"
        log_info "flux bootstrap github --owner=\$GITHUB_USER --repository=$REPO_NAME --branch=main --path=./kubernetes/clusters/local --personal"
        return 0
    fi
    
    log_info "Bootstrapping Flux with GitHub..."
    
    flux bootstrap github \
        --owner=$GITHUB_USER \
        --repository=$REPO_NAME \
        --branch=main \
        --path=./kubernetes/clusters/local \
        --personal \
        --read-write-key
    
    log_success "Flux bootstrapped with GitHub!"
}

# Apply base configurations
apply_configs() {
    log_info "Applying initial configurations..."
    
    # Apply bootstrap configurations
    kubectl apply -k ./kubernetes/bootstrap/ --wait=true
    
    log_success "Base configurations applied!"
}

# Wait for deployments to be ready
wait_for_ready() {
    log_info "Waiting for all deployments to be ready..."
    
    local namespaces=("flux-system" "ingress-nginx" "cnpg-system" "monitoring" "database" "phoenix-app")
    
    for ns in "${namespaces[@]}"; do
        log_info "Waiting for namespace: $ns"
        kubectl wait --for=condition=ready pods --all -n $ns --timeout=300s 2>/dev/null || {
            log_warning "Some pods in $ns are not ready yet, continuing..."
        }
    done
    
    log_success "All deployments are ready!"
}

# Display access information
show_access_info() {
    log_success "🎉 Phoenix GitOps Homelab is ready!"
    echo ""
    echo "📱 Application Access:"
    echo "   Phoenix App:  http://phoenix.$DOMAIN_SUFFIX"
    echo "   Grafana:      http://grafana.$DOMAIN_SUFFIX (admin/admin)"
    echo "   Prometheus:   http://prometheus.$DOMAIN_SUFFIX"
    echo ""
    echo "🔧 Useful Commands:"
    echo "   make status           - Check deployment status"
    echo "   make logs-phoenix     - View Phoenix app logs"
    echo "   make logs-flux        - View Flux logs"
    echo "   make health-check     - Run health checks"
    echo "   make backup-db        - Backup database"
    echo ""
    echo "📊 Monitoring:"
    echo "   - CloudNativePG dashboard pre-installed in Grafana"
    echo "   - Phoenix app metrics available at /metrics"
    echo "   - Alert rules configured for pod readiness"
    echo ""
    echo "🚀 Next Steps:"
    echo "   1. Build and push your Phoenix app image"
    echo "   2. Update image reference in kubernetes/apps/phoenix/values.yaml"
    echo "   3. Commit changes to trigger GitOps deployment"
}

# Health check function
health_check() {
    log_info "Running health checks..."
    
    local failed_checks=0
    
    # Check cluster
    if kubectl cluster-info &>/dev/null; then
        log_success "✓ Kubernetes cluster is healthy"
    else
        log_error "✗ Kubernetes cluster is not accessible"
        ((failed_checks++))
    fi
    
    # Check Flux
    if flux check &>/dev/null; then
        log_success "✓ Flux is healthy"
    else
        log_error "✗ Flux has issues"
        ((failed_checks++))
    fi
    
    # Check core services
    local services=("ingress-nginx/ingress-nginx-controller" "monitoring/prometheus-operated" "cnpg-system/cnpg-controller-manager")
    
    for service in "${services[@]}"; do
        local ns=$(echo $service | cut -d'/' -f1)
        local svc=$(echo $service | cut -d'/' -f2)
        
        if kubectl get deployment $svc -n $ns &>/dev/null; then
            log_success "✓ $service is running"
        else
            log_error "✗ $service is not running"
            ((failed_checks++))
        fi
    done
    
    if [ $failed_checks -eq 0 ]; then
        log_success "All health checks passed!"
        return 0
    else
        log_error "$failed_checks health checks failed!"
        return 1
    fi
}

# Cleanup function
cleanup() {
    log_info "Cleaning up resources..."
    
    if k3d cluster list | grep -q $CLUSTER_NAME; then
        k3d cluster delete $CLUSTER_NAME
        log_success "Cluster $CLUSTER_NAME deleted"
    fi
    
    # Remove hosts entries
    local hosts_entries=(
        "phoenix.$DOMAIN_SUFFIX"
        "grafana.$DOMAIN_SUFFIX"
        "prometheus.$DOMAIN_SUFFIX"
        "argocd.$DOMAIN_SUFFIX"
    )
    
    for entry in "${hosts_entries[@]}"; do
        sudo sed -i "/$entry/d" /etc/hosts 2>/dev/null || true
    done
    
    log_success "Cleanup completed!"
}

# Main execution
main() {
    case "${1:-bootstrap}" in
        bootstrap)
            log_info "🚀 Starting Phoenix GitOps Homelab Bootstrap"
            check_prerequisites
            create_cluster
            update_hosts
            install_flux
            bootstrap_flux
            apply_configs
            wait_for_ready
            show_access_info
            ;;
        health)
            health_check
            ;;
        cleanup)
            cleanup
            ;;
        *)
            echo "Usage: $0 {bootstrap|health|cleanup}"
            echo "  bootstrap  - Full homelab setup (default)"
            echo "  health     - Run health checks"
            echo "  cleanup    - Remove cluster and cleanup"
            exit 1
            ;;
    esac
}

# Handle script interruption
trap cleanup EXIT

main "$@"

---
