data "template_file" "vault_config" {
  template = <<EOF
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

storage "inmem" {}

ui = true

disable_mlock = true
EOF
}