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

variable "vpc" {
    type = string
    description = "vpc id"
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

variable "instance_count" {
    type = number
    description = "number of ecs task instances"
    default = 0
}

variable "ecs_task_definition_policy" {
    type = string
    description = "json encoded policy document"
}

variable "image" {
    type = string
    description = "path to image"
}

variable "portMappings" {
    type = list(map(string))
    default = []
}

variable "load_balancer" {
    type = bool
    default = false
}
