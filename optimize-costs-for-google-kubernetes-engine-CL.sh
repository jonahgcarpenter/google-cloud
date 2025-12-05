#!/bin/bash

# ------------------
# ----- TASK 1 -----
# ------------------
ZONE=Cluster_Zone
CLUSTER_NAME=Cluster_Name 

gcloud container clusters create $CLUSTER_NAME \
  --project=$DEVSHELL_PROJECT_ID \
  --zone=$ZONE \
  --machine-type=e2-standard-2 \
  --num-nodes=2 \
  --release-channel rapid

kubectl create namespace dev
kubectl create namespace prod

git clone https://github.com/GoogleCloudPlatform/microservices-demo.git && \
cd microservices-demo && \
kubectl apply -f ./release/kubernetes-manifests.yaml --namespace dev

# ------------------
# ----- TASK 2 -----
# ------------------
POOL_NAME=Pool_Name

gcloud container node-pools create $POOL_NAME \
  --cluster=$CLUSTER_NAME \
  --machine-type=custom-2-3584 \
  --num-nodes=2 \
  --zone=$ZONE

for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=default-pool -o=name); do
  kubectl cordon "$node"
done

for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=default-pool -o=name); do
  kubectl drain --force --ignore-daemonsets --delete-emptydir-data --delete-local-data --grace-period=10 "$node"
done

gcloud container node-pools delete default-pool --cluster $CLUSTER_NAME --zone $ZONE --quiet

# ------------------
# ----- TASK 3 -----
# ------------------
kubectl create poddisruptionbudget onlineboutique-frontend-pdb \
  --selector app=frontend \
  --min-available 1 \
  --namespace dev

kubectl patch deployment frontend -n dev --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "gcr.io/qwiklabs-resources/onlineboutique-frontend:v2.1"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value": "Always"}
]'

# ------------------
# ----- TASK 4 -----
# ------------------
kubectl autoscale deployment frontend --cpu-percent=50 --min=1 --max=13 --namespace dev

gcloud beta container clusters update $CLUSTER_NAME \
  --enable-autoscaling --min-nodes 1 --max-nodes 6 --zone=$ZONE
