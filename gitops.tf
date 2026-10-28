locals {
  github_owner      = "ilkomiliev"
  github_repository = "eks-flux-d2"
  ecr_repository_names = toset([
    "first-tofu-flux-fleet",
    "first-tofu-flux-infra",
    "first-tofu-flux-apps",
    "first-tofu-superset",
  ])
}

data "aws_kms_key" "gitops_secrets" {
  key_id = "alias/first-tofu-gitops-secrets"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_ecr_repository" "gitops" {
  for_each = local.ecr_repository_names

  name                 = each.value
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = each.value
  }
}

resource "aws_iam_role" "github_actions" {
  name = "${local.cluster_name}-github-actions-ecr"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github_actions.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            "repo:${local.github_owner}/${local.github_repository}:ref:refs/heads/main",
            "repo:${local.github_owner}/${local.github_repository}:ref:refs/tags/v*",
            "repo:${local.github_owner}/${local.github_repository}:environment:prod",
          ]
        }
      }
    }]
  })
}

resource "aws_iam_policy" "github_actions_ecr" {
  name        = "${local.cluster_name}-github-actions-ecr"
  description = "Allow the GitHub Actions workflow for ${local.github_owner}/${local.github_repository} to publish pinned D2 artifacts and Superset images"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
        Resource = [for repository in aws_ecr_repository.gitops : repository.arn]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_ecr" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_ecr.arn
}

resource "aws_iam_role" "flux_source_controller" {
  name = "${local.cluster_name}-flux-source-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.cluster.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
          "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:flux-system:source-controller"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "flux_source_ecr" {
  name        = "${local.cluster_name}-flux-source-ecr"
  description = "Read the D2 OCI artifacts from ECR"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
          "ecr:GetDownloadUrlForLayer",
        ]
        Resource = [for repository in aws_ecr_repository.gitops : repository.arn]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "flux_source_ecr" {
  role       = aws_iam_role.flux_source_controller.name
  policy_arn = aws_iam_policy.flux_source_ecr.arn
}

resource "aws_iam_role" "flux_kustomize_controller" {
  name = "${local.cluster_name}-flux-kustomize-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.cluster.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
          "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:flux-system:kustomize-controller"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "flux_kms_decrypt" {
  name        = "${local.cluster_name}-flux-kms-decrypt"
  description = "Allow Flux Kustomize controller to decrypt SOPS secrets with the dedicated GitOps KMS key"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Decrypt", "kms:DescribeKey"]
      Resource = data.aws_kms_key.gitops_secrets.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "flux_kms_decrypt" {
  role       = aws_iam_role.flux_kustomize_controller.name
  policy_arn = aws_iam_policy.flux_kms_decrypt.arn
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}

output "ecr_repository_urls" {
  value = { for name, repository in aws_ecr_repository.gitops : name => repository.repository_url }
}

output "flux_source_controller_role_arn" {
  value = aws_iam_role.flux_source_controller.arn
}

output "flux_kustomize_controller_role_arn" {
  value = aws_iam_role.flux_kustomize_controller.arn
}