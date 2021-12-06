terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.43"
    }
    hcp = {
      source  = "hashicorp/hcp"
      version = "~> 0.19"
    }
  }
}

locals {
  vpc_region     = "{{ .VPCRegion }}"
  hvn_region     = "{{ .HVNRegion }}"
  cluster_id     = "{{ .ClusterID }}"
  vpc_id         = "{{ .VPCID }}"
  route_table_id = "{{ .RouteTableID }}"
  subnet1        = "{{ .Subnet1 }}"
}

provider "aws" {
  region = local.vpc_region
}

resource "hcp_hvn" "main" {
  hvn_id         = "${local.cluster_id}-hvn"
  cloud_provider = "aws"
  region         = local.hvn_region
  cidr_block     = "172.25.32.0/20"
}

module "aws_hcp_consul" {
  source  = "hashicorp/hcp-consul/aws"
  version = "0.3.0"

  hvn             = hcp_hvn.main
  vpc_id          = local.vpc_id
  subnet_ids      = [local.subnet1]
  route_table_ids = [local.route_table_id]
}

resource "hcp_consul_cluster" "main" {
  cluster_id      = local.cluster_id
  hvn_id          = hcp_hvn.main.hvn_id
  public_endpoint = true
  tier            = "development"
}

resource "hcp_consul_cluster_root_token" "token" {
  cluster_id = hcp_consul_cluster.main.id
}

module "aws_ec2_consul_client" {
  source  = "hashicorp/hcp-consul/aws//modules/hcp-ec2-client"
  version = "0.3.0"

  subnet_id                = local.subnet1
  security_group_id        = module.aws_hcp_consul.security_group_id
  allowed_ssh_cidr_blocks  = ["0.0.0.0/0"]
  allowed_http_cidr_blocks = ["0.0.0.0/0"]
  client_config_file       = hcp_consul_cluster.main.consul_config_file
  client_ca_file           = hcp_consul_cluster.main.consul_ca_file
  root_token               = hcp_consul_cluster_root_token.token.secret_id
}

output "consul_root_token" {
  value     = hcp_consul_cluster_root_token.token.secret_id
  sensitive = true
}

output "consul_url" {
  value = hcp_consul_cluster.main.consul_public_endpoint_url
}

output "nomad_ec2_id" {
  value = module.aws_ec2_consul_client.host_id
}

output "hashicups_url" {
  value = "http://${module.aws_ec2_consul_client.host_dns}:8080"
}