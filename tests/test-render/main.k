import models.ai.com.ops.hops.v1alpha1 as stacksv1alpha1
import models.io.upbound.dev.meta.v1alpha1 as metav1alpha1

# ==============================================================================
# Unit tests for VolumeSnapshotStack XRD
#
# Philosophy: test YOUR API, not the provider's API.
# - render/validate already checks provider schema correctness
# - Tests should verify XRD spec fields produce expected behavior
# ==============================================================================

_items = [
    # ==========================================================================
    # Test 1: minimal claim renders the snapshot-controller Helm release.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "minimal-renders-snapshot-controller"
        spec = {
            compositionPath = "apis/volumesnapshotstacks/composition.yaml"
            xrdPath = "apis/volumesnapshotstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.VolumeSnapshotStack {
                metadata.name = "test-snap"
                spec.clusterName = "my-cluster"
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "snapshot-controller"
                    spec.forProvider = {
                        chart = {
                            name = "snapshot-controller"
                            repository = "https://piraeus.io/helm-charts"
                            # renovate: datasource=helm depName=snapshot-controller registryUrl=https://piraeus.io/helm-charts
                            version = "5.2.0"
                        }
                        namespace = "kube-system"
                        values = {
                            controller.resources.requests = {cpu = "15m", memory = "100Mi"}
                            webhook.resources.requests = {cpu = "15m", memory = "100Mi"}
                        }
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 2: custom labels merge with the stack's defaults.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "custom-labels-merged-with-defaults"
        spec = {
            compositionPath = "apis/volumesnapshotstacks/composition.yaml"
            xrdPath = "apis/volumesnapshotstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.VolumeSnapshotStack {
                metadata.name = "labeled-snap"
                spec = {
                    clusterName = "my-cluster"
                    labels = {team = "platform", environment = "staging"}
                }
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata = {
                        name = "snapshot-controller"
                        labels = {
                            "hops.ops.com.ai/managed" = "true"
                            "hops.ops.com.ai/volume-snapshot" = "labeled-snap"
                            team = "platform"
                            environment = "staging"
                        }
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 3: ha.enabled=true sets controller.replicaCount on the chart values.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "ha-enabled-injects-replica-count"
        spec = {
            compositionPath = "apis/volumesnapshotstacks/composition.yaml"
            xrdPath = "apis/volumesnapshotstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.VolumeSnapshotStack {
                metadata.name = "ha-on"
                spec = {
                    clusterName = "prod"
                    ha = {enabled = True, replicas = 3}
                }
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "snapshot-controller"
                    spec.forProvider.values.controller.replicaCount = 3
                }
            ]
        }
    }

    # ==========================================================================
    # Test 4: spec.controller.overrideAllValues replaces all defaults.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "controller-override-all-values-replaces-defaults"
        spec = {
            compositionPath = "apis/volumesnapshotstacks/composition.yaml"
            xrdPath = "apis/volumesnapshotstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.VolumeSnapshotStack {
                metadata.name = "override-test"
                spec = {
                    clusterName = "my-cluster"
                    controller = {
                        overrideAllValues = {
                            controller = {replicaCount = 5}
                            crds = {install = False}
                        }
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "snapshot-controller"
                    spec.forProvider.values = {
                        controller = {replicaCount = 5}
                        crds = {install = False}
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 5: custom namespace propagates to the Helm release.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "custom-namespace-propagates"
        spec = {
            compositionPath = "apis/volumesnapshotstacks/composition.yaml"
            xrdPath = "apis/volumesnapshotstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.VolumeSnapshotStack {
                metadata.name = "ns-test"
                spec = {
                    clusterName = "my-cluster"
                    namespace = "snapshot-system"
                }
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "snapshot-controller"
                    spec.forProvider.namespace = "snapshot-system"
                }
            ]
        }
    }

    # ==========================================================================
    # Test 6: helmProviderConfigRef defaults to clusterName.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "helm-provider-config-defaults-to-cluster-name"
        spec = {
            compositionPath = "apis/volumesnapshotstacks/composition.yaml"
            xrdPath = "apis/volumesnapshotstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.VolumeSnapshotStack {
                metadata.name = "provider-test"
                spec.clusterName = "prod-cluster"
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "snapshot-controller"
                    spec.providerConfigRef = {
                        name = "prod-cluster"
                        kind = "ProviderConfig"
                    }
                }
            ]
        }
    }
]

items = _items
