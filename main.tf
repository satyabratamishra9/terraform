provider "aws" {
  region = "us-east-2"
  access_key = "****"
  secret_key = "****"
}

module "ssh_key_pair" {
  source                = "git::https://github.com/cloudposse/terraform-tls-ssh-key-pair.git?ref=tags/0.2.0"
  namespace             = ""
  stage                 = ""
  name                  = "twitter-etl-demo"
  ssh_public_key_path   = "secrets"
  private_key_extension = ".pem"
  public_key_extension  = ".pub"
  chmod_command         = "chmod 600 %v"
}

resource "aws_key_pair" "ssh" {
  key_name   = "twitter-demo"
  public_key = "${module.ssh_key_pair.public_key}"
}

#data "aws_ami" "amazon-ami" {
#  owners      = ["amazon"]
#  most_recent = true
#
#  filter {
#    name   = "name"
#    values = ["CentOS Linux 7 x86_64 HVM EBS *"]
#  }
#
#  filter {
#    name   = "architecture"
#    values = ["x86_64"]
#  }
#
#  filter {
#    name   = "root-device-type"
#    values = ["ebs"]
#  }
#}

data "aws_ami" "amazon-ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "ec2-instance" {
  count                  = 10
  ami                    = "${data.aws_ami.amazon-ami.id}"
  instance_type          = "t2.medium"
  vpc_security_group_ids = ["${aws_security_group.security-group.id}"]
  subnet_id              = "${element(module.vpc.public_subnets, count.index % length(module.vpc.public_subnets))}"
  key_name               = "${aws_key_pair.ssh.key_name}"

  tags = {
    Name = "twitter-etl-demo-${count.index}"
  }
}
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "twitter-etl-demo"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-2a", "us-east-2b", "us-east-2c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
  enable_dns_hostnames = true

}

resource "aws_security_group" "security-group" {
  name          = "twitter-etl-demo"
  vpc_id        = "${module.vpc.vpc_id}"

  ingress {
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 22
    to_port     = 22
  }
  ingress {
    protocol    = "tcp"
    self        = true
    from_port   = 9092
    to_port     = 9092
  }
  ingress {
    protocol    = "tcp"
    self        = true
    from_port   = 2181
    to_port     = 2181
  }
  ingress {
    protocol    = "tcp"
    self        = true
    from_port   = 2888
    to_port     = 2888
  }
  ingress {
    protocol    = "tcp"
    self        = true
    from_port   = 3888
    to_port     = 3888
  }
  ingress {
    protocol    = "tcp"
    self        = true
    from_port   = 27017
    to_port     = 27017
  }
  ingress {
    protocol    = "tcp"
    self        = true
    from_port   = 8080
    to_port     = 8080
  }
  ingress {
    protocol    = "tcp"
    self        = true
    from_port   = 8081
    to_port     = 8081
  }
  ingress {
    protocol    = "tcp"
    self        = true
    from_port   = 7077
    to_port     = 7077
  }
  ingress {
    protocol    = "tcp"
    self        = true
    from_port   = 0
    to_port     = 65535
  }
#  ingress {
#    protocol    = "-1"
#    cidr_blocks = ["0.0.0.0/0"]
#    from_port   = 0
#    to_port     = 0
#  }
#  egress {
#    from_port   = 0
#    to_port     = 0
#    protocol    = "-1"
#    cidr_blocks = ["0.0.0.0/0"]
#  }
  tags = {
    Purpose = "twitter-etl-demo"
  }
}

resource "null_resource" "zookeeper_hosts" {
  provisioner "local-exec" {
    command = "echo [zookeeper] > hosts"
  }
}

resource "null_resource" "zookeeper_ip" {
  count = 3
  provisioner "local-exec" {
    command = <<EOF
              echo "${aws_instance.ec2-instance.*.public_ip[count.index]} zookeeper_id=${count.index} ansible_ssh_private_key_file=secrets/twitter-etl-demo.pem ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python" >> hosts
    EOF
  }
  depends_on = ["null_resource.zookeeper_hosts"]
}

