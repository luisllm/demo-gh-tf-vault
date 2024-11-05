output "grafana_url" {
  value = "http://${aws_eip.grafana_eip.public_ip}:3000"
}