resource "aws_iam_role" "agentcore_memory" {
  name = "${var.project_name}-agentcore-memory"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "agentcore_memory" {
  role       = aws_iam_role.agentcore_memory.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockAgentCoreMemoryBedrockModelInferenceExecutionRolePolicy"
}

resource "aws_iam_role_policy" "memory_permissions" {
  role = aws_iam_role.agentcore_memory.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]

        Resource = "*"
      }
    ]
  })
}

locals {
  project_name_underscored = replace(var.project_name, "-", "_")
}

resource "aws_bedrockagentcore_memory" "customer_support" {
  name                  = "${local.project_name_underscored}_customer_support"
  description           = "Customer support agent memory"
  event_expiry_duration = 7
}

# Wait for memory to leave UPDATING state before attaching strategies.
# Without this, parallel strategy creates race and fail with ValidationException.
resource "time_sleep" "wait_for_memory" {
  depends_on      = [aws_bedrockagentcore_memory.customer_support]
  create_duration = "30s"
}

resource "aws_bedrockagentcore_memory_strategy" "preferences" {
  name        = "CustomerSupportPreferences"
  description = "Captures customer preferences and behavior"
  memory_id   = aws_bedrockagentcore_memory.customer_support.id
  type        = "USER_PREFERENCE"
  namespaces  = ["support/customer/{actorId}/preferences/"]
  depends_on  = [time_sleep.wait_for_memory]
}

resource "aws_bedrockagentcore_memory_strategy" "semantic" {
  name        = "CustomerSupportSemantic"
  description = "Stores facts from customer support conversations"
  memory_id   = aws_bedrockagentcore_memory.customer_support.id
  type        = "SEMANTIC"
  namespaces  = ["support/customer/{actorId}/semantic/"]
  depends_on  = [time_sleep.wait_for_memory]
}

resource "local_file" "memory_id" {
  content  = aws_bedrockagentcore_memory.customer_support.id
  filename = "${path.root}/../tmp/memory_id.txt"
}

output "memory_id" {
  value = aws_bedrockagentcore_memory.customer_support.id
}
