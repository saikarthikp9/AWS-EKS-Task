//Setting Up AWS Provider

provider "aws" {
        region = "ap-south-1"
	profile = "attriprofile"
}


//Creating Variable for VPC

variable "vpc" {
  type    = string
  default = "vpc-dde2ffb5"
}

//Creating Key
resource "tls_private_key" "tls_key" {
  algorithm = "RSA"
}

//Generating Key-Value Pair
resource "aws_key_pair" "generated_key" {
  key_name   = "eks-key"
  public_key = tls_private_key.tls_key.public_key_openssh

  depends_on = [
    tls_private_key.tls_key
  ]
}

//Saving Private Key PEM File
resource "local_file" "key-file" {
  content  = tls_private_key.tls_key.private_key_pem
  filename = "eks-key.pem"

  depends_on = [
    tls_private_key.tls_key
  ]
}

//Creating Security Group For NodeGroups

resource "aws_security_group" "NodeGroup-SecurityGroup" {
  name        = "NodeGroup-SecurityGroup"
  description = "NodeGroupSG"
  vpc_id      = var.vpc


  //Adding Rules to Security Group 

  ingress {
    description = "SSH Rule"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    description = "HTTP Rule"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


//Getting all Subnet IDs of a VPC

data "aws_subnet_ids" "Subnet" {
  vpc_id = var.vpc
}


data "aws_subnet" "Subnet1" {
  for_each = data.aws_subnet_ids.Subnet.ids
  id       = each.value


  depends_on = [
    data.aws_subnet_ids.Subnet
  ]
}


//Creating IAM Role for EKS Cluster

resource "aws_iam_role" "EKS-Role" {
  name = "My-AWS-EKS-Cluster-Role"


// Policy

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}


//Attaching Polices to IAM Role for EKS

resource "aws_iam_role_policy_attachment" "IAM-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.EKS-Role.name
}


resource "aws_iam_role_policy_attachment" "IAM-AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.EKS-Role.name
}

//Created IAM Role for Node Groups

resource "aws_iam_role" "NG-Role" {
  name = "My-AWS-EKS-NG-Role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

//Attaching Policies to IAM Role of Node Groups

resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.NG-Role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.NG-Role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.NG-Role.name
}


//Creating EKS Cluster

resource "aws_eks_cluster" "EKSCluster" {
  name     = "My-AWS-EKS-Cluster"
  role_arn = aws_iam_role.EKS-Role.arn


  vpc_config {
    subnet_ids = [for s in data.aws_subnet.Subnet1 : s.id if s.availability_zone != "ap-south-1a"]
  }


  depends_on = [
    aws_iam_role_policy_attachment.IAM-AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.IAM-AmazonEKSServicePolicy,
    data.aws_subnet.Subnet1
  ]
}

//Creating a Node Group 1

resource "aws_eks_node_group" "NG1" {
  cluster_name    = aws_eks_cluster.EKSCluster.name
  node_group_name = "Node-Group1"
  node_role_arn   = aws_iam_role.NG-Role.arn
  subnet_ids      = [for s in data.aws_subnet.Subnet1 : s.id if s.availability_zone != "ap-south-1a"]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  instance_types  = ["t2.micro"]

  remote_access {
    ec2_ssh_key = "eks-key"
    source_security_group_ids = [aws_security_group.NodeGroup-SecurityGroup.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
    aws_eks_cluster.EKSCluster
  ]
}

//Creating Node Group 2

resource "aws_eks_node_group" "NG2" {
  cluster_name    = aws_eks_cluster.EKSCluster.name
  node_group_name = "Node-Group2"
  node_role_arn   = aws_iam_role.NG-Role.arn
  subnet_ids      = [for s in data.aws_subnet.Subnet1 : s.id if s.availability_zone != "ap-south-1a"]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  instance_types  = ["t2.micro"]

  remote_access {
    ec2_ssh_key = "eks-key"
    source_security_group_ids = [aws_security_group.NodeGroup-SecurityGroup.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
    aws_eks_cluster.EKSCluster
  ]
}


//Updating Kubectl Config File

resource "null_resource" "Update-Kube-Config" {
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name My-AWS-EKS-Cluster"
  }
  depends_on = [
    aws_eks_node_group.NG1,
    aws_eks_node_group.NG2
  ]
}
