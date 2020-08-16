provider "aws" {
    region = "us-east-1"
}

resource "aws_db_instance" "default" {
    allocated_storage = 5
    storage_type = "gp2"
    engine = "mysql"
    engine_version = "5.7"
    instance_class = "db.t2.micro"
    name = "BexhBackendDbMain"
    username = ""
    password = ""
    parameter_group_name = "default.mysql5.7"
}
