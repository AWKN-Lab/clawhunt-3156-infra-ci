# tflint 配置：只用 tflint 内置的 terraform 语言规则集（recommended 预设）。
#
# 关于“alicloud 规则集”的核实（2026-11-24，本机实测）：
#   - terraform-linters 官方只提供 AWS / Azure / GCP 三个云厂商规则集，
#     没有 alicloud 规则集（api.github.com 查
#     terraform-linters/tflint-ruleset-alicloud 返回 404；tflint-ruleset
#     topic 列表里也没有阿里云规则集）。
#   - 所以本单不虚构插件地址、不装来路不明的第三方插件。
#   - 阿里云相关的检查改由另外两道门覆盖，本文件只负责语言层：
#       terraform validate（provider schema：参数名/必填项/类型）
#       checkov（CKV_ALI_1/2/3/9 + 自定义 CKV_CUSTOM_ALI_1，见 .checkov.yaml）
#   - 今后若出现官方或可信的 alicloud 规则集，再把 plugin "alicloud" 加回来，
#     并把版本钉死；加之前先在本地跑通 tflint --init。

config {
  format = "compact"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
