//Download git source on local system.
resource "null_resource" "local_git" {
  provisioner "local-exec" {
      command = "git clone https://github.com/piyu8787/terraform_task1-.git /path/"
  }
}
//AWS Provider .
provider "aws" {
  region                  = "ap-south-1"
  profile                 = "name_of_profile"
}
//Security Group 
resource "aws_security_group" "sg_terr1" {
name        = "Terra"
ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
}
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
    egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}
//Key Gengration for Instance 
resource "tls_private_key" "public_key_gen"{
algorithm = "RSA"
}
resource "aws_key_pair" "key_generation" {
key_name = "Name_of_key"
public_key = tls_private_key.public_key_gen.public_key_openssh
depends_on = [tls_private_key.public_key_gen]
}
//AWS Launch Instance .
resource "aws_instance" "web" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name      = "Name_of_key"
  vpc_security_group_ids = [ "${aws_security_group.sg_terr1.id}" ]
  tags = {
    Name = "Terraform_os"
  }
  //Connect to AWS .
  connection { 
	     type            = "ssh"
    	 user        = "ec2-user"
    	 private_key = tls_private_key.public_key_gen.private_key_pem
   	   host        = aws_instance.web.public_ip
  }
  //Install Server Software and Configure it .
  provisioner "remote-exec" {
    	inline = [
     		"sudo yum install httpd php -y",
        "sudo yum install git -y ",
    	  "sudo systemctl restart httpd ",	
    		"sudo systemctl enable httpd",
   
		]	
  }
}
output "instance_output" {
	value = aws_instance.web.public_ip
	
}
// Create a Extra Volume .
resource "aws_ebs_volume" "terraform_ebs" {

  type              = "gp2"
  availability_zone = aws_instance.web.availability_zone
  size              = 1

  tags = {
    Name = "Task1_ebs"
  }
}
// Attach the Extra Volume to EC-2 Instance .
resource "aws_volume_attachment" "ebs_att" {
depends_on = [
    aws_ebs_volume.terraform_ebs,
  ]
  device_name = "/dev/sdf"
  volume_id   = "${aws_ebs_volume.terraform_ebs.id}"
  instance_id = "${aws_instance.web.id}"
  force_detach = true 
}

// After Attachment Give the Formate and Mount IT .
resource "null_resource" "null_mount_drive" {
 depends_on = [
    aws_volume_attachment.ebs_att,
  ]
            
      connection { 
         type            = "ssh"
         user        = "ec2-user"
         private_key = tls_private_key.public_key_gen.private_key_pem
         host        = aws_instance.web.public_ip
  }
       provisioner "remote-exec" {
         inline = [
          "sudo mkfs.ext4 /dev/xvdf",
          "sudo mount /dev/xvdf  /var/www/html",
          "sudo rm -rf /var/www/html/",
          "sudo git clone /github_url/ /var/www/html"
   
        ] 
  }
}

// Create S3 Bucket and Upload a Image on the bucket 
resource "aws_s3_bucket" "tf" {
  bucket = "tfb123"
  acl    = "public-read"

  tags = {
    Name        = "My_bucket1234"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_object" "object" {
depends_on = [
    aws_s3_bucket.tf,
  ]
  bucket = "tfb123"
  key    = "shreeg.jpg"
  acl    = "public-read"  
  content_type = "image/png"
  source = "/home/pradhyumn/Desktop/git_terr/shreeg.jpg"
  //etag = "${filemd5("/home/pradhyumn/Desktop/git_terr/shreeg.jpg")}"
}

//CloudFront 
resource "aws_cloudfront_origin_access_identity" "origin_access_identity"{

  comment = "origin.access.identity"
}
data "aws_iam_policy_document" "s3_policy" {

statement {
actions = ["s3:GetObject"]
resources = ["${aws_s3_bucket.tf.arn}/*"]
principals {
type = "AWS"
identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
}
}
statement{
actions = ["s3:ListBucket"]
resources = ["${aws_s3_bucket.tf.arn}"]
principals {
type = "AWS"
identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
}
}
}
resource "aws_s3_bucket_policy" "bucket_policy" {
bucket = aws_s3_bucket.tf.id
policy = data.aws_iam_policy_document.s3_policy.json
} 

resource "aws_cloudfront_distribution" "s3_distribution" {
depends_on = [
    aws_s3_bucket_object.object,
  ]
  origin {
    domain_name = "${aws_s3_bucket.tf.bucket_regional_domain_name}"
    origin_id   = "S3-tf123"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  enabled             = true

default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-tf123"
    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
 price_class = "PriceClass_All"

 restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  tags = {
    Environment = "production"
  }
 
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

//Edit In index.html file 

resource "null_resource" "updating" {
depends_on = [
   aws_cloudfront_distribution.s3_distribution,
  ]
            
      connection { 
         type            = "ssh"
         user        = "ec2-user"
         private_key = tls_private_key.public_key_gen.private_key_pem
         host        = aws_instance.web.public_ip
  }
      provisioner "remote-exec" {
         inline = [ 
         "echo '<img src='https://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.object.key}'> ' | sudo tee -a /var/www/html/index.html"
         ]
  }
}
resource "null_resource" "local_start" {
depends_on = [
   null_resource.updating,
  ]

  provisioner "local-exec" {
      command = "firefox ${aws_instance.web.public_ip}"
  }
}


  


