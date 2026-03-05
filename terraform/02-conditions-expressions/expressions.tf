# ============================================
# TERRAFORM EXPRESSIONS - Complete Guide
# ============================================
# For expressions, splat operators, string templates

# ============================================
# 1. FOR EXPRESSIONS
# ============================================

variable "users" {
  type = list(string)
  default = ["alice", "bob", "charlie", "david"]
}

variable "servers" {
  type = map(object({
    instance_type = string
    az            = string
  }))
  default = {
    web1 = { instance_type = "t3.micro", az = "us-east-1a" }
    web2 = { instance_type = "t3.small", az = "us-east-1b" }
    api1 = { instance_type = "t3.medium", az = "us-east-1a" }
  }
}

locals {
  # ==========================================
  # FOR with LISTS
  # ==========================================
  
  # Transform each element
  uppercase_users = [for user in var.users : upper(user)]
  # Result: ["ALICE", "BOB", "CHARLIE", "DAVID"]

  # With index
  indexed_users = [for i, user in var.users : "${i}: ${user}"]
  # Result: ["0: alice", "1: bob", "2: charlie", "3: david"]

  # Filter with if
  filtered_users = [for user in var.users : user if length(user) > 4]
  # Result: ["alice", "charlie", "david"]

  # Transform and filter
  filtered_upper = [for user in var.users : upper(user) if startswith(user, "a") || startswith(user, "c")]
  # Result: ["ALICE", "CHARLIE"]

  # ==========================================
  # FOR with MAPS
  # ==========================================
  
  # List from map values
  server_types = [for name, server in var.servers : server.instance_type]
  # Result: ["t3.micro", "t3.small", "t3.medium"]

  # List from map keys
  server_names = [for name, _ in var.servers : name]
  # Result: ["api1", "web1", "web2"]

  # Map from map (transform)
  server_azs = { for name, server in var.servers : name => server.az }
  # Result: { api1 = "us-east-1a", web1 = "us-east-1a", web2 = "us-east-1b" }

  # Swap key-value
  az_to_servers = { for name, server in var.servers : server.az => name... }
  # Result: { "us-east-1a" = ["api1", "web1"], "us-east-1b" = ["web2"] }

  # Filter map
  micro_servers = { for name, server in var.servers : name => server if server.instance_type == "t3.micro" }
  # Result: { web1 = { instance_type = "t3.micro", az = "us-east-1a" } }

  # ==========================================
  # List to Map conversion
  # ==========================================
  users_map = { for user in var.users : user => {
    name  = user
    email = "${user}@example.com"
    role  = "user"
  }}

  # ==========================================
  # Nested FOR expressions
  # ==========================================
  environments = ["dev", "stg", "prod"]
  services     = ["web", "api", "worker"]
  
  # Flatten nested structure
  all_combinations = flatten([
    for env in local.environments : [
      for svc in local.services : {
        name = "${env}-${svc}"
        env  = env
        svc  = svc
      }
    ]
  ])
  # Creates list of 9 objects (3 envs × 3 services)
}

# ============================================
# 2. SPLAT EXPRESSIONS
# ============================================

variable "instances" {
  type = list(object({
    id   = string
    name = string
    ip   = string
  }))
  default = [
    { id = "i-001", name = "web-1", ip = "10.0.1.10" },
    { id = "i-002", name = "web-2", ip = "10.0.1.11" },
    { id = "i-003", name = "api-1", ip = "10.0.2.10" }
  ]
}

locals {
  # List splat - get all IPs
  all_ips = var.instances[*].ip
  # Result: ["10.0.1.10", "10.0.1.11", "10.0.2.10"]

  # Get all names
  all_names = var.instances[*].name
  # Result: ["web-1", "web-2", "api-1"]

  # Equivalent for expression
  all_ips_for = [for instance in var.instances : instance.ip]
}

# ============================================
# 3. STRING TEMPLATES & FUNCTIONS
# ============================================

variable "project" {
  default = "myproject"
}

variable "items" {
  type    = list(string)
  default = ["item1", "item2", "item3"]
}

