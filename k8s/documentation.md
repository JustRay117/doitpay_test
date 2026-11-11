# Kubernetes manifests for the PayTrack API

These manifests run the API on the EKS cluster from `infra/`. They were validated offline only. No cluster was used, as the assessment requires.

## Files

| File | Object | Purpose |
|---|---|---|
| `namespace.yaml` | Namespace `paytrack` | Keeps PayTrack's objects apart from other workloads |
| `configmap.yaml` | ConfigMap `paytrack-api-config` | Non-sensitive settings (`APP_ENV`) |
| `deployment.yaml` | Deployment `paytrack-api` | Runs three pods of the API |
| `service.yaml` | Service `paytrack-api` | Stable internal address in front of the pods |

Apply order on a real cluster: the namespace first, then the rest.

## Decisions

| Decision | Reason |
|---|---|
| Three replicas | The API stays available when one pod or one node fails |
| Rolling update with `maxSurge: 1`, `maxUnavailable: 0` | An old pod is removed only after its replacement is ready, so a broken release cannot reduce capacity |
| Readiness probe on `/ready` | A pod receives traffic only while it reports ready |
| Liveness probe on `/health` | A stuck container is restarted |
| CPU and memory requests and limits | One pod cannot starve the others on a node |
| Service type `ClusterIP` | The API is internal only, so it gets no public address |
| Fixed image tag, never `latest` | The running version is always known, and a rollback has a clear target |
| Only `APP_ENV` in the ConfigMap | It is the one setting that differs per environment. The port stays at the image default, 8080 |

## Assumptions

- The image is built from the `Dockerfile` in this repository and pushed to a private Amazon ECR repository in the same account and region. The address in `deployment.yaml` is a placeholder in ECR format. The node role from `infra/` can already pull from ECR.
- Callers are inside the cluster, or reach the Service through an internal gateway managed by the platform team. No Ingress or load balancer is created here.
- The resource requests and limits are starting values. They were not measured.
- The API has no secrets, so there is no Secret object.

## Validation without a cluster

Run from the repository root:

```bash
docker run --rm -v "$PWD/k8s:/k8s:ro" ghcr.io/yannh/kubeconform:v0.8.0 \
  -strict -summary -verbose -kubernetes-version 1.36.0 /k8s
```

`kubeconform` compares every manifest with the official Kubernetes schema for version 1.36, the version of the cluster in `infra/`. `-strict` also rejects unknown or misspelled fields.

Result: `Valid: 4, Invalid: 0, Errors: 0, Skipped: 0`.

This proves that the manifests are well formed. It does not prove that the pods start on a real cluster.

The image was also built and run locally with Docker. `/health`, `/ready` and `/` returned HTTP 200 on port 8080.

## Findings in the provided application

These were not changed, because application development is out of scope:

- The container runs as root. The `Dockerfile` does not switch to another user.
- The app starts Flask's development server with debug mode on. A production server should be used instead.

## Not included

These are recommendations, not implemented, to keep the solution small:

- A security context for the container (non-root user, read-only file system).
- A PodDisruptionBudget, so node maintenance cannot take all pods down at once.
- A NetworkPolicy that limits which workloads may call the API.
- Autoscaling.
