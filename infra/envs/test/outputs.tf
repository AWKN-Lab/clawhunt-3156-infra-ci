output "vpc_id" {
  description = "VPC ID"
  value       = alicloud_vpc.main.id
}

output "oss_bucket" {
  description = "OSS 数据桶名"
  value       = alicloud_oss_bucket.data.bucket
}

output "db_instance_id" {
  description = "RDS 实例 ID"
  value       = alicloud_db_instance.main.id
}
