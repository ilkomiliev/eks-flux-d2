terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.70.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "= 3.6.3"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "= 4.4.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "= 3.4.0"
    }
  }

  encryption {
    key_provider "aws_kms" "state" {
      kms_key_id = "arn:aws:kms:us-east-1:264930181295:key/c711ba5f-e979-4fcc-b954-bcb1375e5bdf"
      region     = "us-east-1"
      key_spec   = "AES_256"
    }

    method "aes_gcm" "state" {
      keys = key_provider.aws_kms.state
    }

    state {
      method   = method.aes_gcm.state
      enforced = true
    }

    plan {
      method   = method.aes_gcm.state
      enforced = true
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "first-tofu-eks"
      ManagedBy = "OpenTofu"
    }
  }
}

provider "http" {}
provider "tls" {}

data "aws_eks_cluster" "main" {
  name = local.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--region", local.region, "--cluster-name", local.cluster_name]
  }
}

data "http" "workstation_ip" {
  url = "https://checkip.amazonaws.com"
}

data "aws_availability_zones" "available" {
  state = "available"

  exclude_zone_ids = ["use1-az3"]
}

locals {
  cluster_name = "first-tofu-eks"
  region       = "us-east-1"
  azs          = ["us-east-1a", "us-east-1b"]
  client_cidr  = "${chomp(data.http.workstation_ip.response_body)}/32"
}