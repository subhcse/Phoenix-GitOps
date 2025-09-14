# scripts/install-tools.sh
#!/bin/bash
set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Detect OS
OS="$(uname -s)"
ARCH="$(uname -m)"

case $OS in
    Linux*)  
        PLATFORM="linux"
        if [[ $ARCH == "x86_64" ]]; then
            ARCH="amd64"
        elif [[ $ARCH == "aarch64" ]]; then
            ARCH="arm64"
        fi
        ;;
    Darwin*) 
        PLATFORM="darwin"
        if [[ $ARCH == "x86_64" ]]; then
            ARCH="amd64"
        elif [[ $ARCH == "arm64" ]]; then
            ARCH="arm64"
        fi
        ;;
    *)       
        echo "Unsupported OS: $OS"
        exit 1
        ;;
esac

# Install kubectl
install_kubectl() {
    if command -v kubectl &> /dev/null; then
        log_info "kubectl already installed"
        return 0
    fi
    
    log_info "Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/$PLATFORM/$ARCH/kubectl"
    sudo install kubectl /usr/local/bin/kubectl
    rm kubectl
    log_success "kubectl installed"
}

# Install k3d
install_k3d() {
    if command -v k3d &> /dev/null; then
        log_info "k3d already installed"
        return 0
    fi
    
    log_info "Installing k3d..."
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
    log_success "k3d installed"
}

# Install Flux CLI
install_flux() {
    if command -v flux &> /dev/null; then
        log_info "flux already installed"
        return 0
    fi
    
    log_info "Installing Flux CLI..."
    curl -s https://fluxcd.io/install.sh | sudo bash
    log_success "flux installed"
}

# Install Helm
install_helm() {
    if command -v helm &> /dev/null; then
        log_info "helm already installed"
        return 0
    fi
    
    log_info "Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    log_success "helm installed"
}

# Install Docker (if not present)
install_docker() {
    if command -v docker &> /dev/null; then
        log_info "docker already installed"
        return 0
    fi
    
    log_info "Installing Docker..."
    case $PLATFORM in
        linux)
            curl -fsSL https://get.docker.com | sh
            sudo usermod -aG docker $USER
            log_info "Please log out and back in for Docker group membership to take effect"
            ;;
        darwin)
            log_info "Please install Docker Desktop from https://docker.com/products/docker-desktop"
            ;;
    esac
    log_success "docker installation initiated"
}

# Main installation
main() {
    log_info "Installing required tools for Phoenix GitOps Homelab..."
    
    install_docker
    install_kubectl
    install_k3d
    install_flux
    install_helm
    
    log_success "All tools installed successfully!"
    
    echo ""
    echo "Next steps:"
    echo "1. Set environment variables:"
    echo "   export GITHUB_TOKEN=your_github_token"
    echo "   export GITHUB_USER=your_github_username"
    echo ""
    echo "2. Run the bootstrap script:"
    echo "   ./scripts/bootstrap.sh"
}

main "$@"

---
# Makefile
.PHONY: help bootstrap dev-up dev-down cluster-create cluster-delete flux-install flux-bootstrap build push deploy status health-check logs-phoenix logs-flux backup-db scale-up scale-down test-all clean

# Configuration
CLUSTER_NAME ?= phoenix-cluster
DOMAIN_SUFFIX ?= local
DOCKER_USERNAME ?= your-docker-hub-username
IMAGE_NAME ?= phoenix-app
TAG ?= latest
NAMESPACE ?= phoenix-app

