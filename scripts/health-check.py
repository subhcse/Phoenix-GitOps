# scripts/health-check.py
#!/usr/bin/env python3
"""
Phoenix GitOps Homelab Health Check Script
Comprehensive health monitoring for all components
"""

import subprocess
import requests
import json
import sys
import time
from datetime import datetime
from typing import Dict, List, Tuple, Optional

class HealthChecker:
    def __init__(self):
        self.checks_passed = 0
        self.checks_failed = 0
        self.warnings = []
        
    def run_command(self, cmd: List[str]) -> Tuple[bool, str]:
        """Execute shell command and return success status and output"""
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            return result.returncode == 0, result.stdout.strip()
        except subprocess.TimeoutExpired:
            return False, "Command timeout"
        except Exception as e:
            return False, str(e)
    
    def check_http_endpoint(self, url: str, expected_status: int = 200) -> bool:
        """Check if HTTP endpoint is responding correctly"""
        try:
            response = requests.get(url, timeout=10)
            return response.status_code == expected_status
        except requests.RequestException:
            return False
    
    def log_check(self, name: str, success: bool, message: str = ""):
        """Log check result"""
        status = "✅ PASS" if success else "❌ FAIL"
        print(f"{status} | {name:<30} | {message}")
        
        if success:
            self.checks_passed += 1
        else:
            self.checks_failed += 1
    
    def log_warning(self, message: str):
        """Log warning message"""
        print(f"⚠️  WARN | {message}")
        self.warnings.append(message)
    
    def check_kubernetes_cluster(self):
        """Check Kubernetes cluster connectivity"""
        print("\n🔧 Kubernetes Cluster Health")
        print("=" * 50)
        
        # Cluster info
        success, output = self.run_command(["kubectl", "cluster-info"])
        self.log_check("Cluster connectivity", success, 
                      "Connected" if success else "Cannot connect to cluster")
        
        # Node status
        success, output = self.run_command(["kubectl", "get", "nodes", "-o", "json"])
        if success:
            try:
                nodes = json.loads(output)
                ready_nodes = 0
                total_nodes = len(nodes['items'])
                
                for node in nodes['items']:
                    conditions = node['status']['conditions']
                    for condition in conditions:
                        if condition['type'] == 'Ready' and condition['status'] == 'True':
                            ready_nodes += 1
                            break
                
                self.log_check("Node readiness", ready_nodes == total_nodes, 
                              f"{ready_nodes}/{total_nodes} nodes ready")
            except (json.JSONDecodeError, KeyError):
                self.log_check("Node readiness", False, "Cannot parse node status")
        else:
            self.log_check("Node readiness", False, "Cannot get node status")
    
    def check_flux_system(self):
        """Check Flux system health"""
        print("\n⚡ Flux System Health")
        print("=" * 50)
        
        # Flux check
        success, output = self.run_command(["flux", "check"])
        self.log_check("Flux system", success, "All components ready" if success else "Issues detected")
        
        # Flux resources
        success, output = self.run_command(["flux", "get", "all"])
        if success:
            self.log_check("Flux resources", True, "All resources reconciled")
        else:
            self.log_check("Flux resources", False, "Some resources not reconciled")
    
    def check_infrastructure_components(self):
        """Check infrastructure component health"""
        print("\n🏗️  Infrastructure Components")
        print("=" * 50)
        
        components = [
            ("ingress-nginx", "ingress-nginx-controller"),
            ("cnpg-system", "cnpg-controller-manager"),
            ("monitoring", "prometheus-operator"),
            ("monitoring", "grafana")
        ]
        
        for namespace, deployment in components:
            success, output = self.run_command([
                "kubectl", "get", "deployment", deployment, 
                "-n", namespace, "-o", "json"
            ])
            
            if success:
                try:
                    dep = json.loads(output)
                    ready = dep['status'].get('readyReplicas', 0)
                    desired = dep['spec']['replicas']
                    
                    component_ready = ready == desired
                    self.log_check(f"{namespace}/{deployment}", component_ready, 
                                  f"{ready}/{desired} replicas ready")
                except (json.JSONDecodeError, KeyError):
                    self.log_check(f"{namespace}/{deployment}", False, "Cannot parse status")
            else:
                self.log_check(f"{namespace}/{deployment}", False, "Deployment not found")
    
    def check_database_cluster(self):
        """Check PostgreSQL cluster health"""
        print("\n🗄️  Database Cluster Health")
        print("=" * 50)
        
        # Check cluster status
        success, output = self.run_command([
            "kubectl", "get", "cluster", "postgres-cluster", 
            "-n", "database", "-o", "json"
        ])
        
        if success:
            try:
                cluster = json.loads(output)
                status = cluster.get('status', {})
                ready_instances = status.get('readyInstances', 0)
                instances = status.get('instances', 0)
                
                cluster_healthy = ready_instances == instances and instances > 0
                self.log_check("PostgreSQL cluster", cluster_healthy, 
                              f"{ready_instances}/{instances} instances ready")
                
                # Check cluster phase
                phase = status.get('phase', 'Unknown')
                self.log_check("Cluster phase", phase == 'Cluster in healthy state', 
                              f"Phase: {phase}")
                
            except (json.JSONDecodeError, KeyError):
                self.log_check("PostgreSQL cluster", False, "Cannot parse cluster status")
        else:
            self.log_check("PostgreSQL cluster", False, "Cluster not found")
    
    def check_phoenix_application(self):
        """Check Phoenix application health"""
        print("\n🔥 Phoenix Application Health")
        print("=" * 50)
        
        # Check deployment
        success, output = self.run_command([
            "kubectl", "get", "deployment", "phoenix-app", 
            "-n", "phoenix-app", "-o", "json"
        ])
        
        if success:
            try:
                dep = json.loads(output)
                ready = dep['status'].get('readyReplicas', 0)
                desired = dep['spec']['replicas']
                
                app_ready = ready == desired
                self.log_check("Phoenix deployment", app_ready, 
                              f"{ready}/{desired} replicas ready")
                
            except (json.JSONDecodeError, KeyError):
                self.log_check("Phoenix deployment", False, "Cannot parse deployment status")
        else:
            self.log_check("Phoenix deployment", False, "Deployment not found")
        
        # Check health endpoint
        health_url = "http://phoenix.local/health"
        if self.check_http_endpoint(health_url):
            self.log_check("Health endpoint", True, "Responding correctly")
        else:
            self.log_check("Health endpoint", False, "Not responding")
    
    def check_monitoring_stack(self):
        """Check monitoring stack health"""
        print("\n📊 Monitoring Stack Health")
        print("=" * 50)
        
        # Prometheus
        prometheus_url = "http://prometheus.local/-/healthy"
        prometheus_healthy = self.check_http_endpoint(prometheus_url)
        self.log_check("Prometheus", prometheus_healthy, 
                      "Healthy" if prometheus_healthy else "Not responding")
        
        # Grafana
        grafana_url = "http://grafana.local/api/health"
        grafana_healthy = self.check_http_endpoint(grafana_url)
        self.log_check("Grafana", grafana_healthy, 
                      "Healthy" if grafana_healthy else "Not responding")
        
        # Check Prometheus targets
        if prometheus_healthy:
            try:
                targets_url = "http://prometheus.local/api/v1/targets"
                response = requests.get(targets_url, timeout=10)
                if response.status_code == 200:
                    data = response.json()
                    active_targets = data['data']['activeTargets']
                    up_targets = [t for t in active_targets if t['health'] == 'up']
                    
                    targets_ratio = f"{len(up_targets)}/{len(active_targets)}"
                    self.log_check("Prometheus targets", len(up_targets) > 0, 
                                  f"{targets_ratio} targets up")
                else:
                    self.log_check("Prometheus targets", False, "Cannot fetch targets")
            except requests.RequestException:
                self.log_check("Prometheus targets", False, "Cannot connect to Prometheus API")
    
    def check_ingress_connectivity(self):
        """Check ingress connectivity"""
        print("\n🌐 Ingress Connectivity")
        print("=" * 50)
        
        endpoints = [
            ("phoenix.local", "Phoenix App"),
            ("grafana.local", "Grafana UI"),
            ("prometheus.local", "Prometheus UI")
        ]
        
        for hostname, description in endpoints:
            url = f"http://{hostname}"
            connected = self.check_http_endpoint(url)
            self.log_check(f"{description}", connected, 
                          f"{url} {'accessible' if connected else 'not accessible'}")
    
    def check_resource_usage(self):
        """Check resource usage"""
        print("\n📈 Resource Usage")
        print("=" * 50)
        
        # Node resource usage
        success, output = self.run_command([
            "kubectl", "top", "nodes", "--no-headers"
        ])
        
        if success:
            for line in output.split('\n'):
                if line.strip():
                    parts = line.split()
                    if len(parts) >= 5:
                        node, cpu, cpu_pct, memory, memory_pct = parts[:5]
                        
                        cpu_usage = int(cpu_pct.rstrip('%'))
                        memory_usage = int(memory_pct.rstrip('%'))
                        
                        node_healthy = cpu_usage < 80 and memory_usage < 80
                        self.log_check(f"Node {node}", node_healthy, 
                                      f"CPU: {cpu_pct}, Memory: {memory_pct}")
                        
                        if cpu_usage > 90 or memory_usage > 90:
                            self.log_warning(f"High resource usage on {node}")
        else:
            self.log_warning("Cannot get node resource usage (metrics-server might not be available)")
    
    def run_all_checks(self):
        """Run all health checks"""
        print(f"🏥 Phoenix GitOps Homelab Health Check")
        print(f"Started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("=" * 80)
        
        self.check_kubernetes_cluster()
        self.check_flux_system()
        self.check_infrastructure_components()
        self.check_database_cluster()
        self.check_phoenix_application()
        self.check_monitoring_stack()
        self.check_ingress_connectivity()
        self.check_resource_usage()
        
        # Summary
        print("\n📋 Health Check Summary")
        print("=" * 50)
        print(f"✅ Passed: {self.checks_passed}")
        print(f"❌ Failed: {self.checks_failed}")
        print(f"⚠️  Warnings: {len(self.warnings)}")
        
        if self.warnings:
            print("\n⚠️  Warnings:")
            for warning in self.warnings:
                print(f"   - {warning}")
        
        print(f"\nOverall Status: {'🟢 HEALTHY' if self.checks_failed == 0 else '🔴 ISSUES DETECTED'}")
        
        return self.checks_failed == 0

if __name__ == "__main__":
    checker = HealthChecker()
    success = checker.run_all_checks()
    sys.exit(0 if success else 1))✅ Development environment started!$(NC)"
	@echo "Phoenix app: http://localhost:4000"