resource "null_resource" "kafka_hosts" {
  provisioner "local-exec" {
    command = "echo [kafka] >> hosts"
  }
  depends_on = ["null_resource.zookeeper_ip"]

}

resource "null_resource" "kafka_ip" {
  count = 3
  provisioner "local-exec" {
    command = <<EOF
              echo "${aws_instance.ec2-instance.*.public_ip[count.index]} kafka_broker_id=${count.index} ansible_ssh_private_key_file=secrets/twitter-etl-demo.pem ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python" >> hosts
    EOF
  }
  depends_on = ["null_resource.kafka_hosts"]
}

resource "null_resource" "mongodb_master" {
  provisioner "local-exec" {
    command = "echo [mongo_master] >> hosts"
  }
  depends_on = ["null_resource.kafka_ip"]
}

resource "null_resource" "mongodb_master_ip" {
  provisioner "local-exec" {
    command = <<EOF
              echo "${aws_instance.ec2-instance.*.public_ip[3]} mongodb_master=True ansible_ssh_private_key_file=secrets/twitter-etl-demo.pem ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python" >> hosts
    EOF
  }
  depends_on = ["null_resource.mongodb_master"]
}

resource "null_resource" "mongodb_replicas" {
  provisioner "local-exec" {
    command = "echo [mongo_replicas] >> hosts"
  }
  depends_on = ["null_resource.mongodb_master_ip"]
}

resource "null_resource" "mongodb_replicas_ip" {
  provisioner "local-exec" {
    command = <<EOF
              echo "${aws_instance.ec2-instance.*.public_ip[4]} ansible_ssh_private_key_file=secrets/twitter-etl-demo.pem ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python" >> hosts
              echo "${aws_instance.ec2-instance.*.public_ip[5]} ansible_ssh_private_key_file=secrets/twitter-etl-demo.pem ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python" >> hosts
    EOF
  }
  depends_on = ["null_resource.mongodb_replicas"]
}

resource "null_resource" "spark_master" {
  provisioner "local-exec" {
    command = "echo [cluster_master] >> hosts"
  }
  depends_on = ["null_resource.mongodb_replicas_ip"]
}

resource "null_resource" "spark_master_ip" {
  provisioner "local-exec" {
    command = <<EOF
              echo "${aws_instance.ec2-instance.*.public_ip[6]} DNS=${aws_instance.ec2-instance.*.public_dns[6]} ansible_ssh_private_key_file=secrets/twitter-etl-demo.pem ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python" >> hosts
              echo "${aws_instance.ec2-instance.*.public_ip[7]} DNS=${aws_instance.ec2-instance.*.public_dns[7]} ansible_ssh_private_key_file=secrets/twitter-etl-demo.pem ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python" >> hosts
    EOF
  }
  depends_on = ["null_resource.spark_master"]
}

resource "null_resource" "spark_worker" {
  provisioner "local-exec" {
    command = "echo [cluster_nodes] >> hosts"
  }
  depends_on = ["null_resource.spark_master_ip"]
}

resource "null_resource" "spark_worker_ip" {
  provisioner "local-exec" {
    command = <<EOF
              echo "${aws_instance.ec2-instance.*.public_ip[8]} DNS=${aws_instance.ec2-instance.*.public_dns[8]} ansible_ssh_private_key_file=secrets/twitter-etl-demo.pem ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python" >> hosts
              echo "${aws_instance.ec2-instance.*.public_ip[9]} DNS=${aws_instance.ec2-instance.*.public_dns[9]} ansible_ssh_private_key_file=secrets/twitter-etl-demo.pem ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python" >> hosts
    EOF
  }
  depends_on = ["null_resource.spark_worker"]
}

#resource "null_resource" "configure_ansible" {
#  provisioner "local-exec" {
#    command = "sleep 120 && ansible-playbook -i hosts main.yaml"
#  }
#  depends_on = ["null_resource.spark_worker_ip"]
#}
