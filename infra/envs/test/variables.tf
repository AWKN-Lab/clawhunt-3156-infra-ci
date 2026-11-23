variable "region" {
  description = "阿里云地域（虚构测试值）"
  type        = string
  default     = "cn-hangzhou"
}

variable "env_name" {
  description = "环境名：dev / test / prod"
  type        = string
  default     = "test"
}

variable "zone_id" {
  description = "可用区（虚构测试值）"
  type        = string
  default     = "cn-hangzhou-h"
}

variable "vpc_cidr" {
  description = "VPC 网段"
  type        = string
  default     = "10.2.0.0/16"
}

variable "vswitch_cidr" {
  description = "交换机网段"
  type        = string
  default     = "10.2.1.0/24"
}

variable "bucket_name" {
  description = "OSS 数据桶名（虚构测试值）"
  type        = string
  default     = "member-space-data-test-example"
}

variable "db_password" {
  description = "数据库密码：只从环境变量 / CI secrets 注入，不写进代码与 plan 评论"
  type        = string
  sensitive   = true
}
