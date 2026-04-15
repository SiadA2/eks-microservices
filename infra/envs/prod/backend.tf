terraform {
  backend "s3" {
    bucket       = "eks-microservices-049217867073-eu-west-2-tfstate"
    key          = "prod/terraform.tfstate"
    region       = "eu-west-2"
    use_lockfile = true
  }
}
