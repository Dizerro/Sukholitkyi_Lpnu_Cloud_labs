locals {
  cluster_name = aws_ecs_cluster.main.name
  service_name = aws_ecs_service.app.name
  lb_suffix    = aws_lb.app.arn_suffix
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = var.project

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "1. Екземпляри: бажана і фактична кількість"
          region = var.region
          view   = "timeSeries"
          period = 60
          stat   = "Average"
          yAxis  = { left = { min = 0, max = 5 } }
          metrics = [
            ["ECS/ContainerInsights", "DesiredTaskCount", "ClusterName", local.cluster_name, "ServiceName", local.service_name, { label = "Desired" }],
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", local.cluster_name, "ServiceName", local.service_name, { label = "Running" }],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "2. Завантаження CPU сервісу, %"
          region = var.region
          view   = "timeSeries"
          period = 60
          stat   = "Average"
          yAxis  = { left = { min = 0, max = 100 } }
          annotations = {
            horizontal = [
              { label = "ціль масштабування", value = var.cpu_target },
              { label = "поріг сповіщення", value = 70 },
            ]
          }
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", local.cluster_name, "ServiceName", local.service_name],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "3. Запити за хвилину"
          region = var.region
          view   = "timeSeries"
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.lb_suffix],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title  = "4. Латентність p95, с"
          region = var.region
          view   = "timeSeries"
          period = 60
          stat   = "p95"
          annotations = {
            horizontal = [{ label = "0.5 с", value = 0.5 }]
          }
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.lb_suffix],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 12, height = 6
        properties = {
          title  = "5. Відповіді 5xx від застосунку"
          region = var.region
          view   = "timeSeries"
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", local.lb_suffix],
          ]
        }
      },
    ]
  })
}
