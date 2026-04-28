# volume-snapshot-stack — Design Spec

## Problem

EKS Auto Mode ships the `snapshot.storage.k8s.io` CRDs and includes per-CSI-driver `csi-snapshotter` sidecars (inside AWS-managed control-plane components for `ebs.csi.eks.amazonaws.com`), but does **not** install the cluster-wide `snapshot-controller` Deployment.

Without snapshot-controller, the chain is broken:

```
[user] → VolumeSnapshot          ✓ accepted by API
   ↓
[snapshot-controller]              ✗ MISSING — orchestrator absent
   ↓
[csi-snapshotter sidecar]          ✓ in AWS-managed driver, but starves
   ↓
[EBS CreateSnapshot API]
```

VolumeSnapshot resources sit forever with no `.status`. PVC restore via `dataSource: VolumeSnapshot` fails. Any consumer (PSQLBranch, Velero CSI plugin, future stacks) breaks.

## Scope

This stack does **one thing**: install the cluster-wide snapshot-controller Deployment + its CRDs. Driver-agnostic.

Out of scope (intentionally):
- Default `VolumeSnapshotClass` resources — those belong to whichever workload stack composes them (e.g., psql-stack composes `psql` VSC for `ebs.csi.eks.amazonaws.com`).
- AWS-specific config — the controller has none. EBS-specific knobs (encryption, tags, KMS keys) live as `VolumeSnapshotClass.parameters` in workload stacks.
- Per-driver `csi-snapshotter` sidecars — these are part of each CSI driver's own install (EKS Auto Mode includes them for EBS).
- Volume cloning — that's a separate CSI feature using `dataSource: PersistentVolumeClaim`, not snapshots.

## Non-decisions (explicit)

- **Stack name `volume-snapshot-stack`**, not `k8s-snapshot-stack` or `csi-snapshot-stack` — disambiguates from etcd snapshots / Velero workload snapshots / config snapshots. Direct mapping to the API group `snapshot.storage.k8s.io` and the user-facing `VolumeSnapshot` kind.
- **Helm chart, not raw Crossplane Objects** — chart version bumps are one-field changes, well-handled by Renovate; raw inlined manifests would require manual YAML resync on every upstream release. We use raw Objects for the s2z plugin (small, near-static); snapshot-controller's surface and release cadence make Helm the better fit.

## Helm chart selection

Three real candidates evaluated:

| Chart | Source | Verdict |
|---|---|---|
| **piraeus-charts/snapshot-controller** | https://piraeus.io/helm-charts (LINBIT) | **Selected.** Chart 5.0.3 (Feb 2025) tracks upstream v8.5.0 (released 5 days earlier). 5+ year track record, used by Talos / OpenEBS / KubeBlocks docs. Maintained by LINBIT (LINSTOR maintainers), business motive to keep current. Bundles snapshot validation webhook. |
| stevehipwell/helm-charts/snapshot-controller | github.com/stevehipwell/helm-charts | Brand new (chart 0.1.0), tracks older upstream (v8.2.0), single maintainer. Pass for now; reconsider if maturity grows. |
| democratic-csi/snapshot-controller | github.com/democratic-csi/charts | Embedded in democratic-csi project; less independent. |

**No "official" chart** exists from `kubernetes-csi/external-snapshotter`. They publish raw YAML and explicitly reject shipping a chart (see [issue #812](https://github.com/kubernetes-csi/external-snapshotter/issues/812)) — "install via your config-management tool of choice."

## Update story

- Renovate datasource: `helm:piraeus-charts` watches `controller.chartVersion`
- Piraeus releases tracked upstream snapshot-controller within days historically
- Bumping our default version is one field change; existing claims with explicit `chartVersion` pin themselves

## Multi-chart CRD ownership

This stack is the canonical CRD installer for the cluster. Helm chart ownership conflicts arise if multiple charts ship the same CRDs. Mitigation:

- Mayastor: `crds.csi.volumeSnapshots.enabled: false` (already set in our prior psql-stack work for Mayastor)
- Longhorn: `csi.snapshotterCustomResourceDefinitions: false` (chart-version-dependent)
- Other CSI driver charts: similar opt-out toggle

Documented in [README.md](./README.md) under "Multi-chart CRD ownership."

## Composed resources

```
1× Helm Release (snapshot-controller, piraeus-charts)
```

That's the entire composition. Smallest stack in the repo.

## Schema design

```yaml
spec:
  clusterName: <required>          # default for helmProviderConfigRef.name + labels
  namespace: kube-system            # where the controller runs
  labels: {}                        # merged with stack defaults
  managementPolicies: ["*"]
  helmProviderConfigRef: {...}      # defaults to clusterName

  ha:
    enabled: false                  # default off; flip true for prod
    replicas: 2                     # leader-elected, upstream HA default
    topologySpreadByZone: true

  controller:
    name: snapshot-controller       # Helm release name
    chartVersion: "5.0.3"           # piraeus chart version
    values: {}                      # merge with stack defaults
    overrideAllValues: {}           # full replacement escape hatch
```

No `kubernetesProviderConfigRef` — we compose only Helm Releases, not Objects. No `crds.enabled` — the chart bundles CRDs; if the user doesn't want them, `controller.overrideAllValues.crds.install: false` is the escape hatch.

## Lifecycle / deletion

The stack is leaf-level — nothing depends on it via Crossplane Usage. Other stacks (psql-stack, future longhorn-stack) document it as a prerequisite but don't enforce via Crossplane (cross-stack `Usage` would fight readability).

If the controller is removed:
- Existing VolumeSnapshot resources stop progressing but aren't error
- No data loss (snapshots already in EBS persist)
- New VolumeSnapshot requests sit unprocessed

This is an acceptable failure mode. The controller is restartable / re-installable safely (it has no persistent state of its own — state lives in K8s API and EBS).

## What it does NOT do

| Concern | Why not | Where it lives |
|---|---|---|
| Default VolumeSnapshotClass for EBS | Driver-specific, opinionated | Each workload stack composes its own VSC (e.g. psql-stack's `psql` VSC) |
| AWS IAM / PodIdentity | snapshot-controller doesn't talk to AWS | N/A |
| Backup retention / lifecycle | Out of CSI snapshot scope | AWS DLM, Velero, or workload-specific |
| Cross-region snapshot copy | EBS feature, not CSI | AWS API directly via `provider-aws-ec2` |
| EBS encryption / KMS keys | VolumeSnapshotClass parameters | Workload stack's VSC |

## Acceptance criteria

- [ ] `make render` produces a clean Helm Release
- [ ] `make test` — KCL tests pass (~6 cases covering minimal, labels, HA, namespace, override, providerConfig)
- [ ] `hops config install` builds + pushes the package to colima
- [ ] Live install on pat-local: snapshot-controller pod reaches Ready
- [ ] Smoke test: PVC + VolumeSnapshot reaches `readyToUse=true` (same flow as the manual install we did to verify)
- [ ] psql-stack's composed `psql` VolumeSnapshotClass becomes functional (PSQLBranch unblocked downstream)
