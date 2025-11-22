#!/bin/bash
set -e

read -p "Enter BUCKET_NAME (From Lab Instructions): " BUCKET_NAME
read -p "Enter VPC_NAME (From Lab Instructions): " VPC_NAME
read -p "Enter INSTANCE_3_NAME (From Lab Instructions): " INSTANCE_3_NAME

export PROJECT_ID=$(gcloud config get-value project)
export ZONE=$(gcloud compute instances describe tf-instance-1 --format="value(zone)" | awk -F/ '{print $NF}')
export REGION=${ZONE%-*}
export INSTANCE_ID_1=$(gcloud compute instances describe tf-instance-1 --zone=$ZONE --format="value(id)")
export INSTANCE_ID_2=$(gcloud compute instances describe tf-instance-2 --zone=$ZONE --format="value(id)")

# --------------------
# ----- TASK 1&2 -----
# --------------------
cd modules/instances
cat > instances.tf <<EOF
resource "google_compute_instance" "tf-instance-1" {
  name         = "tf-instance-1"
  machine_type = "n1-standard-1"
  zone         = "$ZONE"
  allow_stopping_for_update = true
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }
  network_interface {
    network = "default"
  }
}

resource "google_compute_instance" "tf-instance-2" {
  name         = "tf-instance-2"
  machine_type = "n1-standard-1"
  zone         = "$ZONE"
  allow_stopping_for_update = true
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }
  network_interface {
    network = "default"
  }
}
EOF
cd ../..

cat > main.tf <<EOF
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "4.53.0"
    }
  }
}
provider "google" {
  project     = "$PROJECT_ID"
  region      = "$REGION"
  zone        = "$ZONE"
}
module "instances" {
  source      = "./modules/instances"
}
EOF

terraform init
terraform import module.instances.google_compute_instance.tf-instance-1 $INSTANCE_ID_1
terraform import module.instances.google_compute_instance.tf-instance-2 $INSTANCE_ID_2
terraform apply -auto-approve

# ------------------
# ----- TASK 3 -----
# ------------------
cd modules/storage
cat > storage.tf <<EOF
resource "google_storage_bucket" "storage-bucket" {
  name          = "$BUCKET_NAME"
  location      = "US"
  force_destroy = true
  uniform_bucket_level_access = true
}
EOF
cd ../..

cat >> main.tf <<EOF
module "storage" {
  source      = "./modules/storage"
}
EOF

terraform init
terraform apply -auto-approve

cat > main.tf <<EOF
terraform {
  backend "gcs" {
    bucket  = "$BUCKET_NAME"
    prefix  = "terraform/state"
  }
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "4.53.0"
    }
  }
}
provider "google" {
  project     = "$PROJECT_ID"
  region      = "$REGION"
  zone        = "$ZONE"
}
module "instances" {
  source      = "./modules/instances"
}
module "storage" {
  source      = "./modules/storage"
}
EOF

echo "yes" | terraform init -migrate-state

# ------------------
# ----- TASK 4 -----
# ------------------
cd modules/instances
cat > instances.tf <<EOF
resource "google_compute_instance" "tf-instance-1" {
  name         = "tf-instance-1"
  machine_type = "e2-standard-2"
  zone         = "$ZONE"
  allow_stopping_for_update = true
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }
  network_interface {
    network = "default"
  }
}

resource "google_compute_instance" "tf-instance-2" {
  name         = "tf-instance-2"
  machine_type = "e2-standard-2"
  zone         = "$ZONE"
  allow_stopping_for_update = true
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }
  network_interface {
    network = "default"
  }
}

resource "google_compute_instance" "$INSTANCE_3_NAME" {
  name         = "$INSTANCE_3_NAME"
  machine_type = "e2-standard-2"
  zone         = "$ZONE"
  allow_stopping_for_update = true
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }
  network_interface {
    network = "default"
  }
}
EOF
cd ../..

terraform apply -auto-approve

echo ""
echo "****************************************************************"
echo "Task 4 Complete! The 3rd instance ($INSTANCE_3_NAME) is created."
echo "SCRIPT IS PAUSED FOR 60 SECONDS."
echo ">> CLICK 'CHECK MY PROGRESS' FOR TASK 4 NOW! <<"
echo "****************************************************************"
echo ""
sleep 60

# ------------------
# ----- TASK 5 -----
# ------------------
cd modules/instances
cat > instances.tf <<EOF
resource "google_compute_instance" "tf-instance-1" {
  name         = "tf-instance-1"
  machine_type = "e2-standard-2"
  zone         = "$ZONE"
  allow_stopping_for_update = true
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }
  network_interface {
    network = "default"
  }
}

resource "google_compute_instance" "tf-instance-2" {
  name         = "tf-instance-2"
  machine_type = "e2-standard-2"
  zone         = "$ZONE"
  allow_stopping_for_update = true
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }
  network_interface {
    network = "default"
  }
}
EOF
cd ../..

terraform apply -auto-approve

echo ""
echo "****************************************************************"
echo "Task 5 Complete! The 3rd instance has been destroyed."
echo "SCRIPT IS PAUSED FOR 60 SECONDS."
echo ">> CLICK 'CHECK MY PROGRESS' FOR TASK 5 NOW! <<"
echo "****************************************************************"
echo ""
sleep 60

# ------------------
# ----- TASK 6 -----
# ------------------
cat > main.tf <<EOF
terraform {
  backend "gcs" {
    bucket  = "$BUCKET_NAME"
    prefix  = "terraform/state"
  }
  required_providers {
    google = {
      source = "hashicorp/google"
      version = ">= 4.53.0"
    }
  }
}
provider "google" {
  project     = "$PROJECT_ID"
  region      = "$REGION"
  zone        = "$ZONE"
}
module "instances" {
  source      = "./modules/instances"
}
module "storage" {
  source      = "./modules/storage"
}
module "vpc" {
    source  = "terraform-google-modules/network/google"
    version = "~> 10.0.0"

    project_id   = "$PROJECT_ID"
    network_name = "$VPC_NAME"
    routing_mode = "GLOBAL"

    subnets = [
        {
            subnet_name           = "subnet-01"
            subnet_ip             = "10.10.10.0/24"
            subnet_region         = "$REGION"
        },
        {
            subnet_name           = "subnet-02"
            subnet_ip             = "10.10.20.0/24"
            subnet_region         = "$REGION"
        },
    ]
}

resource "google_compute_firewall" "tf-firewall" {
  name    = "tf-firewall"
  network = module.vpc.network_self_link

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
}
EOF

cd modules/instances
cat > instances.tf <<EOF
resource "google_compute_instance" "tf-instance-1" {
  name         = "tf-instance-1"
  machine_type = "e2-standard-2"
  zone         = "$ZONE"
  allow_stopping_for_update = true
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }
  network_interface {
    network    = "$VPC_NAME"
    subnetwork = "subnet-01"
  }
}

resource "google_compute_instance" "tf-instance-2" {
  name         = "tf-instance-2"
  machine_type = "e2-standard-2"
  zone         = "$ZONE"
  allow_stopping_for_update = true
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }
  network_interface {
    network    = "$VPC_NAME"
    subnetwork = "subnet-02"
  }
}
EOF
cd ../..

terraform init -upgrade
terraform apply -auto-approve
