---
# tests/integration/test-monitoring.sh
#!/bin/bash
set -euo pipefail

echo "📊 Testing Monitoring Stack"
echo "=========================="

# Test Prometheus targets
echo "Testing Prometheus targets..."
curl -s http://prometheus.local/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Test Grafana API
echo "Testing Grafana API..."
curl -s http://grafana.local/api/health | jq '.'

# Test alert rules
echo "Testing alert rules..."
curl -s http://prometheus.local/api/v1/rules | jq '.data.groups[].rules[] | select(.type == "alerting") | .name'

# Test ServiceMonitor
echo "Testing ServiceMonitor..."
kubectl get servicemonitor -n monitoring phoenix-app -o yaml

echo "✅ Monitoring tests completed!"
