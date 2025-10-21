resource "aws_s3_bucket" "terraform-source-bucket" {
  bucket = "mtw-terraform-source-bucket"
}
resource "aws_s3_bucket_versioning" "versioning_terraform-source-bucket" {
  bucket = aws_s3_bucket.terraform-source-bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket" "terraform-art-bucket" {
  bucket = "mtw-terraform-art-bucket"
}
resource "aws_s3_bucket_versioning" "versioning_terraform-art-bucket" {
  bucket = aws_s3_bucket.terraform-art-bucket.id
  versioning_configuration {
    status = "Suspended"
  }
}
resource "aws_codedeploy_app" "helloWorld" {
  compute_platform = "Server"
  name             = "helloWorld"
}
resource "aws_iam_role_policy_attachment" "AWSCodeDeployRole" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
  role       = aws_iam_role.codepipeline_role.name
}
resource "aws_iam_role_policy_attachment" "AmazonEC2RoleforAWSCodeDeploy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforAWSCodeDeploy"
  role       = aws_iam_role.codepipeline_role.name
}
resource "aws_codedeploy_deployment_group" "helloWroldGroup" {
  app_name              = aws_codedeploy_app.helloWorld.name
  deployment_group_name = "helloWroldGroup"
  service_role_arn      = aws_iam_role.codepipeline_role.arn
  autoscaling_groups    = [aws_autoscaling_group.helloWorld.name]
}
resource "aws_autoscaling_group" "helloWorld" {
  name               = "helloWorld"
  desired_capacity   = 1
  max_size           = 1
  min_size           = 1
  availability_zones = ["us-west-1b"]
  launch_template {
    id      = aws_launch_template.helloWorld.id
    version = "$Latest"
  }
}
resource "aws_iam_instance_profile" "test_profile" {
  name = "test_profile"
  role = aws_iam_role.codepipeline_role.name
}
resource "aws_launch_template" "helloWorld" {
  name                                 = "helloWorld"
  image_id                             = "ami-051317f1184dd6e92"
  instance_initiated_shutdown_behavior = "terminate"
  instance_type                        = "t2.micro"
  key_name                             = "aws_testing"
  iam_instance_profile {
    arn = aws_iam_instance_profile.test_profile.arn
  }
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "helloWorld"
    }
  }
  user_data = filebase64("install_codedeploy_agent.sh")
}
resource "aws_codepipeline" "terraform" {
  name     = "terrformPipelineByMTW"
  role_arn = aws_iam_role.codepipeline_role.arn
  depends_on = [
    aws_codedeploy_deployment_group.helloWroldGroup
  ]
  artifact_store {
    location = aws_s3_bucket.terraform-art-bucket.bucket
    type     = "S3"
  }
  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "S3"
      version          = "1"
      output_artifacts = ["source_output"]
      configuration = {
        S3Bucket    = aws_s3_bucket.terraform-source-bucket.bucket
        S3ObjectKey = "code.zip"
      }
    }
  }
  stage {
    name = "Deploy"
    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeploy"
      input_artifacts = ["source_output"]
      version         = "1"
      configuration = {
        ApplicationName = "helloWorld"
        "DeploymentGroupName" : "helloWroldGroup"
      }
    }
  }
}
resource "aws_iam_role" "codepipeline_role" {
  name               = "test-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com",
        "Service": "codedeploy.amazonaws.com",
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}
resource "aws_iam_role_policy" "codepipeline_policy" {
  name   = "codepipeline_policy"
  role   = aws_iam_role.codepipeline_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect":"Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetBucketVersioning",
        "s3:PutObjectAcl",
        "s3:PutObject"
      ],
      "Resource": [
        "${aws_s3_bucket.terraform-source-bucket.arn}",
        "${aws_s3_bucket.terraform-source-bucket.arn}/*",
        "${aws_s3_bucket.terraform-art-bucket.arn}",
        "${aws_s3_bucket.terraform-art-bucket.arn}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:CreateTags",
        "iam:PassRole",
        "codebuild:BatchGetBuilds",
        "codebuild:StartBuild",
        "sts:AssumeRole",
        "codedeploy:CreateDeployment",
        "codedeploy:GetDeploymentConfig",
        "codedeploy:GetDeployment",
        "codedeploy:RegisterApplicationRevision",
        "codedeploy:GetApplicationRevision",
        "codedeploy:GetApplication"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}
