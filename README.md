# bexh-backend-aws-terraform

SSH Tunneling into kibana:

ssh -i "~/.ssh/jumpbox.pem" ec2-user@ec2-23-20-163-198.compute-1.amazonaws.com -ND 8157

Go to settings > network > advanced > proxies

check socks proxy

proxy server: localhost:8157

bypass for domains: https://vpc-bexh-autocomplete-dev-ambtcunjvvgj73buvtzn456jye.us-east-1.es.amazonaws.com/_plugin/kibana/

Go to https://vpc-bexh-autocomplete-dev-ambtcunjvvgj73buvtzn456jye.us-east-1.es.amazonaws.com/_plugin/kibana/