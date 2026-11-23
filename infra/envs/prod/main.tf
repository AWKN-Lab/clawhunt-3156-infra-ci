# dev 环境测试用配置（虚构数据，仅供 CI 流水线验证）。
# 命名与网段与 test/prod 相同结构、不同取值；不要把真实账号信息放进来。
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    alicloud = {
      source  = "aliyun/alicloud"
      version = "~> 1.0"
    }
  }
}

provider "alicloud" {
  region = var.region
}

resource "alicloud_vpc" "main" {
  vpc_name   = "member-space-${var.env_name}"
  cidr_block = var.vpc_cidr
}

resource "alicloud_vswitch" "main" {
  vpc_id       = alicloud_vpc.main.id
  cidr_block   = var.vswitch_cidr
  zone_id      = var.zone_id
  vswitch_name = "member-space-${var.env_name}"
}

resource "alicloud_security_group" "main" {
  security_group_name = "member-space-${var.env_name}"
  vpc_id              = alicloud_vpc.main.id
}

# 只放行内网段的 HTTPS；出站 0.0.0.0/0 是正常出站，不受入站规则约束。
resource "alicloud_security_group_rule" "https_internal" {
  type              = "ingress"
  ip_protocol       = "tcp"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "443/443"
  priority          = 1
  security_group_id = alicloud_security_group.main.id
  cidr_ip           = "10.0.0.0/8"
}

resource "alicloud_security_group_rule" "egress_any" {
  type              = "egress"
  ip_protocol       = "all"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "-1/-1"
  priority          = 1
  security_group_id = alicloud_security_group.main.id
  cidr_ip           = "0.0.0.0/0"
}

resource "alicloud_oss_bucket" "data" {
  bucket = var.bucket_name

  tags = {
    env = var.env_name
  }
}

resource "alicloud_oss_bucket_acl" "data" {
  bucket = alicloud_oss_bucket.data.bucket
  acl    = "private"
}

resource "alicloud_db_account" "app" {
  db_instance_id   = alicloud_db_instance.main.id
  account_name     = "app"
  account_password = var.db_password
}

resource "alicloud_db_instance" "main" {
  engine               = "MySQL"
  engine_version       = "8.0"
  instance_type        = "rds.mysql.t1.small"
  instance_storage     = "20"
  instance_charge_type = "Postpaid"
  instance_name        = "member-space-${var.env_name}"
  vswitch_id           = alicloud_vswitch.main.id
  security_ips         = ["10.0.0.0/8"]
}
