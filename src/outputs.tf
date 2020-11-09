output "API_Gateway_base_url" {
  value = module.bexh_app.aws_api_gateway_deployment.invoke_url
}

# output "ElasticSearch_Endpoint" {
#   value = module.bexh_app.aws_elasticsearch_domain.es.endpoint
# }

# output "ElasticSearch_Kibana_Endpoint" {
#   value = module.bexh_app.aws_elasticsearch_domain.es.kibana_endpoint
# }
