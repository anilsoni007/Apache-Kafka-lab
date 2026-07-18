variable "name"            { type = string }
variable "vpc_id"          { type = string }
variable "subnet_ids"      { type = list(string) }
variable "allowed_sg_ids"  { type = list(string) }
variable "kafka_version"   { type = string }
variable "broker_instance" { type = string }
variable "broker_count"    { type = number }
variable "environment"     { type = string }
