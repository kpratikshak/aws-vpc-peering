# Outputs for VPC Peering Demo

output "primary_vpc_id" {
  description = "ID of the Primary VPC"
  value       = aws_vpc.primary_vpc.id
}

output "secondary_vpc_id" {
  description = "ID of the Secondary VPC"
  value       = aws_vpc.secondary_vpc.id
}

output "primary_vpc_cidr" {
  description = "CIDR block of the Primary VPC"
  value       = aws_vpc.primary_vpc.cidr_block
}

output "secondary_vpc_cidr" {
  description = "CIDR block of the Secondary VPC"
  value       = aws_vpc.secondary_vpc.cidr_block
}

output "vpc_peering_connection_id" {
  description = "ID of the VPC Peering Connection"
  value       = aws_vpc_peering_connection.primary_to_secondary.id
}

output "vpc_peering_status" {
  description = "Status of the VPC Peering Connection"
  value       = aws_vpc_peering_connection.primary_to_secondary.accept_status
}

output "primary_instance_id" {
  description = "ID of the Primary EC2 Instance"
  value       = aws_instance.primary_instance.id
}

output "secondary_instance_id" {
  description = "ID of the Secondary EC2 Instance"
  value       = aws_instance.secondary_instance.id
}

output "primary_instance_private_ip" {
  description = "Private IP of the Primary EC2 Instance"
  value       = aws_instance.primary_instance.private_ip
}

output "secondary_instance_private_ip" {
  description = "Private IP of the Secondary EC2 Instance"
  value       = aws_instance.secondary_instance.private_ip
}

output "primary_instance_public_ip" {
  description = "Public IP of the Primary EC2 Instance"
  value       = aws_instance.primary_instance.public_ip
}

output "secondary_instance_public_ip" {
  description = "Public IP of the Secondary EC2 Instance"
  value       = aws_instance.secondary_instance.public_ip
}

output "tertiary_vpc_id" {
  description = "ID of the Tertiary VPC"
  value       = aws_vpc.tertiary_vpc.id
}

output "tertiary_vpc_cidr" {
  description = "CIDR block of the Tertiary VPC"
  value       = aws_vpc.tertiary_vpc.cidr_block
}

output "vpc_peering_primary_tertiary_id" {
  description = "ID of the Primary-Tertiary VPC Peering Connection"
  value       = aws_vpc_peering_connection.primary_to_tertiary.id
}

output "vpc_peering_secondary_tertiary_id" {
  description = "ID of the Secondary-Tertiary VPC Peering Connection"
  value       = aws_vpc_peering_connection.secondary_to_tertiary.id
}

output "tertiary_instance_id" {
  description = "ID of the Tertiary EC2 Instance"
  value       = aws_instance.tertiary_instance.id
}

output "tertiary_instance_private_ip" {
  description = "Private IP of the Tertiary EC2 Instance"
  value       = aws_instance.tertiary_instance.private_ip
}

output "tertiary_instance_public_ip" {
  description = "Public IP of the Tertiary EC2 Instance"
  value       = aws_instance.tertiary_instance.public_ip
}

output "test_connectivity_command" {
  description = "Command to test connectivity between VPCs"
  value       = <<-EOT
    Multi-Region VPC Peering Connectivity Tests:
    
    === Full Mesh Topology - All Direct Peering Connections (All Should Work) ===
    
    1. Primary → Secondary (Direct Peering):
       ssh -i your-key.pem ubuntu@${aws_instance.primary_instance.public_ip}
       ping ${aws_instance.secondary_instance.private_ip}
       curl http://${aws_instance.secondary_instance.private_ip}
    
    2. Primary → Tertiary (Direct Peering):
       ssh -i your-key.pem ubuntu@${aws_instance.primary_instance.public_ip}
       ping ${aws_instance.tertiary_instance.private_ip}
       curl http://${aws_instance.tertiary_instance.private_ip}
    
    3. Secondary → Tertiary (Direct Peering):
       ssh -i your-key.pem ubuntu@${aws_instance.secondary_instance.public_ip}
       ping ${aws_instance.tertiary_instance.private_ip}
       curl http://${aws_instance.tertiary_instance.private_ip}
    
    === Architecture Notes ===
    
    This is a FULL MESH topology where all three VPCs have direct peering connections:
    - Primary ↔ Secondary
    - Primary ↔ Tertiary
    - Secondary ↔ Tertiary
    
    All VPCs can communicate directly with each other across regions.
  EOT
}
