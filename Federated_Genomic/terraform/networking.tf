# =============================================================================
# Cloud-Native Multiomics Platform - Networking Configuration
# =============================================================================

# -----------------------------------------------------------------------------
# VPC Network
# -----------------------------------------------------------------------------

resource "google_compute_network" "main" {
  count = var.create_vpc ? 1 : 0

  name                    = "${var.project_id}-multiomics-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# -----------------------------------------------------------------------------
# Compute Subnet
# -----------------------------------------------------------------------------
# Primary subnet for Cloud Batch VMs

resource "google_compute_subnetwork" "compute" {
  count = var.create_vpc ? 1 : 0

  name          = "${var.project_id}-compute-subnet"
  ip_cidr_range = "10.0.0.0/20"
  region        = var.region
  network       = google_compute_network.main[0].id

  private_ip_google_access = var.enable_private_google_access

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# -----------------------------------------------------------------------------
# Cloud NAT (for private VMs to access internet)
# -----------------------------------------------------------------------------

resource "google_compute_router" "router" {
  count = var.create_vpc ? 1 : 0

  name    = "${var.project_id}-router"
  region  = var.region
  network = google_compute_network.main[0].id
}

resource "google_compute_router_nat" "nat" {
  count = var.create_vpc ? 1 : 0

  name                               = "${var.project_id}-nat"
  router                             = google_compute_router.router[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# -----------------------------------------------------------------------------
# Firewall Rules
# -----------------------------------------------------------------------------

# Allow internal communication within the VPC
resource "google_compute_firewall" "allow_internal" {
  count = var.create_vpc ? 1 : 0

  name    = "${var.project_id}-allow-internal"
  network = google_compute_network.main[0].name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.0.0/8"]
}

# Allow SSH from IAP (Identity-Aware Proxy) for secure access
resource "google_compute_firewall" "allow_iap_ssh" {
  count = var.create_vpc ? 1 : 0

  name    = "${var.project_id}-allow-iap-ssh"
  network = google_compute_network.main[0].name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"] # IAP IP range
  target_tags   = ["allow-iap-ssh"]
}

# Deny all egress except to Google APIs (for enhanced security)
# Uncomment for production environments
# resource "google_compute_firewall" "deny_egress" {
#   count = var.create_vpc && var.environment == "prod" ? 1 : 0
#
#   name      = "${var.project_id}-deny-egress"
#   network   = google_compute_network.main[0].name
#   direction = "EGRESS"
#   priority  = 65534
#
#   deny {
#     protocol = "all"
#   }
#
#   destination_ranges = ["0.0.0.0/0"]
# }
