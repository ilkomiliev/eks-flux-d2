resource "tls_private_key" "alb" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "alb" {
  private_key_pem       = tls_private_key.alb.private_key_pem
  validity_period_hours = 8760
  dns_names             = ["*.us-east-1.elb.amazonaws.com"]

  subject {
    common_name  = "*.us-east-1.elb.amazonaws.com"
    organization = "first-tofu experimental cluster"
  }

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "alb" {
  certificate_body       = tls_self_signed_cert.alb.cert_pem
  private_key_wo         = tls_private_key.alb.private_key_pem
  private_key_wo_version = 1

  tags = {
    Name = "${local.cluster_name}-self-signed"
  }
}