output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "region" {
  value = local.region
}

output "workstation_cidr" {
  value = local.client_cidr
}

output "vpc_id" {
  value = aws_vpc.eks.id
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "alb_certificate_arn" {
  value = aws_acm_certificate.alb.arn
}

output "load_balancer_controller_role_arn" {
  value = aws_iam_role.load_balancer_controller.arn
}

output "worker_instance_type" {
  value = "m6a.large"
}

output "monthly_cost_floor_usd" {
  value       = 97.0
  description = "Approximate EKS, ALB-hour, and ALB public IPv4 charges for 730 hours; excludes nodes, storage, traffic, and KMS."
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${local.region} --name ${local.cluster_name}"
}