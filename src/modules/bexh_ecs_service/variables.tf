variable "name" {
    type = string
}

variable "cluster_id" {
    type = string
}

variable "env_name" {
    type = string
}

variable "account_id" {
    type = string
}

variable "ecr_repository" {
    type = string
}

variable "image_tag" {
    type = string
}

variable "security_groups" {
    type = list(string)
}

variable "cpu" {
    type = string
    default = "512"
}

variable "memory" {
    type = string
    default = "1024"
}

variable "region" {
    type = string
    default = "us-east-1"
}

variable "log_level" {
    type = string
}

variable "subnets" {
    type = list(string)
}

variable "env_vars" {
    type = list(map(string))
}
