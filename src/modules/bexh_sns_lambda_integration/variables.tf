variable "function_name" {
    type = string
}

variable "s3_key" {
    type = string
}

variable "s3_object_version" {
    type = string
}

variable "env_name" {
    type = string
}

variable "account_id" {
    type = string
}

variable "handler" {
    type = string
}

variable "timeout" {
    type = number
    default = 60
}

variable "env_vars" {
    type = map
}

variable "sns_topic_name" {
    type = string
}

