output "alb_dns" {
  value = aws_lb.app.dns_name
}

output "ecr_url" {
  value = aws_ecr_repository.app.repository_url
}

# output "github_role_arn" {
#   value = aws_iam_role.github.arn
# }