dev-down: ## Stop local development environment
	@echo "$(YELLOW)🛑 Stopping development environment...$(NC)"
	@docker-compose -f phoenix-app/docker-compose.yml down
	@echo "$(GREEN)✅ Development environment stopped!$(NC)"

cluster-create: ## Create k3d cluster
	@echo "$(BLUE)🏗️ Creating k3d cluster...$(NC)"
	@k3d cluster create $(CLUSTER_NAME) \
		--port "8080:80@loadbalancer" \
		--port "8443:443@loadbalancer" \
		--port "9090:9090@loadbalancer" \
		--k3s-arg "--disable=traefik@server:*" \
		--agents 2 \
		--wait
	@echo "$(GREEN)✅ Cluster $(CLUSTER_NAME) created!$(NC)"

cluster-delete: ## Delete k3d cluster
	@echo "$(YELLOW)🗑️ Deleting k3d cluster...$(NC)"
	@k3d cluster delete $(CLUSTER_NAME)
	@echo "$(GREEN)✅ Cluster $(CLUSTER_NAME) deleted!$(NC)"

flux-install: ## Install Flux in the cluster
	@echo "$(BLUE)⚡ Installing Flux...$(NC)"
	@flux check --pre
	@flux install --wait
	@echo "$(GREEN)✅ Flux installed!$(NC)"

