terraform {
  backend "s3" {
    bucket = "my-aws-vpc-peering-demo-bucket"
    key    = "terraform/.terraform/terraform.tfstate"
    region = "us-east-1"
  }
}