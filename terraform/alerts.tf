# Завдання 4. Сповіщення на пошту: тривога і повернення до норми.

resource "aws_sns_topic" "alerts" {
  name = "${var.project}-alerts"
}

# Після apply на пошту прийде лист підтвердження підписки -- без кліку на посилання листів не буде.
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project}-cpu-high"
  alarm_description   = "Середнє завантаження CPU сервісу понад 70% протягом 2 хвилин"
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  dimensions          = { ClusterName = local.cluster_name, ServiceName = local.service_name }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 70
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn] # перехід у стан ALARM -> перший лист
  ok_actions    = [aws_sns_topic.alerts.arn] # перехід у стан OK    -> другий лист
}