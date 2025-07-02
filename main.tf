## Define Networking Component ## 
### VPC 
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "klr-vpc"
  cidr = "10.0.0.0/16"
  azs = [ "ap-southeast-2a", "ap-southeast-2b" ]
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  vpc_flow_log_iam_role_name = "vpc-role"
  vpc_flow_log_iam_role_use_name_prefix = false
  enable_flow_log = true 
  create_flow_log_cloudwatch_log_group = true 
  create_flow_log_cloudwatch_iam_role = true 
  flow_log_max_aggregation_interval = 60

}

### Security Groups 
resource "aws_security_group" "allow-webhook" {
  name = "allow-webhook-sg"
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

resource "aws_security_group" "allow-ssh" {
	name = "allow-ssh-sg"
	description = "Allow SSH to instance"
	vpc_id = module.vpc.vpc_id 

	ingress {
		from_port = 22 
		to_port = 22 
		protocol = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
	}
  
}

resource "aws_security_group" "allow-jenkins-access" {
	name = "allow-jenkins-access"
	description = "Custom Port for Jenkins"

	ingress {
		from_port = 8080
		to_port = 8080
		protocol = "tcp"
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
	security_groups = [aws_security_group.allow-jenkins-access.id, aws_security_group.allow-ssh.id, aws_security_group.allow-webhook.id]
	
	# Define the key-pair for SSH 

	
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
	security_groups = [ aws_security_group.allow-ssh.id ]

	# Define the key-pair for SSH 

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
module "s3-bucket-access" {
  source = "terraform-aws-modules/s3-bucket/aws"
  version = "5.1.0"
  bucket = "access_logs_klr_alb"
  versioning = {
    enabled = true
  }
  attach_elb_log_delivery_policy = true  
  attach_lb_log_delivery_policy  = true
}

module "s3-bucket-connection" {
  source = "terraform-aws-modules/s3-bucket/aws"
  version = "5.1.0"
  bucket = "connection_logs_klr_alb"
  versioning = {
    enabled = true
  }
  attach_elb_log_delivery_policy = true  
  attach_lb_log_delivery_policy  = true
  
}

resource "aws_lb" "alb-klr" {
	name = "alb-klr"

	# Add security group 

	load_balancer_type = "application"
	subnet_mapping {
		subnet_id = module.vpc.public_subnets[1]
	}

	access_logs {
	  bucket = module.s3-bucket-access.s3_bucket_id
	  enabled = true 
	  prefix = "klr-alb-access"
	}

	connection_logs {
	  bucket = module.s3-bucket-connection.s3_bucket_id
	  enabled = true 
	  prefix = "klr-alb-connection"
	}

}


### Route 53 



### ACM


## Define the EKS within the ALB
module "eks_managed_node_groups" {
  source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"

  name = "eks-node-groups"
  cluster_name = "klr-cluster"
  cluster_version = "1.32"

  cluster_primary_security_group_id = module.eks.cluster_primary_security_group_id
  vpc_security_group_ids            = [module.eks.node_security_group_id]

#   remote_access = {
#     ec2_ssh_key               = module.key_pair.key_pair_name
#     source_security_group_ids = [aws_security_group.remote_access.id]
#   }
  min_size     = 1
  max_size     = 10
  desired_size = 1

  instance_types = ["t2.large"]

  labels = {
    Environment = "test"
    GithubRepo  = "terraform-aws-eks"
    GithubOrg   = "terraform-aws-modules"
  }

  taints = {
    dedicated = {
      key    = "dedicated"
      value  = "gpuGroup"
      effect = "NO_SCHEDULE"
    }
  }
}

