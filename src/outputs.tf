output "base_url" {
  value = "${aws_api_gateway_deployment.this.invoke_url}"
}

output "es_endpoint" {
  value = "${aws_elasticsearch_domain.es.endpoint}"
}

output "kibana_endpoint" {
  value = "${aws_elasticsearch_domain.es.kibana_endpoint}"
}
