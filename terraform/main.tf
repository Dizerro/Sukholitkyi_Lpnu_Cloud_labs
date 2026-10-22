terraform {
  required_version = ">= 1.6"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  default = "eu-north-1"
}

variable "project" {
  default = "notes-api"
}

variable "github_repo" {
  description = "Dizerro/Sukholitkyi_Lpnu_Cloud_labs"
  type        = string
}

variable "image_tag" {
  default = "v0"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_ecr_repository" "app" {
  name         = var.project
  force_delete = true
  image_scanning_configuration {
    scan_on_push = true
  }
}