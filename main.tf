## Define Networking Component ## 
### VPC 
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "klr-vpc"
  cidr = "10.0.0.0/16"
  
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  vpc_flow_log_iam_role_name = "vpc-role"
  vpc_flow_log_iam_role_use_name_prefix = false
  enable_flow_log = true 
  create_flow_log_cloudwatch_log_group = true 
  create_flow_log_cloudwatch_iam_role = true 
  flow_log_max_aggregation_interval = 60

}

### Security Groups 
resource "aws_security_group" "allow_webhook" {
  name = "allow-webhook"
  description = "Allow Webhook to communicate with Jenkins"
  vpc_id = module.vpc.vpc_id 

  ingress {
	from_port = 443 
	to_port = 443 
	protocol = "tcp"
	description = "HTTPS from Webhook"
	cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
	from_port = 80
	to_port = 80
	protocol = "tcp"
	description = "HTTP from Webhook"
	cidr_blocks = ["0.0.0.0/0"]
  }

}


## Define other components 
data "aws_ami" "amzn-linux-2023-ami" {
	most_recent = true 

	owners = [ "amazon" ]
	filter {
	  name = "name"
	  values = ["al2023-ami-2023.*-x86_64"]
	}
  
}

### EC2 instance for Jenkins 
resource "aws_instance" "jenkins-server" {
	ami = data.aws_ami.amzn-linux-2023-ami.id
	instance_type = "t2.large"  
	subnet_id = module.vpc.public_subnets[0]
	user_data = templatefile("${path.module}/install_jenkins.sh", {})

	tags = {
	  "server" = "Jenkins"
	}
}


### EC2 instance for Monitoring 
resource "aws_instance" "monitoring-server" {
    ami =  data.aws_ami.amzn-linux-2023-ami.id 
	instance_type = "t2.large"
	subnet_id = module.vpc.public_subnets[0]
	user_data = templatefile("${path.module}/install_monitoring.sh", {})

	tags = {
	  "server" = "Monitoring"
	}
}

### ECR
resource "aws_ecr_repository" "klr-repo" {
	name = "klr-repo"
	image_tag_mutability = "MUTABLE"

	image_scanning_configuration {
	  scan_on_push = true 
	}
  
}

### ALB
resource "aws_lb" "alb-klr" {
	name = "alb-klr"
	load_balancer_type = "application"
	subnet_mapping {
		subnet_id = module.vpc.public_subnets[1]
	}

	access_logs {
	  bucket = "access_logs_klr_alb"
	  enabled = true 
	  prefix = "klr-alb"
	}

	connection_logs {
	  bucket = "connection_logs_klr_alb"
	  enabled = true 
	  prefix = "klr-alb-connection"
	}

}

### Route 53 


### ACM


## Define the EKS within the ALB