# ── Scan Jobs Table ───────────────────────────────────────────────────────────
resource "aws_dynamodb_table" "scan_jobs" {
  name         = "compliance-scan-jobs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "job_id"

  attribute {
    name = "job_id"
    type = "S"
  }
  attribute {
    name = "status"
    type = "S"
  }
  attribute {
    name = "created_at"
    type = "S"
  }

  global_secondary_index {
    name            = "status-index"
    hash_key        = "status"
    range_key       = "created_at"
    projection_type = "ALL"
  }

  # Point-in-time recovery for DR
  point_in_time_recovery {
    enabled = true
  }

  # Encryption at rest using KMS
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  # Enable DynamoDB Streams for cross-region replication
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    table = "scan-jobs"
  }
}

# ── Scan Results Table ────────────────────────────────────────────────────────
resource "aws_dynamodb_table" "scan_results" {
  name         = "compliance-scan-results"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "job_id"
  range_key    = "check_id"

  attribute {
    name = "job_id"
    type = "S"
  }
  attribute {
    name = "check_id"
    type = "S"
  }
  attribute {
    name = "account_id"
    type = "S"
  }
  attribute {
    name = "status"
    type = "S"
  }

  global_secondary_index {
    name            = "account-status-index"
    hash_key        = "account_id"
    range_key       = "status"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    table = "scan-results"
  }
}

# ── KMS key for DynamoDB encryption ──────────────────────────────────────────
resource "aws_kms_key" "dynamodb" {
  description             = "KMS key for compliance-scanner DynamoDB tables"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "dynamodb" {
  name          = "alias/${var.project}-dynamodb"
  target_key_id = aws_kms_key.dynamodb.key_id
}

# ── DynamoDB Global Tables (DR — secondary region) ───────────────────────────
# Requires DynamoDB streams to be enabled (above).
resource "aws_dynamodb_table_replica" "scan_jobs_dr" {
  global_table_arn = aws_dynamodb_table.scan_jobs.arn
  region_name      = var.dr_secondary_region

  depends_on = [aws_dynamodb_table.scan_jobs]
}

resource "aws_dynamodb_table_replica" "scan_results_dr" {
  global_table_arn = aws_dynamodb_table.scan_results.arn
  region_name      = var.dr_secondary_region

  depends_on = [aws_dynamodb_table.scan_results]
}