# Colors
GREEN := \033[32m
YELLOW := \033[33m
BLUE := \033[34m
NC := \033[0m

help: ## Show this help message
	@echo "Phoenix GitOps Homelab - Available Commands:"
	@echo ""
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Environment Variables:"
	@echo "  GITHUB_TOKEN    - GitHub personal access token"
	@echo "  GITHUB_USER     - GitHub username"
	@echo "  DOCKER_USERNAME - Docker Hub username"

bootstrap: ## Bootstrap the entire GitOps homelab
	@echo "$(BLUE)🚀 Bootstrapping Phoenix GitOps Homelab...$(NC)"
	@./scripts/bootstrap.sh bootstrap

install-tools: ## Install required tools
	@echo "$(BLUE)🔧 Installing required tools...$(NC)"
	@./scripts/install-tools.sh

dev-up: ## Start local development environment
	@echo "$(BLUE)🏗️ Starting development environment...$(NC)"
	@docker-compose -f phoenix-app/docker-compose.yml up -d
	@echo "$(GREEN)📱 Application URLs:$(NC)"
	@echo "  Phoenix App:  http://phoenix.$(DOMAIN_SUFFIX)"
	@echo "  Grafana:      http://grafana.$(DOMAIN_SUFFIX)"
	@echo "  Prometheus:   http://prometheus.$(DOMAIN_SUFFIX)"

health-check: ## Run comprehensive health checks
	@echo "$(BLUE)🏥 Running health checks...$(NC)"
	@./scripts/bootstrap.sh health

logs-phoenix: ## View Phoenix application logs
	@echo "$(BLUE)📋 Phoenix application logs:$(NC)"
	@kubectl logs -n $(NAMESPACE) deployment/phoenix-app -f --tail=50

logs-flux: ## View Flux controller logs
	@echo "$(BLUE)📋 Flux controller logs:$(NC)"
	@flux logs --all-namespaces --tail=50

backup-db: ## Backup PostgreSQL database
	@echo "$(BLUE)💾 Creating database backup...$(NC)"
	@./scripts/backup-restore.sh backup

scale-up: ## Scale Phoenix app up
	@echo "$(BLUE)📈 Scaling Phoenix app up...$(NC)"
	@kubectl scale deployment phoenix-app -n $(NAMESPACE) --replicas=5
	@kubectl rollout status deployment/phoenix-app -n $(NAMESPACE)
	@echo "$(GREEN)✅ Phoenix app scaled up!$(NC)"

scale-down: ## Scale Phoenix app down
	@echo "$(BLUE)📉 Scaling Phoenix app down...$(NC)"
	@kubectl scale deployment phoenix-app -n $(NAMESPACE) --replicas=1
	@kubectl rollout status deployment/phoenix-app -n $(NAMESPACE)
	@echo "$(GREEN)✅ Phoenix app scaled down!$(NC)"

test-all: ## Run all tests
	@echo "$(BLUE)🧪 Running all tests...$(NC)"
	@./tests/integration/test-deployment.sh
	@./tests/integration/test-database.sh
	@./tests/integration/test-monitoring.sh
	@echo "$(GREEN)✅ All tests passed!$(NC)"

clean: ## Clean up all resources
	@echo "$(YELLOW)🧹 Cleaning up resources...$(NC)"
	@./scripts/bootstrap.sh cleanup
	@echo "$(GREEN)✅ Cleanup completed!$(NC)"

# Development helpers
dev-logs: ## Show development environment logs
	@docker-compose -f phoenix-app/docker-compose.yml logs -f

dev-shell: ## Access development database shell
	@docker-compose -f phoenix-app/docker-compose.yml exec db psql -U postgres -d phoenix_app

dev-reset: ## Reset development environment
	@docker-compose -f phoenix-app/docker-compose.yml down -v
	@docker-compose -f phoenix-app/docker-compose.yml up -d

# Monitoring helpers
port-forward-grafana: ## Port forward Grafana (emergency access)
	@echo "$(BLUE)🔄 Port forwarding Grafana to localhost:3000...$(NC)"
	@kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

port-forward-prometheus: ## Port forward Prometheus (emergency access)
	@echo "$(BLUE)🔄 Port forwarding Prometheus to localhost:9090...$(NC)"
	@kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090

# Debugging helpers
describe-phoenix: ## Describe Phoenix app resources
	@kubectl describe deployment phoenix-app -n $(NAMESPACE)
	@kubectl describe pods -l app.kubernetes.io/name=phoenix-app -n $(NAMESPACE)

get-secrets: ## Show available secrets (names only)
	@echo "$(BLUE)🔐 Available secrets:$(NC)"
	@kubectl get secrets -A | grep -v "Opaque.*3" | head -20

flux-suspend: ## Suspend Flux reconciliation
	@echo "$(YELLOW)⏸️ Suspending Flux reconciliation...$(NC)"
	@flux suspend kustomization infrastructure
	@flux suspend kustomization apps

flux-resume: ## Resume Flux reconciliation
	@echo "$(GREEN)▶️ Resuming Flux reconciliation...$(NC)"
	@flux resume kustomization infrastructure
	@flux resume kustomization apps

# Quick commands for common tasks
quick-deploy: cluster-create flux-install apply-local status ## Quick deployment without GitHub bootstrap

apply-local: ## Apply configurations locally (without Flux)
	@echo "$(BLUE)📝 Applying local configurations...$(NC)"
	@kubectl apply -k ./kubernetes/bootstrap/
	@kubectl apply -k ./kubernetes/infrastructure/
	@kubectl apply -k ./kubernetes/apps/

wait-ready: ## Wait for all deployments to be ready
	@echo "$(BLUE)⏳ Waiting for deployments to be ready...$(NC)"
	@kubectl wait --for=condition=available --timeout=300s deployment --all -n flux-system || true
	@kubectl wait --for=condition=available --timeout=300s deployment --all -n ingress-nginx || true
	@kubectl wait --for=condition=available --timeout=300s deployment --all -n cnpg-system || true
	@kubectl wait --for=condition=available --timeout=300s deployment --all -n monitoring || true
	@kubectl wait --for=condition=available --timeout=300s deployment --all -n $(NAMESPACE) || true
	@echo "$(GREEN)✅ All deployments are ready!$(NC)"

---

---
