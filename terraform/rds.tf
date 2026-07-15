resource "aws_db_subnet_group" "this" {
  name       = "${local.name}-db"
  subnet_ids = aws_subnet.private_db[*].id

  tags = merge(local.common_tags, { Name = "${local.name}-db-subnet-group" })
}

resource "aws_db_instance" "this" {
  identifier     = "${local.name}-db"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  db_name  = var.db_name
  username = var.db_username

  # AWS creates and manages a Secrets Manager secret holding the generated
  # master password — no password ever appears in state or in this repo.
  manage_master_user_password = true

  multi_az = true

  storage_type          = "gp3"
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  backup_retention_period   = var.db_backup_retention_period
  deletion_protection       = var.db_deletion_protection
  skip_final_snapshot       = var.db_skip_final_snapshot
  final_snapshot_identifier = var.db_skip_final_snapshot ? null : "${local.name}-db-final"

  tags = merge(local.common_tags, { Name = "${local.name}-db" })
}
