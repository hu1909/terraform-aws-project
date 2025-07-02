terraform {
	required_providers {
		aws = {
			source = "hashicorp/aws"
			version = "~>5.0"
		}
	}

	backend "s3" {
	  bucket = "terraform-state-hu1909"
	  key = "/state/terraform.tfstate"
	  region = "ap-southeast-2"
	  encrypt = true
	}

}

provider "aws" {
	region = "ap-southeast-2"
}