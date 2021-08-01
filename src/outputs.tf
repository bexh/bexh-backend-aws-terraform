output "API_Gateway_base_url" {
  value = module.bexh_app.aws_api_gateway_deployment.invoke_url
}
