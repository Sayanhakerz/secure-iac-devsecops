terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  required_version = ">= 1.5.0"
}

provider "aws" {
  region = "ap-south-1"
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "kms_key_policy" {
  statement {
    sid    = "EnableRootAccountKMSManagement"
    effect = "Allow"

    principals {
      type = "AWS"

      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      ]
    }

    actions = [
      "kms:Create*",
      "kms:Describe*",
      "kms:Enable*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Revoke*",
      "kms:Disable*",
      "kms:Get*",
      "kms:Delete*",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion"
    ]

    resources = ["*"]

    # Documented exceptions for the KMS administrative recovery statement.
    # The principal is restricted to this AWS account and permissions are
    # restricted to KMS APIs.

    #checkov:skip=CKV_AWS_109:Controlled KMS administration requires write-capable key-management permissions.
    #checkov:skip=CKV_AWS_111:KMS administration requires write access restricted to KMS APIs.
    #checkov:skip=CKV_AWS_356:KMS key policy actions operate on the KMS key resource and require the policy resource wildcard.
  }
}

resource "aws_s3_bucket" "secure_iac_demo" {
  bucket = "secure-iac-demo-${data.aws_caller_identity.current.account_id}"

  # Documented lab-scope exceptions.
  #checkov:skip=CKV2_AWS_62:Event notifications are outside the scope of this demonstration bucket.
  #checkov:skip=CKV_AWS_144:Cross-region replication is outside the scope of this low-value demonstration environment.
  #checkov:skip=CKV_AWS_18:Dedicated S3 access logging is outside the scope of this demonstration environment.

  tags = {
    Project     = "Secure-IaC-DevSecOps"
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "secure_iac_demo" {
  bucket = aws_s3_bucket.secure_iac_demo.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "secure_iac_demo" {
  bucket = aws_s3_bucket.secure_iac_demo.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_kms_key" "secure_iac_demo" {
  description             = "KMS key for Secure IaC demonstration S3 bucket"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  tags = {
    Project = "Secure-IaC-DevSecOps"
  }
}

resource "aws_kms_key_policy" "secure_iac_demo" {
  key_id = aws_kms_key.secure_iac_demo.id
  policy = data.aws_iam_policy_document.kms_key_policy.json
}

resource "aws_s3_bucket_server_side_encryption_configuration" "secure_iac_demo" {
  bucket = aws_s3_bucket.secure_iac_demo.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.secure_iac_demo.arn
    }

    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "secure_iac_demo" {
  bucket = aws_s3_bucket.secure_iac_demo.id

  rule {
    id     = "secure-lifecycle"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
