resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project}"
  retention_in_days = 7
}

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# execution role: те, що потрібно самій ECS (тягнути образ, писати логи, читати секрет)
resource "aws_iam_role" "execution" {
  name               = "${var.project}-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_secret" {
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [aws_secretsmanager_secret.db.arn]
    }]
  })
}

# task role: права самого застосунку (їх він не потребує, тому порожня)
resource "aws_iam_role" "task" {
  name               = "${var.project}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_ecs_cluster" "main" {
  name = var.project

  # Лаб. 2: без цього немає метрик RunningTaskCount / DesiredTaskCount для панелі
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.project
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name         = "app"
    image        = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
    essential    = true
    stopTimeout  = 30
    portMappings = [{ containerPort = 8000 }]
    environment = concat(
      [
        { name = "DB_HOST", value = aws_db_instance.db.address },
        { name = "DB_NAME", value = "notes" },
        { name = "DB_USER", value = "notes" },
      ],
      var.enable_cache ? [
        { name = "REDIS_HOST", value = aws_elasticache_cluster.cache[0].cache_nodes[0].address },
        { name = "CACHE_ENABLED", value = tostring(var.cache_enabled) },
        { name = "CACHE_TTL", value = tostring(var.cache_ttl) },
        { name = "CACHE_INVALIDATE", value = tostring(var.cache_invalidate) },
      ] : []
    )
    secrets = [
      { name = "DB_PASSWORD", valueFrom = aws_secretsmanager_secret.db.arn },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "app"
      }
    }
  }])
}

resource "aws_ecs_service" "app" {
  name                              = var.project
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.app.arn
  desired_count                     = var.min_tasks
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 60

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = 8000
  }

  depends_on = [aws_lb_listener.http]

  # Лаб. 2: desired_count тепер належить autoscaling, Terraform його не чіпає.
  # ignore_changes = [task_definition] ПРИБРАНО: CI/CD через OIDC заблокований, нові версії
  # образу та змінні середовища (Redis, кеш) розгортаються через terraform apply.
  # Коли OIDC запрацює, поверніть task_definition у цей список.
  lifecycle {
    ignore_changes = [desired_count]
  }
}