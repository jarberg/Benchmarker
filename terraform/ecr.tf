resource "aws_ecr_repository" "server" {
  name                 = "${var.project_name}/server"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_lifecycle_policy" "server" {
  repository = aws_ecr_repository.server.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1,
      description  = "Keep last 30 images",
      selection = {
        tagStatus = "any", countType = "imageCountMoreThan", countNumber = 30
      },
      action = { type = "expire" }
    }]
  })
}
