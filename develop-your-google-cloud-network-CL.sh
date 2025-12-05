#!/bin/bash

# --- PRE-FLIGHT CHECK ---
echo "Starting Challenge Lab Setup..."
echo "Please ensure you have set the Zone correctly (usually us-central1-c for this lab)."
read -p "Enter ZONE (e.g., us-central1-c): " ZONE
export REGION="${ZONE%-*}"
export PROJECT_ID=$(gcloud config get-value project)

# --- TASK 1: Development VPC ---
echo "Creating Development VPC..."
gcloud compute networks create griffin-dev-vpc --subnet-mode custom
gcloud compute networks subnets create griffin-dev-wp --network=griffin-dev-vpc --region $REGION --range=192.168.16.0/20
gcloud compute networks subnets create griffin-dev-mgmt --network=griffin-dev-vpc --region $REGION --range=192.168.32.0/20

# --- TASK 2: Production VPC (FIXED: Converted to Manual) ---
echo "Creating Production VPC..."
gcloud compute networks create griffin-prod-vpc --subnet-mode custom
gcloud compute networks subnets create griffin-prod-wp --network=griffin-prod-vpc --region $REGION --range=192.168.48.0/20
gcloud compute networks subnets create griffin-prod-mgmt --network=griffin-prod-vpc --region $REGION --range=192.168.64.0/20

# --- TASK 3: Bastion Host ---
echo "Creating Bastion Host..."
gcloud compute instances create bastion \
    --network-interface=network=griffin-dev-vpc,subnet=griffin-dev-mgmt \
    --network-interface=network=griffin-prod-vpc,subnet=griffin-prod-mgmt \
    --tags=ssh \
    --zone=$ZONE

gcloud compute firewall-rules create fw-ssh-dev --source-ranges=0.0.0.0/0 --target-tags ssh --allow=tcp:22 --network=griffin-dev-vpc
gcloud compute firewall-rules create fw-ssh-prod --source-ranges=0.0.0.0/0 --target-tags ssh --allow=tcp:22 --network=griffin-prod-vpc

# --- TASK 4: Cloud SQL ---
echo "Creating Cloud SQL Instance (This takes a few minutes)..."
gcloud sql instances create griffin-dev-db \
    --database-version=MYSQL_5_7 \
    --tier=db-f1-micro \
    --region=$REGION \
    --root-password='quicklab'

echo "Configuring SQL Databases and Users..."
gcloud sql databases create wordpress --instance=griffin-dev-db
gcloud sql users create wp_user --instance=griffin-dev-db --host=% --password=stormwind_rules

# --- TASK 5: Kubernetes Cluster ---
echo "Creating GKE Cluster..."
gcloud container clusters create griffin-dev \
  --network griffin-dev-vpc \
  --subnetwork griffin-dev-wp \
  --machine-type e2-standard-4 \
  --num-nodes 2  \
  --zone $ZONE

gcloud container clusters get-credentials griffin-dev --zone $ZONE

# --- TASK 6: Prepare K8s (FIXED: Bucket URL) ---
echo "Preparing K8s Assets..."
cd ~/
gsutil cp -r gs://spls/gsp321/wp-k8s .

cat > wp-k8s/wp-env.yaml <<EOF_END
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: wordpress-volumeclaim
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 200Gi
---
apiVersion: v1
kind: Secret
metadata:
  name: database
type: Opaque
stringData:
  username: wp_user
  password: stormwind_rules
EOF_END

cd wp-k8s
kubectl apply -f wp-env.yaml

gcloud iam service-accounts keys create key.json \
    --iam-account=cloud-sql-proxy@$PROJECT_ID.iam.gserviceaccount.com
kubectl create secret generic cloudsql-instance-credentials \
    --from-file key.json

# --- TASK 7: WordPress Deployment ---
echo "Deploying WordPress..."
INSTANCE_CONNECTION_NAME=$(gcloud sql instances describe griffin-dev-db --format='value(connectionName)')

sed -i "s/YOUR_SQL_INSTANCE/$INSTANCE_CONNECTION_NAME/g" wp-deployment.yaml

kubectl apply -f wp-deployment.yaml
kubectl apply -f wp-service.yaml

# --- TASK 9: Engineer Access (Moved up to run while Load Balancer provisions) ---
gcloud projects get-iam-policy $PROJECT_ID --format="json" \
  | jq -r '.bindings[] | select(.role=="roles/viewer").members[]' \
  | grep "user:" \
  | xargs -I {} gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="{}" \
    --role="roles/editor"

# --- TASK 8: Monitoring (Wait for IP) ---
echo "Waiting for External IP to provision Uptime Check..."

get_external_ip() {
    kubectl get service wordpress -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
}

for _ in {1..20}; do
    EXTERNAL_IP=$(get_external_ip)
    if [ -n "$EXTERNAL_IP" ]; then
        echo "External IP found: $EXTERNAL_IP"
        gcloud monitoring uptime create "wordpress-uptime" \
            --resource-type=uptime-url \
            --resource-labels=host=$EXTERNAL_IP
        break
    fi
    echo "Waiting for Load Balancer IP..."
    sleep 10
done

echo "Script Complete. Verify tasks in the Lab Interface."