flux-bootstrap: ## Bootstrap Flux with GitHub
	@echo "$(BLUE)🔄 Bootstrapping Flux with GitHub...$(NC)"
	@if [ -z "$(GITHUB_TOKEN)" ] || [ -z "$(GITHUB_USER)" ]; then \
		echo "$(YELLOW)⚠️  GITHUB_TOKEN and GITHUB_USER must be set$(NC)"; \
		exit 1; \
	fi
	@flux bootstrap github \
		--owner=$(GITHUB_USER) \
		--repository=phoenix-gitops-homelab \
		--branch=main \
		--path=./kubernetes/clusters/local \
		--personal \
		--read-write-key
	@echo "$(GREEN)✅ Flux bootstrapped!$(NC)"

build: ## Build Phoenix application Docker image
	@echo "$(BLUE)🏗️ Building Phoenix application image...$(NC)"
	@cd phoenix-app && docker build -t $(DOCKER_USERNAME)/$(IMAGE_NAME):$(TAG) .
	@docker tag $(DOCKER_USERNAME)/$(IMAGE_NAME):$(TAG) $(DOCKER_USERNAME)/$(IMAGE_NAME):latest
	@echo "$(GREEN)✅ Image built: $(DOCKER_USERNAME)/$(IMAGE_NAME):$(TAG)$(NC)"

push: ## Push Docker image to registry
	@echo "$(BLUE)📤 Pushing image to registry...$(NC)"
	@docker push $(DOCKER_USERNAME)/$(IMAGE_NAME):$(TAG)
	@docker push $(DOCKER_USERNAME)/$(IMAGE_NAME):latest
	@echo "$(GREEN)✅ Image pushed!$(NC)"

deploy: ## Deploy applications using Flux
	@echo "$(BLUE)🚀 Triggering Flux reconciliation...$(NC)"
	@flux reconcile source git flux-system
	@flux reconcile kustomization infrastructure
	@flux reconcile kustomization apps
	@echo "$(GREEN)✅ Deployment triggered!$(NC)"

status: ## Show deployment status
	@echo "$(BLUE)📊 Checking deployment status...$(NC)"
	@echo ""
	@echo "$(YELLOW)=== Flux Status ===$(NC)"
	@flux get all
	@echo ""
	@echo "$(YELLOW)=== Pod Status ===$(NC)"
	@kubectl get pods -A | grep -E "(NAMESPACE|phoenix|postgres|prometheus|grafana|flux|ingress)"
	@echo ""
	@echo "$(YELLOW)=== Service Status ===$(NC)"
	@kubectl get svc -A | grep -E "(NAMESPACE|phoenix|postgres|prometheus|grafana|ingress)"
	@echo ""
	@echo "$(YELLOW)=== Ingress Status ===$(NC)"
	@kubectl get ingress -A
	@echo ""
	@echo "$(GREEN
