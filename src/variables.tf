variable "whitelisted_ips" {
    type = list(string)
    default = ["107.5.201.132/32", "70.88.232.46/32", "97.70.144.117/32", "68.56.130.250/32"]
}

variable "bexh_api_lambda_s3_version" {
    type = string
    default = "9V_l3pF7_W0LGDD7OSPw3633SaHeKiPG"
}