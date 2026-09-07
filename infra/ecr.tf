# ---------------------------------------------------------------------------
# Container registry.
#
# The application image lives in ECR rather than GHCR: the deployment already
# authenticates to AWS in every stage, the image sits next to the workload that
# pulls it, and no GitHub package permissions are involved.
#
# ORDERING NOTE: the image is built and pushed BEFORE this root module applies
# (image_build_push runs before provision). The repository is therefore created
# by the build stage itself via `aws ecr describe-repositories || create`, and
# adopted into state here on the first apply. Declaring it in both places is
# deliberate and safe because the build stage's create is idempotent and this
# resource uses the same deterministic name — terraform adopts the existing
# repository rather than fighting it.
#
# force_delete lets `terraform destroy` remove the repository even when it
# still holds images, so teardown does not need a manual purge step.
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  name                 = var.project_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    # Complements the Clair gate in CI: this is AWS's own scan of what actually
    # landed in the registry.
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${var.project_name}-ecr"
  }
}

# Keep storage bounded: the pipeline pushes one image per commit.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Retain only the 10 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
