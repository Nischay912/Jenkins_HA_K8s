# Jenkins High Availability on Kubernetes

A high availability Jenkins setup on Kubernetes using StatefulSets, leader election, and Helm for automated deployments.

---

## What This Does

- Runs 2 Jenkins pods at all times — one active leader, one standby
- If the active pod dies, standby automatically becomes the new leader
- Jenkins pipeline resumes from the same stage it was running on — not from the beginning
- Image version can be upgraded or rolled back with a single Helm command
- No manual pod deletion or kubectl set image needed for upgrades

---

## Project Structure

```
jenkins-ha-project/
├── Dockerfile
├── monitor.ps1
└── jenkins-ha-chart/
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        ├── namespace.yaml
        ├── rbac.yaml
        ├── pv.yaml
        ├── pvc.yaml
        ├── service.yaml
        ├── nodeport.yaml
        └── statefulset.yaml
```

---

## How It Works

### Leader Election

Each pod has two containers running inside it:

- **jenkins** — the main Jenkins container. It starts in a waiting loop and only launches Jenkins after it wins the election
- **leader-election** — a sidecar container that runs a loop every few seconds, competing for a Kubernetes Lease object. Whoever holds the Lease is the active leader

When a pod dies, the Lease expires after 30 seconds and the standby pod claims it, starts Jenkins, and becomes the new leader.

### Why StatefulSet

StatefulSet gives each pod a stable fixed name — `jenkins-ha-0` and `jenkins-ha-1`. This is required because the Lease object stores the pod name as the holder identity. If names changed on every restart (like in a Deployment), leader election would break.

### Why Shared PVC

Both pods mount the same PersistentVolume at `/var/jenkins_home`. This is what allows pipeline resumption — the pipeline state written by the active pod is still available when the new leader takes over.

### Why Helm

Before Helm, upgrading the image required manually running `kubectl set image` and deleting pods. With Helm, one command handles everything — it updates the StatefulSet template, Kubernetes detects the change and automatically restarts pods with the new image.

---

## Setup

### Prerequisites

- Docker Desktop with Kubernetes enabled
- Helm installed

### Build Images

```bash
docker build --build-arg IMAGE_VERSION=v1.0 -t jenkins-ha:v1.0 .
docker build --build-arg IMAGE_VERSION=v1.1 -t jenkins-ha:v1.1 .
```

### Deploy

```bash
helm install jenkins-ha ./jenkins-ha-chart -n jenkins-ha --create-namespace
```

### Create ConfigMap for Leader History

```bash
kubectl create configmap jenkins-leader-history --from-literal=lastLeader="" -n jenkins-ha
```

### Watch Pods Come Up

```bash
kubectl get pods -n jenkins-ha -w
```

Wait until both pods show `2/2 Running`.

### Get Jenkins Password

```bash
kubectl exec -n jenkins-ha jenkins-ha-0 -c jenkins -- cat /var/jenkins_home/secrets/initialAdminPassword
```

Open browser at `http://localhost:32000`

---

## Usage

### Upgrade Image Version

```bash
helm upgrade jenkins-ha ./jenkins-ha-chart --set image.tag=v1.1
```

Kubernetes automatically restarts both pods with the new image. No manual steps needed.

### Rollback to Previous Version

```bash
helm rollback jenkins-ha 1
```

### View Upgrade History

```bash
helm history jenkins-ha
```

### Check Current Leader

```bash
kubectl get lease jenkins-leader -n jenkins-ha -o jsonpath='{.spec.holderIdentity}'
```

### Live Monitoring

```powershell
.\monitor.ps1
```

Shows current leader, image version, pod status and Jenkins UI availability — refreshes every 3 seconds.

### View Leader Election Logs

```bash
kubectl logs jenkins-ha-0 -n jenkins-ha -c leader-election --tail=10
kubectl logs jenkins-ha-1 -n jenkins-ha -c leader-election --tail=10
```

---

## Key Design Decisions

**Removed readinessProbe** — the standby pod by design never starts Jenkins, so it would always fail the readiness check. This was causing a deadlock during rolling updates where Kubernetes waited forever for standby to become ready. Since the standby being in a waiting loop is correct behaviour, the probe was giving false signals.

**Parallel pod management** — switched from OrderedReady to Parallel so both pods update simultaneously without waiting for each other's readiness. This fixed the rolling update deadlock.

**ConfigMap for leader history** — when both pods restart on upgrade, the pod that was standby last time gets a shorter startup delay and wins the election first. This ensures leadership alternates on every upgrade.

**preStop lifecycle hook** — before a pod terminates, it clears the Lease so the other pod can claim leadership immediately without waiting for the 30 second expiry.

---

## Plugins Installed

| Plugin | Purpose |
|---|---|
| workflow-aggregator | Enables Pipeline syntax and stores pipeline execution state |
| git | Source code checkout |
| docker-workflow | Docker support in pipelines |
| blueocean | Better pipeline UI |
| timestamper | Adds timestamps to console output |

---

## Common Commands

```bash
# See all pods
kubectl get pods -n jenkins-ha

# Delete a pod to test failover
kubectl delete pod jenkins-ha-0 -n jenkins-ha

# See current image version
kubectl describe statefulset jenkins-ha -n jenkins-ha | findstr Image

# See ConfigMap (last leader)
kubectl get configmap jenkins-leader-history -n jenkins-ha -o jsonpath='{.data.lastLeader}'

# Recreate ConfigMap if missing after restart
kubectl create configmap jenkins-leader-history --from-literal=lastLeader="" -n jenkins-ha
```