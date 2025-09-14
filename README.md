# Phoenix GitOps Homelab Repository
A complete GitOps-managed Phoenix application deployment on Kubernetes using FluxCD, following homelab best practices.

 phoenix-gitops-homelab/
├── README.md                           # This file
├── Makefile                           # Automation commands
├── .github/
│   └── workflows/
│       ├── docker-build.yml           # CI for Phoenix app image
│       ├── security-scan.yml          # Security scanning
│       └── test.yml                   # Repository validation
├── docs/
│   ├── architecture.md               # Architecture documentation
│   ├── troubleshooting.md            # Common issues and solutions
│   └── operations.md                 # Day-2 operations guide
├── scripts/
│   ├── bootstrap.sh                  # One-shot cluster setup
│   ├── install-tools.sh              # Install required tools
│   ├── health-check.py               # Health monitoring script
│   └── backup-restore.sh             # Database backup/restore
├── phoenix-app/
│   ├── Dockerfile                    # Phoenix application container
│   ├── docker-compose.yml           # Local development
│   ├── .dockerignore                # Docker ignore patterns
│   └── lib/                         # Phoenix app modifications
│       ├── health_controller.ex     # Health check endpoint
│       ├── metrics_controller.ex    # Metrics endpoint
│       └── release.ex               # Release utilities
├── kubernetes/
│   ├── bootstrap/                   # Initial cluster setup
│   │   ├── flux-system/            # Flux installation
│   │   │   ├── kustomization.yaml
│   │   │   ├── gotk-components.yaml
│   │   │   └── gotk-sync.yaml
│   │   └── sealed-secrets/         # Secret management
│   │       ├── namespace.yaml
│   │       └── controller.yaml
│   ├── infrastructure/             # Infrastructure components
│   │   ├── kustomization.yaml
│   │   ├── ingress-nginx/         # Ingress controller
│   │   │   ├── namespace.yaml
│   │   │   ├── helmrepository.yaml
│   │   │   ├── helmrelease.yaml
│   │   │   └── values.yaml
│   │   ├── cloudnativepg/         # PostgreSQL operator
│   │   │   ├── namespace.yaml
│   │   │   ├── helmrepository.yaml
│   │   │   └── helmrelease.yaml
│   │   ├── monitoring/            # Monitoring stack
│   │   │   ├── namespace.yaml
│   │   │   ├── helmrepository.yaml
│   │   │   ├── helmrelease.yaml
│   │   │   ├── values.yaml
│   │   │   ├── servicemonitor.yaml
│   │   │   └── prometheus-rules.yaml
│   │   └── cert-manager/          # SSL certificates
│   │       ├── namespace.yaml
│   │       ├── helmrepository.yaml
│   │       └── helmrelease.yaml
│   ├── apps/                      # Application deployments
│   │   ├── kustomization.yaml
│   │   ├── database/              # PostgreSQL cluster
│   │   │   ├── namespace.yaml
│   │   │   ├── cluster.yaml
│   │   │   ├── secret.yaml
│   │   │   └── backup.yaml
│   │   └── phoenix/               # Phoenix application
│   │       ├── namespace.yaml
│   │       ├── helmrelease.yaml
│   │       ├── values.yaml
│   │       ├── secret.yaml
│   │       └── ingress.yaml
│   └── clusters/                  # Environment-specific configs
│       ├── local/                 # Local development
│       │   ├── kustomization.yaml
│       │   ├── infrastructure.yaml
│       │   └── apps.yaml
│       └── production/            # Production (future)
│           ├── kustomization.yaml
│           ├── infrastructure.yaml
│           └── apps.yaml
├── charts/
│   └── phoenix-app/               # Helm chart for Phoenix app
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── templates/
│       │   ├── _helpers.tpl
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   ├── ingress.yaml
│       │   ├── secret.yaml
│       │   ├── configmap.yaml
│       │   ├── serviceaccount.yaml
│       │   ├── hpa.yaml
│       │   ├── servicemonitor.yaml
│       │   └── poddisruptionbudget.yaml
│       └── tests/
│           └── test-connection.yaml
├── monitoring/
│   ├── dashboards/               # Grafana dashboards
│   │   ├── phoenix-app.json     # Application dashboard
│   │   ├── cloudnativepg.json   # Database dashboard
│   │   └── infrastructure.json  # Infrastructure dashboard
│   ├── alerts/                  # Alert rules
│   │   ├── phoenix-app.yaml    # App-specific alerts
│   │   ├── database.yaml       # Database alerts
│   │   └── infrastructure.yaml # Infrastructure alerts
│   └── webhook/                 # Alert webhook receiver
│       ├── alertmanager-webhook.py
│       └── requirements.txt
├── config/
│   ├── local.env               # Local environment variables
│   ├── secrets.example         # Secret templates
│   └── hosts.example          # /etc/hosts entries
└── tests/
    ├── integration/           # Integration tests
    │   ├── test-deployment.sh
    │   ├── test-database.sh
    │   └── test-monitoring.sh
    └── unit/                  # Unit tests
        └── test-helm-charts.sh
