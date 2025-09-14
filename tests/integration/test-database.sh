---
# tests/integration/test-database.sh
#!/bin/bash
set -euo pipefail

echo "🗄️ Testing PostgreSQL Database Setup"
echo "===================================="

# Test cluster status
echo "Testing cluster status..."
kubectl get cluster postgres-cluster -n database -o yaml | grep -A 5 "status:"

# Test database connection
echo "Testing database connectivity..."
kubectl run db-test --rm -i --restart=Never --image=postgres:15 --namespace=database -- \
  psql -h postgres-cluster-rw.database.svc.cluster.local -U app_user -d phoenix_app -c "SELECT version();"

# Test backup configuration
echo "Testing backup configuration..."
kubectl get scheduledbackup -n database

echo "✅ Database tests completed!"
