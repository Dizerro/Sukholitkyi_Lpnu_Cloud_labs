resource "aws_appautoscaling_target" "app" {
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  min_capacity       = var.min_tasks
  max_capacity       = var.max_tasks
}

# Target tracking: ви задаєте цільове значення метрики, AWS сам створює тривоги CloudWatch
# (на підвищення і на зниження) і рахує, скільки задач потрібно.
resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.project}-cpu-target"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.app.service_namespace
  scalable_dimension = aws_appautoscaling_target.app.scalable_dimension
  resource_id        = aws_appautoscaling_target.app.resource_id

  target_tracking_scaling_policy_configuration {
    target_value = var.cpu_target

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    # Cooldown: скільки чекати після масштабування, перш ніж робити наступне.
    # Додавати можна швидко (користувачі вже страждають), прибирати -- обережно.
    scale_out_cooldown = 60
    scale_in_cooldown  = 300
  }
}
