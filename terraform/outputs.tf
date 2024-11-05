output "vault_url" {
  value = "http://${aws_eip.vault_eip.public_ip}:8200"
}