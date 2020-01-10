#!/bin/bash
registry=${1:-"origin"}
image_version=${2:-":latest"}
#image_version="@sha256:xxxx"

if [[ X"$registry" == X"origin" ]]; then
    registry_url="quay.io/openshift/"
fi

if [[ X"$registry" == X"brew" ]]; then
    registry_url="registry-proxy.engineering.redhat.com/rh-osbs/openshift3-ose-"
fi

if [[ X"$registry" == X"stage" ]]; then
    registry_url="registry.stage.redhat.io/openshif4/ose-"
fi

if [[ X"$registry" == X"prod" ]]; then
    registry_url="registry.redhat.io/openshift3/ose-"
fi

echo '
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-logging
  annotations:
    openshift.io/node-selector: ""
  labels:
    openshift.io/cluster-logging: "true"
    openshift.io/cluster-monitoring: "true"' |oc create -f -

oc project openshift-logging

echo 'apiVersion: v1
kind: ServiceAccount
metadata:
  name: cluster-logging-operator' |oc create -f -

echo '---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: cluster-logging-operator
rules:
- apiGroups:
  - logging.openshift.io
  resources:
  - "*"
  verbs:
  - "*"
- apiGroups:
  - ""
  resources:
  - pods
  - services
  - endpoints
  - persistentvolumeclaims
  - events
  - configmaps
  - secrets
  - serviceaccounts
  verbs:
  - "*"
- apiGroups:
  - apps
  resources:
  - deployments
  - daemonsets
  - replicasets
  - statefulsets
  verbs:
  - "*"
- apiGroups:
  - route.openshift.io
  resources:
  - routes
  - routes/custom-host
  verbs:
  - "*"
- apiGroups:
  - batch
  resources:
  - cronjobs
  verbs:
  - "*"' |oc create -f -

echo '---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: cluster-logging-operator-priority
rules:
- apiGroups:
  - scheduling.k8s.io
  resources:
  - priorityclasses
  verbs:
  - "*" '| oc create -f -
echo '---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: cluster-logging-operator-rolebinding
subjects:
- kind: ServiceAccount
  name: cluster-logging-operator
roleRef:
  kind: Role
  name: cluster-logging-operator
  apiGroup: rbac.authorization.k8s.io'|oc create -f  -

echo '---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: cluster-logging-operator-priority-rolebinding
subjects:
- kind: ServiceAccount
  name: cluster-logging-operator
  namespace: cluster-logging
roleRef:
  kind: ClusterRole
  name: cluster-logging-operator-priority' | oc create -f -

echo 'apiGroup: rbac.authorization.k8s.io
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: clusterloggings.logging.openshift.io
spec:
  group: logging.openshift.io
  names:
    kind: ClusterLogging
    listKind: ClusterLoggingList
    plural: clusterloggings
    singular: clusterlogging
  scope: Namespaced
  version: v1alpha1'|oc create -f -

echo "apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-logging-operator
spec:
  replicas: 1
  selector:
    matchLabels:
      name: cluster-logging-operator
  template:
    metadata:
      labels:
        name: cluster-logging-operator
    spec:
      serviceAccountName: cluster-logging-operator
      containers:
      - name: cluster-logging-operator
        image: ${registry_url}cluster-logging-operator${image_version}
        imagePullPolicy: IfNotPresent
        command:
        - cluster-logging-operator
        env:
          - name: WATCH_NAMESPACE
            valueFrom:
              fieldRef:
                fieldPath: metadata.namespace
          - name: OPERATOR_NAME
            value: cluster-logging-operator " | oc create -f -
