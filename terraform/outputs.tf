# EKS outputs skipped for LocalStack (EKS is a Pro feature)
# output "cluster_name"      { value = module.eks.cluster_name }
# output "cluster_endpoint"  { value = module.eks.cluster_endpoint }
# output "kubeconfig_command" { ... }

# RDS + ECR outputs skipped for LocalStack (Pro features)
# output "rds_endpoint"            { value = module.rds.db_instance_endpoint }
# output "database_url_secret_arn" { value = aws_secretsmanager_secret.db_url.arn }
# output "ecr_server_repo_url"     { value = aws_ecr_repository.server.repository_url }
