terraform {
  backend "s3" {
    bucket       = "dev-remote-state-coderco-ecsv3"
    key          = "terraform.tfstate"
    encrypt      = true
    use_lockfile = true
    region       = "eu-west-2"
  }
}
