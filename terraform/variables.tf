variable "primary_region" {
  description = "Primary AWS region for the first VPC"
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Secondary AWS region for the second VPC"
  type        = string
  default     = "us-west-2"
}

variable "tertiary_region" {
  description = "Tertiary AWS region for the third VPC"
  type        = string
  default     = "eu-west-2"
}

# --- Primary VPC ---
variable "primary_vpc_cidr" {
  description = "CIDR block for the primary VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "primary_public_subnet_cidr" {
  description = "CIDR block for the primary public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "primary_private_subnet_cidr" {
  description = "CIDR block for the primary private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

# --- Secondary VPC ---
variable "secondary_vpc_cidr" {
  description = "CIDR block for the secondary VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "secondary_public_subnet_cidr" {
  description = "CIDR block for the secondary public subnet"
  type        = string
  default     = "10.1.1.0/24"
}

variable "secondary_private_subnet_cidr" {
  description = "CIDR block for the secondary private subnet"
  type        = string
  default     = "10.1.2.0/24"
}

# --- Tertiary VPC ---
variable "tertiary_vpc_cidr" {
  description = "CIDR block for the tertiary VPC"
  type        = string
  default     = "10.2.0.0/16"
}

variable "tertiary_public_subnet_cidr" {
  description = "CIDR block for the tertiary public subnet"
  type        = string
  default     = "10.2.1.0/24"
}

variable "tertiary_private_subnet_cidr" {
  description = "CIDR block for the tertiary private subnet"
  type        = string
  default     = "10.2.2.0/24"
}

# --- Common ---
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "primary_key_name" {
  description = "Name of the SSH key pair for Primary VPC instance"
  type        = string
  default     = ""
}

variable "secondary_key_name" {
  description = "Name of the SSH key pair for Secondary VPC instance"
  type        = string
  default     = ""
}

variable "tertiary_key_name" {
  description = "Name of the SSH key pair for Tertiary VPC instance"
  type        = string
  default     = ""
}