locals {
  # Basic interpolation
  bucket_name = "${var.project}-${var.environment}-bucket"

  # Heredoc string
  policy_document = <<-EOT
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": "s3:*",
          "Resource": "arn:aws:s3:::${var.project}-*"
        }
      ]
    }
  EOT

  # Indented heredoc (<<- strips leading whitespace)
  user_data = <<-EOF
    #!/bin/bash
    echo "Hello from ${var.environment}"
    yum update -y
    yum install -y docker
    systemctl start docker
  EOF

  # Template with directive
  items_template = <<-EOT
    Items:
    %{ for item in var.items ~}
    - ${item}
    %{ endfor ~}
  EOT

  # Conditional in template
  conditional_template = <<-EOT
    Environment: ${var.environment}
    %{ if var.environment == "prod" ~}
    WARNING: This is production!
    %{ else ~}
    This is a non-production environment.
    %{ endif ~}
  EOT

  # String functions
  upper_project    = upper(var.project)           # MYPROJECT
  lower_project    = lower("MYPROJECT")           # myproject
  title_project    = title("my project")          # My Project
  trimmed          = trimspace("  hello  ")       # "hello"
  replaced         = replace("hello-world", "-", "_")  # "hello_world"
  substr_example   = substr("hello world", 0, 5)  # "hello"
  split_example    = split(",", "a,b,c")          # ["a", "b", "c"]
  join_example     = join("-", ["a", "b", "c"])   # "a-b-c"
  
  # Format strings
  formatted = format("Instance %s has %d CPUs", "i-123", 4)
  # "Instance i-123 has 4 CPUs"
  
  formatted_list = formatlist("Server: %s", var.users)
  # ["Server: alice", "Server: bob", ...]

  # Regular expressions
  regex_match = regex("^([a-z]+)-([0-9]+)$", "web-123")
  # ["web", "123"]

  regex_all = regexall("[a-z]+", "abc123def456")
  # ["abc", "def"]
}

# ============================================
# 4. COLLECTION FUNCTIONS
# ============================================

variable "list_a" {
  default = [1, 2, 3]
}

variable "list_b" {
  default = [3, 4, 5]
}

locals {
  # List operations
  concatenated = concat(var.list_a, var.list_b)     # [1, 2, 3, 3, 4, 5]
  distinct_list = distinct(local.concatenated)       # [1, 2, 3, 4, 5]
  reversed = reverse(var.list_a)                     # [3, 2, 1]
  sorted = sort(["c", "a", "b"])                     # ["a", "b", "c"]
  
  # Element access
  first_element = element(var.list_a, 0)             # 1
  last_element = element(var.list_a, length(var.list_a) - 1)  # 3

  # Slice
  sliced = slice(var.list_a, 0, 2)                   # [1, 2]

  # Range
  range_example = range(5)                            # [0, 1, 2, 3, 4]
  range_with_step = range(0, 10, 2)                  # [0, 2, 4, 6, 8]

  # Flatten nested lists
  nested = [[1, 2], [3, 4], [5, 6]]
  flattened = flatten(local.nested)                  # [1, 2, 3, 4, 5, 6]

  # Chunklist
  chunked = chunklist([1, 2, 3, 4, 5], 2)            # [[1, 2], [3, 4], [5]]

  # Set operations
  set_a = toset([1, 2, 3])
  set_b = toset([3, 4, 5])
  union = setunion(local.set_a, local.set_b)        # [1, 2, 3, 4, 5]
  intersection = setintersection(local.set_a, local.set_b)  # [3]
  difference = setsubtract(local.set_a, local.set_b)       # [1, 2]

  # Map operations
  map_merged = merge(
    { a = 1, b = 2 },
    { b = 3, c = 4 }
  )  # { a = 1, b = 3, c = 4 }

  map_keys = keys(local.map_merged)                 # ["a", "b", "c"]
  map_values = values(local.map_merged)             # [1, 3, 4]

  # Zipmap
  zipped = zipmap(
    ["name", "age", "role"],
    ["Alice", 30, "Developer"]
  )  # { name = "Alice", age = 30, role = "Developer" }
}

# ============================================
# 5. TYPE CONVERSION FUNCTIONS
# ============================================

locals {
  # To number
  num_from_string = tonumber("42")
  
  # To string
  string_from_num = tostring(42)
  
  # To list
  list_from_set = tolist(toset(["a", "b", "c"]))
  
  # To set
  set_from_list = toset(["a", "b", "a"])  # {"a", "b"}
  
  # To map
  map_from_object = tomap({
    name = "test"
    value = "123"
  })

  # JSON encode/decode
  json_encoded = jsonencode({ key = "value", list = [1, 2, 3] })
  json_decoded = jsondecode("{\"key\": \"value\"}")

  # YAML encode (Terraform 0.12+)
  yaml_encoded = yamlencode({ key = "value" })

  # Base64
  base64_encoded = base64encode("Hello World")
  base64_decoded = base64decode(local.base64_encoded)
}

# ============================================
# 6. MATH FUNCTIONS
# ============================================

locals {
  absolute = abs(-5)                    # 5
  ceiling = ceil(4.2)                   # 5
  floor_val = floor(4.8)               # 4
  maximum = max(1, 5, 3)               # 5
  minimum = min(1, 5, 3)               # 1
  power = pow(2, 3)                    # 8
  sign_val = signum(-10)              # -1
  
  # Sum of list
  sum_total = sum([1, 2, 3, 4, 5])    # 15
}

# ============================================
# OUTPUTS
# ============================================

output "uppercase_users" {
  value = local.uppercase_users
}

output "server_types" {
  value = local.server_types
}

output "all_combinations_count" {
  value = length(local.all_combinations)
}

output "all_ips" {
  value = local.all_ips
}

output "formatted_output" {
  value = local.formatted
}
