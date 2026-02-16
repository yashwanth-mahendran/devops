resource "aws_cloudwatch_log_group" "ssm_sessions" {
  name              = "/aws/ssm/${var.project_name}"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-ssm-logs"
  }
}

resource "aws_ssm_document" "session_manager_prefs" {
  name            = "${var.project_name}-session-manager-prefs"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Document to configure session preferences"
    sessionType   = "Standard_Stream"
    inputs = {
      s3BucketName                = ""
      s3KeyPrefix                 = ""
      s3EncryptionEnabled         = true
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.ssm_sessions.name
      cloudWatchEncryptionEnabled = true
      cloudWatchStreamingEnabled  = true
      runAsEnabled                = false
      runAsDefaultUser            = ""
    }
  })

  tags = {
    Name = "${var.project_name}-ssm-prefs"
  }
}
