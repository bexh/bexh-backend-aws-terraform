output "API Gateway base_url" {
  value = "${aws_api_gateway_deployment.this.invoke_url}"
}

output "ElasticSearch Endpoint" {
  value = "${aws_elasticsearch_domain.es.endpoint}"
}

output "ElasticSearch Kibana Endpoint" {
  value = "${aws_elasticsearch_domain.es.kibana_endpoint}"
}
