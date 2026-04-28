# volume-snapshot-stack

Installs the upstream Kubernetes CSI [`snapshot-controller`](https://kubernetes-csi.github.io/docs/snapshot-controller.html) — the cluster-wide orchestrator that turns user-facing `VolumeSnapshot` resources into driver-facing `VolumeSnapshotContent` records. Driver-agnostic; works alongside any CSI driver whose controller plugin includes the `csi-snapshotter` sidecar (EKS Auto Mode's managed EBS CSI driver does, as do Longhorn, Mayastor, OpenEBS LocalPV, etc.).

Composes a single Helm release via the [piraeus-charts/snapshot-controller](https://artifacthub.io/packages/helm/piraeus-charts/snapshot-controller) chart, which bundles the `snapshot.storage.k8s.io` CRDs and the controller Deployment.

## Why this stack exists

EKS Auto Mode ships the CSI driver (`ebs.csi.eks.amazonaws.com`) and the snapshot CRDs, but **not the cluster-wide snapshot-controller**. Without it, `VolumeSnapshot` resources are accepted by the API server but never get processed — they sit forever with no `.status.readyToUse`.

This is a foundational cluster concern (like cert-manager). Any stack that composes a `VolumeSnapshotClass` (psql-stack, future longhorn-stack, etc.) depends on the controller being present.

## Components

| Component | Default | Purpose |
|---|---|---|
| **snapshot-controller Deployment** | always-on | Watches `VolumeSnapshot` → creates `VolumeSnapshotContent` → populates `.status` |
| **Snapshot CRDs** | bundled with the Helm chart | `VolumeSnapshot`, `VolumeSnapshotContent`, `VolumeSnapshotClass` |
| **Snapshot validation webhook** | optional via chart values | Validates VolumeSnapshot/Content schemas at admission |
| **HA mode** | off (`spec.ha.enabled: false`) | When enabled: `replicaCount: 2` (active + standby, leader-elected) + `topologySpreadConstraints` by zone |

## Prerequisites

- A target Kubernetes cluster — the controller is driver-agnostic, no CSI-driver-specific config needed.
- One or more CSI drivers with their `csi-snapshotter` sidecar installed (handled by the driver's own install — EKS Auto Mode includes it for `ebs.csi.eks.amazonaws.com`).

That's it. No IAM, no PodIdentity, no AWS-specific config.

## Multi-chart CRD ownership

This stack is the **canonical CRD installer** for the cluster. Other charts that bundle the snapshot CRDs (Mayastor, Longhorn, Ceph-CSI, OpenEBS LVM, etc.) MUST be configured to skip their own CRD shipment to avoid Helm ownership conflicts. Common toggles:

| Chart | Toggle |
|---|---|
| Mayastor (`openebs/mayastor`) | `crds.csi.volumeSnapshots.enabled: false` |
| Longhorn (`longhorn/longhorn`) | bundle is opt-out via `csi.snapshotterCustomResourceDefinitions: false` (chart-version-dependent) |
| OpenEBS LVM (`openebs/lvm-localpv`) | `csiSnapshots.crds.install: false` |
| Ceph-CSI (`ceph/ceph-csi-rbd`) | `provisioner.snapshotter.enabled` controls sidecar; CRDs are install-once |

Confirm against the specific chart version before adopting.

## Stages

### Stage 1: Default install

```yaml
apiVersion: hops.ops.com.ai/v1alpha1
kind: VolumeSnapshotStack
metadata:
  name: snapshot
  namespace: default
spec:
  clusterName: my-cluster
```

Single replica, leader election on, kube-system namespace, latest pinned chart version.

### Stage 2: HA

```yaml
apiVersion: hops.ops.com.ai/v1alpha1
kind: VolumeSnapshotStack
metadata:
  name: snapshot
  namespace: default
spec:
  clusterName: production-cluster
  labels:
    team: platform
  ha:
    enabled: true
    replicas: 2
    topologySpreadByZone: true
```

### Stage 3: Custom values escape hatch

```yaml
apiVersion: hops.ops.com.ai/v1alpha1
kind: VolumeSnapshotStack
metadata:
  name: snapshot
  namespace: default
spec:
  clusterName: edge
  controller:
    values:
      controller:
        featureGates: "CSIVolumeGroupSnapshot=true"
      webhook:
        enabled: true
        certManager:
          enabled: true
```

`controller.values` deep-merges with the stack's chart defaults; `controller.overrideAllValues` replaces them entirely.

## Spec Reference

| Field | Type | Default | Description |
|---|---|---|---|
| `clusterName` | string | _required_ | Target cluster name; default for `helmProviderConfigRef.name` and label values |
| `namespace` | string | `kube-system` | Where to install snapshot-controller |
| `labels` | object | — | Custom labels merged with stack defaults |
| `managementPolicies` | string[] | `["*"]` | Crossplane management policies |
| `helmProviderConfigRef.name` | string | `clusterName` | Helm ProviderConfig name |
| `helmProviderConfigRef.kind` | enum | `ProviderConfig` | `ProviderConfig` or `ClusterProviderConfig` |
| **HA mode** | | | |
| `ha.enabled` | bool | `false` | Enable replicas + zone-spread |
| `ha.replicas` | int | `2` | Replica count when HA enabled (matches upstream snapshot-controller default for HA) |
| `ha.topologySpreadByZone` | bool | `true` | Add `topologySpreadConstraint` by `topology.kubernetes.io/zone` |
| **Controller** | | | |
| `controller.name` | string | `snapshot-controller` | Helm release name |
| `controller.chartVersion` | string | `5.0.3` | piraeus-charts chart version (tracks upstream `v8.5.0`) |
| `controller.values` | object | — | Helm values merged with stack defaults |
| `controller.overrideAllValues` | object | — | Helm values that replace all defaults |

## Composed Resources

| Resource | Kind | When |
|---|---|---|
| `<controller.name>` | `helm.m.crossplane.io/Release` | always |

That's it. Smallest stack in the repo.

## Dependencies

| Kind | Package | Version |
|---|---|---|
| Function | `crossplane-contrib/function-auto-ready` | `>=v0.6.2` |
| Provider | `crossplane-contrib/provider-helm` | `>=v1` |

## Development

```bash
make render             # Render all examples
make validate           # Validate against Crossplane schemas
make test               # KCL render tests (assert composed resource shapes)
make build              # Build the package
make render:minimal     # Render a single example
```

## See also

- [SPEC.md](./SPEC.md) — design rationale, alternatives considered, why piraeus
- Upstream: [kubernetes-csi/external-snapshotter](https://github.com/kubernetes-csi/external-snapshotter)
- Chart: [piraeus-charts/snapshot-controller](https://artifacthub.io/packages/helm/piraeus-charts/snapshot-controller)

## License

Apache-2.0
