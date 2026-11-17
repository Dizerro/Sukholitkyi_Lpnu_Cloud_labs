resource "aws_security_group" "cache" {
  count  = var.enable_cache ? 1 : 0
  name   = "${var.project}-cache"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
}

resource "aws_elasticache_subnet_group" "cache" {
  count      = var.enable_cache ? 1 : 0
  name       = var.project
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_elasticache_cluster" "cache" {
  count                = var.enable_cache ? 1 : 0
  cluster_id           = var.project
  engine               = "redis"
  engine_version       = "7.1"
  node_type            = "cache.t4g.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.cache[0].name
  security_group_ids   = [aws_security_group.cache[0].id]
}
