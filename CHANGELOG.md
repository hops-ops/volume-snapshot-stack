### What's changed in v0.1.0

* feat: initial scaffold of volume-snapshot-stack (by @patrickleet)

  Installs the Kubernetes CSI snapshot-controller via the
  piraeus-charts/snapshot-controller Helm chart (chart 5.0.3 →
  upstream snapshot-controller v8.5.0). Required prerequisite for
  any stack composing a VolumeSnapshotClass — EKS Auto Mode ships
  the snapshot.storage.k8s.io CRDs but not the cluster-wide controller.

  Composition: 1 Helm Release. Smallest stack in the repo.

  Schema:
    spec.clusterName, spec.namespace (default kube-system), spec.labels,
    spec.helmProviderConfigRef, spec.ha.{enabled,replicas,topologySpreadByZone},
    spec.controller.{name,chartVersion,values,overrideAllValues}

  Verified end-to-end on pat-local:
    - Stack reconciles, snapshot-controller Deployment 1/1 Ready,
      conversion-webhook Deployment 1/1 Ready
    - Smoke test: PVC bound on EBS CSI → VolumeSnapshot via the
      composed `psql` VSC (from psql-stack) reaches readyToUse=true
      with a real EBS snapshot backing it
    - Pre-existing CRD ownership (stale openebs-lvm Helm annotations)
      required one-time annotate to take over; documented in README.

  KCL tests: 6/6 passing. Includes minimal, labels-merge, HA replica
  injection, override-all-values, namespace propagation, providerConfig
  defaults.

* chore: add CI workflows, CHANGELOG, e2e test scaffold (by @patrickleet)

  Adds the standard hops-ops Crossplane-stack CI shape:
  - .github/workflows/on-pr.yaml — validate + render + e2e + publish on PR
  - .github/workflows/on-push-main.yaml — validate + e2e + version-and-tag
    via unbounded-tech/workflow-vnext-tag (uses DEPLOY_KEY secret)
  - .github/workflows/on-version-tagged.yaml — publish to ghcr + GitHub release
  - CHANGELOG.md — keep-a-changelog format, vnext auto-bumps
  - tests/e2etest-volume-snapshot/{kcl.mod,main.k,model/} — single E2ETest
    asserting the XR reaches Ready in a kind cluster (Helm provider via
    InjectedIdentity, no cloud creds needed)

  Mirror of psql-stack's CI pattern. Pinned to:
    unbounded-tech/workflows-crossplane@v2.20.0
    unbounded-tech/workflow-vnext-tag@v1.21.0
    unbounded-tech/workflow-simple-release@v2.1.1


