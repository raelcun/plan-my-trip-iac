data "google_client_config" "default" {}

provider "google" {
  credentials = file("account.json")
}

provider "google-beta" {
  credentials = file("account.json")
}

provider "kubernetes" {
  host                   = "https://${module.gke.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
}

terraform {
  backend "gcs" {
    bucket      = "plan-my-trip-terraform-state"
    prefix      = "terraform"
    credentials = "account.json"
  }
}

module "gcp-network" {
  source       = "terraform-google-modules/network/google"
  version      = "~> 3.1"
  project_id   = var.project_id
  network_name = var.network

  subnets = [
    {
      subnet_name   = var.subnetwork
      subnet_ip     = "10.0.0.0/17"
      subnet_region = var.region
    },
  ]

  secondary_ranges = {
    (var.subnetwork) = [
      {
        range_name    = "${module.gcp-network.network_name}-ip-range-pods"
        ip_cidr_range = "192.168.0.0/18"
      },
      {
        range_name    = "${module.gcp-network.network_name}-ip-range-scv"
        ip_cidr_range = "192.168.64.0/18"
      },
    ]
  }
}

module "gke" {
  source                     = "terraform-google-modules/kubernetes-engine/google"
  project_id                 = var.project_id
  name                       = var.cluster_name
  regional                     = false
  zones                      = ["us-central1-a"]
  network                    = module.gcp-network.network_name
  subnetwork                 = module.gcp-network.subnets_names[0]
  ip_range_pods              = "${module.gcp-network.network_name}-ip-range-pods"
  ip_range_services          = "${module.gcp-network.network_name}-ip-range-scv"
  http_load_balancing        = true
  horizontal_pod_autoscaling = true
  network_policy             = false
  create_service_account     = false
  release_channel            = "REGULAR"

  node_pools = [
    {
      name               = "default-node-pool"
      machine_type       = "e2-small"
      node_locations     = "us-central1-a"
      min_count          = 1
      max_count          = 5
      local_ssd_count    = 0
      disk_size_gb       = 50
      disk_type          = "pd-standard"
      image_type         = "COS"
      auto_repair        = true
      auto_upgrade       = true
      preemptible        = false
      initial_node_count = 2
      service_account    = "plan-my-trip-deployment@plan-my-trip-325720.iam.gserviceaccount.com"
    },
  ]

  node_pools_oauth_scopes = {
    all = []

    default-node-pool = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  node_pools_labels = {
    all = {}

    default-node-pool = {
      default-node-pool = true
    }
  }

  node_pools_metadata = {
    all = {}

    default-node-pool = {
      node-pool-metadata-custom-value = "my-node-pool"
    }
  }

  node_pools_taints = {
    all = []

    default-node-pool = [
      {
        key    = "default-node-pool"
        value  = true
        effect = "PREFER_NO_SCHEDULE"
      },
    ]
  }

  node_pools_tags = {
    all = []

    default-node-pool = [
      "default-node-pool",
    ]
  }
}
