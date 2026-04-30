output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "kubeconfig_command" {
  description = "Run this to populate ~/.kube/config"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "rds_endpoint" {
  value     = module.rds.db_instance_endpoint
  sensitive = true
}

output "database_url_secret_arn" {
  value = aws_secretsmanager_secret.db_url.arn
}

output "ecr_server_repo_url" {
  value = aws_ecr_repository.server.repository_url
}
