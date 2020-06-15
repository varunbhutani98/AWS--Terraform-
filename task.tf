//** Configure terraform to work for aws.

provider "aws" {
  region = "ap-south-1"
  profile = "varun2"
}
data "aws_vpc" "selected" {
    default = true
}

locals {
    vpc_id    = data.aws_vpc.selected.id
}

// creating aws key pair
resource "tls_private_key" "webserver_key" {
    algorithm   =  "RSA"
    rsa_bits    =  4096
}
resource "local_file" "private_key" {
    content         =  tls_private_key.webserver_key.private_key_pem
    filename        =  "webserver.pem"
    file_permission =  0400
}
resource "aws_key_pair" "webserver_key" {
    key_name   = "webserver"
    public_key = tls_private_key.webserver_key.public_key_openssh
}


//Creating Security Group
resource "aws_security_group" "terra_sec_grp" {
  name        = "terra_sec_grp"
  description = "allow https, ssh, icmp"
  vpc_id      = local.vpc_id

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

 ingress {
        description = "ping-icmp"
        from_port   = -1
        to_port     = -1
        protocol    = "icmp"
        cidr_blocks = ["0.0.0.0/0"]
 }

 egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
        Name = "webserver_terraform"
    }
}
//creating aws instance or say os 
resource "aws_instance" "webserver" {
  ami           = "ami-052c08d70def0ac62"
  instance_type = "t2.micro"
  availability_zone =  "ap-south-1b"  
  key_name      = aws_key_pair.webserver_key.key_name
  vpc_security_group_ids = [ "${aws_security_group.terra_sec_grp.id}" ] 
 

 tags = {
    Name = "Terraform_Webserver_OS"
  }


 connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.webserver_key.private_key_pem
    host     = aws_instance.webserver.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }
}
  //create a new ebs volume 
  resource "aws_ebs_volume" "terraebs" {
  availability_zone = aws_instance.webserver.availability_zone
  size              = 1
  tags = {
    Name = "terraebs"
  }
}

// attaching ebs volume to instance 
resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.terraebs.id
  instance_id = aws_instance.webserver.id
  force_detach = true
}


output "myos_ip" {
  value = aws_instance.webserver.public_ip
}

//
resource "null_resource" "nullremote"  {

depends_on = [
    aws_volume_attachment.ebs_att,
  ]

connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.webserver_key.private_key_pem
    host     = aws_instance.webserver.public_ip
  }

 provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/",
      "sudo git clone  https://github.com/varunbhutani98/terra_task.git /var/www/html/",
      "sudo setenforce 0"
    ]
  }
}

//Creating a S3 Bucket

resource "aws_s3_bucket" "firstbucket01" {
bucket = "bct01"
acl = "private"
versioning {
enabled = true
}
tags = {
Name = "firstbucket01" 
Environment = "Dev"
}
}

//Upload image in s3 Bucket

resource "aws_s3_bucket_object" "s3obj" {

/*
depends_on = [
    aws_s3_bucket.firstbucket01,
  ]
*/
  bucket = "${aws_s3_bucket.firstbucket01.id}"
  key    = "varun.jpg"
  source = "varun.jpg"
  acl = "public-read"
 
  
}

// Allow Public Access s3 bucket
resource "aws_s3_bucket_public_access_block" "example" {
  bucket = "${aws_s3_bucket.firstbucket01.id}"
  block_public_acls   = false
  block_public_policy = false
}




// creating cloudfront
resource "aws_cloudfront_distribution" "task1_cloudfront" {
    origin {
        domain_name = "bct01.s3.amazonaws.com"
        origin_id = "s3-bct01-id"


        custom_origin_config {
            http_port = 80
            https_port = 80
            origin_protocol_policy = "match-viewer"
            origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"]
        }
    }

 enabled = true


    default_cache_behavior {
        allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods = ["GET", "HEAD"]
        target_origin_id = "S3-ashu08-id"

        forwarded_values {
            query_string = false

            cookies {
               forward = "none"
            }
        }
        viewer_protocol_policy = "allow-all"
        min_ttl = 0
        default_ttl = 3600
        max_ttl = 86400
    }
restrictions {
        geo_restriction {

            restriction_type = "none"
        }
    }

    viewer_certificate {
        cloudfront_default_certificate = true
    }

//provisioner "local-exec" {
    //command = "google-chrome ${aws_instance.myin1.public_ip}"
 // }
}


