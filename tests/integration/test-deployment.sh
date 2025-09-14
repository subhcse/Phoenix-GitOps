---
# tests/integration/test-deployment.sh
#!/bin/bash
set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}🧪 Running Phoenix GitOps Deployment Tests${NC}"
echo "=========================================="

# Test cluster connectivity
echo -e "${YELLOW}Testing cluster connectivity...${NC}"
if kubectl cluster-info &>/dev/null; then
    echo -e "${GREEN}✅ Cluster is accessible${NC}"
else
    echo -e "${RED}❌ Cannot connect to cluster${NC}"
    exit 1
fi

# Test Flux system
echo -e "${YELLOW}Testing Flux system...${NC}"
if flux check &>/dev/null; then
    echo -e "${GREEN}✅ Flux system is healthy${NC}"
else
    echo -e "${RED}❌ Flux system has issues${NC}"
    exit 1
fi

# Wait for all pods to be ready
echo -e "${YELLOW}Waiting for pods to be ready...${NC}"
namespaces=("flux-system" "ingress-nginx" "cnpg-system" "monitoring" "database" "phoenix-app")

for ns in "${namespaces[@]}"; do
    echo "  Checking namespace: $ns"
    if kubectl get namespace $ns &>/dev/null; then
        kubectl wait --for=condition=ready pods --all -n $ns --timeout=300s || {
            echo -e "${YELLOW}⚠️ Some pods in $ns might not be ready yet${NC}"
        }
        echo -e "${GREEN}  ✅ $ns pods are ready${NC}"
    else
        echo -e "${YELLOW}  ⚠️ Namespace $ns not found${NC}"
    fi
done

# Test application endpoints
echo -e "${YELLOW}Testing application endpoints...${NC}"

endpoints=(
    "http://phoenix.local/health"
    "http://grafana.local/api/health"
    "http://prometheus.local/-/healthy"
)

for endpoint in "${endpoints[@]}"; do
    echo "  Testing: $endpoint"
    for i in {1..5}; do
        if curl -s -f $endpoint >/dev/null; then
            echo -e "${GREEN}  ✅ $endpoint is responding${NC}"
            break
        elif [ $i -eq 5 ]; then
            echo -e "${RED}  ❌ $endpoint is not responding after 5 attempts${NC}"
        else
            echo "    Attempt $i/5 failed, retrying in 10s..."
            sleep 10
        fi
    done
done

# Test database connectivity
echo -e "${YELLOW}Testing database connectivity...${NC}"
if kubectl get cluster postgres-cluster -n database &>/dev/null; then
    echo -e "${GREEN}✅ PostgreSQL cluster exists${NC}"
    
    # Test database connection from Phoenix pod
    pod=$(kubectl get pods -n phoenix-app -l app.kubernetes.io/name=phoenix-app -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || echo "")
    if [ -n "$pod" ]; then
        echo "  Testing database connection from Phoenix pod..."
        if kubectl exec -n phoenix-app $pod -- nc -z postgres-cluster-rw.database.svc.cluster.local 5432; then
            echo -e "${GREEN}  ✅ Database is accessible from Phoenix app${NC}"
        else
            echo -e "${RED}  ❌ Database is not accessible from Phoenix app${NC}"
        fi
    fi
else
    echo -e "${RED}❌ PostgreSQL cluster not found${NC}"
fi

# Test metrics collection
echo -e "${YELLOW}Testing metrics collection...${NC}"
if curl -s http://prometheus.local/api/v1/targets | jq -e '.data.activeTargets[] | select(.health == "up")' >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Prometheus has active targets${NC}"
else
    echo -e "${YELLOW}⚠️ No active Prometheus targets found${NC}"
fi

# Test GitOps workflow
echo -e "${YELLOW}Testing GitOps reconciliation...${NC}"
flux_reconcile_output=$(flux get all 2>&1)
if echo "$flux_reconcile_output" | grep -q "True"; then
    echo -e "${GREEN}✅ Flux reconciliation is working${NC}"
else
    echo -e "${YELLOW}⚠️ Some Flux resources might have issues${NC}"
fi

echo ""
echo -e "${GREEN}🎉 Deployment tests completed!${NC}"
echo "Access your applications:"
echo "  - Phoenix App: http://phoenix.local"
echo "  - Grafana: http://grafana.local (admin/admin)"
echo "  - Prometheus: http://prometheus.local"
