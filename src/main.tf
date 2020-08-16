provider "aws" {
    region = "us-east-1"
}

data "aws_caller_identity" "current" {}

resource "aws_security_group" "rds_sg" {
    name = "tcp-ip-whitelist"
    description = "RDS tcp ip whitelist"

    ingress {
        description = "TCP/IP for RDS with whitelisting"
        from_port = 3306
        to_port = 3306
        protocol  = "tcp"
        cidr_blocks = ["107.5.201.132/32", "70.88.232.46/32", "97.70.144.117/32"]
    }

    ingress {
        description = "All inbound from sg"
        from_port = 0
        to_port = 0
        protocol = "-1"
        self = true
    }

    egress {
        description = "All outbound"
        from_port = 0
        to_port = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_db_instance" "bexh-rds" {
    allocated_storage = 5
    storage_type = "gp2"
    engine = "mysql"
    engine_version = "8.0.17"
    instance_class = "db.t2.micro"
    name = "BexhBackendDbMain"
    username = "bexh"
    password = "PASSWORD"
    parameter_group_name = "default.mysql8.0"
    publicly_accessible = true
    skip_final_snapshot = true
    vpc_security_group_ids = ["${aws_security_group.rds_sg.id}"]
}

resource "null_resource" "setup_db" {
  depends_on = [aws_db_instance.bexh-rds] #wait for the db to be ready
  triggers = {
    file_sha = "${sha1(file("file.sql"))}"
  }
  provisioner "local-exec" {
    command = "mysql -u ${aws_db_instance.bexh-rds.username} -pPASSWORD -h ${aws_db_instance.bexh-rds.address} < file.sql"
  }
}
