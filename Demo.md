# Complete Implementation Guide - AWS VPC Peering

## 📋 Table of Contents
1. [Project Overview](#project-overview)
2. [Architecture Design](#architecture-design)
3. [Detailed Implementation Sequence](#detailed-implementation-sequence)
4. [Resource-by-Resource Breakdown](#resource-by-resource-breakdown)
5. [Configuration Files](#configuration-files)
6. [Testing & Validation](#testing--validation)
7. [Troubleshooting](#troubleshooting)

---

## 🎯 Project Overview

### What This Project Does
This project creates a **hub-and-spoke VPC peering topology** across three AWS regions, demonstrating:
- Multi-region VPC deployment
- Cross-region VPC peering connections
- Security group configuration for cross-VPC communication
- EC2 instance deployment with user data
- Complete networking setup (subnets, IGWs, route tables)

### Architecture Summary
```
┌─────────────────┐
│   Primary VPC   │
│  (us-east-1)    │ ←──────┐
│  10.0.0.0/16    │        │
└─────────────────┘        │
                           │
                      VPC Peering
                           │
┌─────────────────┐        │        ┌─────────────────┐
│  Tertiary VPC   │ ←──────┴───────→│  Secondary VPC  │
│  (eu-west-2)    │                 │  (us-west-2)    │
│  10.2.0.0/16    │ ←───────────────│  10.1.0.0/16    │
└─────────────────┘   VPC Peering   └─────────────────┘
      (HUB)
```

### Visual Architecture Diagram

![AWS VPC Peering Architecture](Assets/00-architecture-diagram.png)
*Detailed multi-region VPC peering architecture showing full mesh topology with all networking components*

### Key Statistics
- **Total Resources**: ~35 AWS resources
- **Regions**: 3 (us-east-1, us-west-2, eu-west-2)
- **VPCs**: 3
- **Peering Connections**: 3
- **EC2 Instances**: 3
- **Lines of Terraform Code**: ~800+

### Infrastructure Overview

**Primary VPC Configuration (us-east-1)**

![Primary VPC Encryption Controls](Assets/05-primary-vpc-encryption-controls.png)
*Primary VPC with encryption controls enabled*

---

## 🏗️ Architecture Design

### Network Design

#### VPC CIDR Blocks (Non-Overlapping)
```
Primary VPC:    10.0.0.0/16  (65,536 IPs)
  └─ Subnet:    10.0.1.0/24  (256 IPs)

Secondary VPC:  10.1.0.0/16  (65,536 IPs)
  └─ Subnet:    10.1.1.0/24  (256 IPs)

Tertiary VPC:   10.2.0.0/16  (65,536 IPs)
  └─ Subnet:    10.2.1.0/24  (256 IPs)
```

**Why non-overlapping?** VPC peering requires unique CIDR blocks to route traffic correctly.

#### Peering Topology
```
Connection 1: Primary (us-east-1) ↔ Secondary (us-west-2)
Connection 2: Primary (us-east-1) ↔ Tertiary (eu-west-2)
Connection 3: Secondary (us-west-2) ↔ Tertiary (eu-west-2)
```

This creates a **full mesh** topology where all VPCs can communicate directly.

### Regional Distribution
- **us-east-1 (N. Virginia)**: Primary VPC - East Coast USA
- **us-west-2 (Oregon)**: Secondary VPC - West Coast USA
- **eu-west-2 (London)**: Tertiary VPC - Europe (Hub)

---

## 📝 Detailed Implementation Sequence

### Phase 1: Foundation Setup (Providers & Variables)

#### Step 1.1: Provider Configuration (`providers.tf`)
**Purpose**: Configure Terraform to work with multiple AWS regions simultaneously.

```hcl
# Terraform version and provider requirements
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

**What this does**:
- Requires Terraform version 1.6.0 or higher
- Uses AWS provider version 5.x
- Ensures compatibility and features

```hcl
# Primary region provider (us-east-1)
provider "aws" {
  region = var.primary_region
  alias  = "primary"
}

# Secondary region provider (us-west-2)
provider "aws" {
  region = var.secondary_region
  alias  = "secondary"
}

# Tertiary region provider (eu-west-2)
provider "aws" {
  region = var.tertiary_region
  alias  = "tertiary"
}
```

**Key Concept - Provider Aliases**:
- Each provider has a unique `alias` (primary, secondary, tertiary)
- Resources specify which provider to use: `provider = aws.primary`
- This allows managing resources in multiple regions from one configuration

---

#### Step 1.2: Variable Definitions (`variables.tf`)
**Purpose**: Define all configurable parameters with defaults.

**Region Variables**:
```hcl
variable "primary_region" {
  description = "Primary AWS region for the first VPC"
  type        = string
  default     = "us-east-1"
}
```

**Why we need this**: Allows easy region changes without modifying main code.

**VPC CIDR Variables**:
```hcl
variable "primary_vpc_cidr" {
  description = "CIDR block for the primary VPC"
  type        = string
  default     = "10.0.0.0/16"
}
```

**Complete Variable Structure**:
1. **Region variables** (3): primary_region, secondary_region, tertiary_region
2. **VPC CIDR variables** (3): primary_vpc_cidr, secondary_vpc_cidr, tertiary_vpc_cidr
3. **Subnet CIDR variables** (6): public and private for each VPC
4. **Instance variables** (1): instance_type
5. **SSH key variables** (3): primary_key_name, secondary_key_name, tertiary_key_name

**Total**: 16 variables defined

---

#### Step 1.3: Data Sources (`data.tf`)
**Purpose**: Fetch dynamic information from AWS.

**Availability Zones**:
```hcl
data "aws_availability_zones" "primary" {
  provider = aws.primary
  state    = "available"
}
```

**What this does**:
- Queries AWS for available AZs in us-east-1
- Returns list of AZ names (e.g., ["us-east-1a", "us-east-1b", ...])
- We use `[0]` to select the first available AZ

**AMI Lookup**:
```hcl
data "aws_ami" "primary_ami" {
  provider    = aws.primary
  most_recent = true
  owners      = ["099720109477"]  # Canonical (Ubuntu)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}
```

**What this does**:
- Searches for the latest Ubuntu 24.04 LTS AMI
- Uses Canonical's official AMI (owner ID: 099720109477)
- Filters for HVM virtualization with GP3 SSD storage
- Returns the most recent matching AMI ID

**Why data sources?**: AMI IDs differ by region. Data sources automatically find the correct AMI for each region.

---

### Phase 2: VPC Infrastructure

#### Step 2.1: Create Primary VPC (`main.tf` lines 5-16)
**Purpose**: Create the foundational network in us-east-1.

```hcl
resource "aws_vpc" "primary_vpc" {
  provider             = aws.primary
  cidr_block           = var.primary_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "Primary-VPC-${var.primary_region}"
    Environment = "Demo"
    Purpose     = "VPC-Peering-Demo"
  }
}
```

**Configuration Breakdown**:
- `provider = aws.primary`: Deploy in us-east-1
- `cidr_block = "10.0.0.0/16"`: 65,536 IP addresses
- `enable_dns_hostnames = true`: Instances get DNS names
- `enable_dns_support = true`: Enable DNS resolution
- `tags`: Metadata for identification and organization

**What happens in AWS**:
1. VPC is created with specified CIDR block
2. Default route table, NACL, and security group are auto-created
3. VPC gets a unique VPC ID (e.g., vpc-0abc123...)

---

#### Step 2.2: Create Secondary VPC (`main.tf` lines 19-30)
**Purpose**: Create the second network in us-west-2.

```hcl
resource "aws_vpc" "secondary_vpc" {
  provider             = aws.secondary
  cidr_block           = var.secondary_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "Secondary-VPC-${var.secondary_region}"
    Environment = "Demo"
    Purpose     = "VPC-Peering-Demo"
  }
}
```

**Key Difference**: Uses `provider = aws.secondary` to deploy in us-west-2.

---

#### Step 2.3: Create Tertiary VPC (`main.tf` lines 32-45)
**Purpose**: Create the hub VPC in eu-west-2.

```hcl
resource "aws_vpc" "tertiary_vpc" {
  provider             = aws.tertiary
  cidr_block           = var.tertiary_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "Tertiary-VPC-${var.tertiary_region}"
    Environment = "Demo"
    Purpose     = "VPC-Peering-Demo"
  }
}
```

**Why this VPC is special**: Central VPC in Europe in our multi-region topology.

**AWS Console - VPC Instances Created**

![Primary VPC Instance Details](Assets/01-primary-vpc-instance-details.png)
*Primary VPC EC2 instance running in us-east-1*

![Tertiary VPC Instance Details](Assets/02-tertiary-vpc-instance-details.png)
*Tertiary VPC EC2 instance running in eu-west-2*

![Secondary VPC Instance Details](Assets/03-secondary-vpc-instance-details.png)
*Secondary VPC EC2 instance running in us-west-2*

---

### Phase 3: Subnet Configuration

#### Step 3.1: Create Primary Subnet (`main.tf` lines 47-59)
**Purpose**: Create a public subnet within the Primary VPC.

```hcl
resource "aws_subnet" "primary_subnet" {
  provider                = aws.primary
  vpc_id                  = aws_vpc.primary_vpc.id
  cidr_block              = var.primary_public_subnet_cidr
  availability_zone       = data.aws_availability_zones.primary.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name        = "Primary-Subnet-${var.primary_region}"
    Environment = "Demo"
  }
}
```

**Configuration Details**:
- `vpc_id`: Links subnet to Primary VPC (dependency)
- `cidr_block = "10.0.1.0/24"`: 256 IP addresses (subset of VPC CIDR)
- `availability_zone`: Uses first available AZ from data source
- `map_public_ip_on_launch = true`: Instances get public IPs automatically

**Terraform Dependency**: This resource depends on `aws_vpc.primary_vpc` being created first.

---

#### Step 3.2: Create Secondary Subnet (`main.tf` lines 61-73)
**Purpose**: Create a public subnet in Secondary VPC.

```hcl
resource "aws_subnet" "secondary_subnet" {
  provider                = aws.secondary
  vpc_id                  = aws_vpc.secondary_vpc.id
  cidr_block              = var.secondary_public_subnet_cidr
  availability_zone       = data.aws_availability_zones.secondary.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name        = "Secondary-Subnet-${var.secondary_region}"
    Environment = "Demo"
  }
}
```

**Same pattern, different region**: Deployed in us-west-2 using secondary provider.

---

#### Step 3.3: Create Tertiary Subnet (`main.tf` lines 75-87)
**Purpose**: Create a public subnet in Tertiary VPC.

```hcl
resource "aws_subnet" "tertiary_subnet" {
  provider                = aws.tertiary
  vpc_id                  = aws_vpc.tertiary_vpc.id
  cidr_block              = var.tertiary_public_subnet_cidr
  availability_zone       = data.aws_availability_zones.tertiary.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name        = "Tertiary-Subnet-${var.tertiary_region}"
    Environment = "Demo"
  }
}
```

**Subnet Summary**:
- All subnets are public (have internet access)
- Each uses /24 CIDR (256 IPs)
- Auto-assign public IPs enabled

**AWS Console - Subnet Configuration**

![Primary VPC Subnets](Assets/04-primary-vpc-subnets-list.png)
*Primary VPC subnets configuration*

![Secondary Subnet us-west-2](Assets/13-secondary-subnet-us-west-2.png)
*Secondary VPC subnet in us-west-2 region*

![Tertiary Subnet eu-west-2](Assets/19-tertiary-subnet-eu-west-2.png)
*Tertiary VPC subnet in eu-west-2 region*

---

### Phase 4: Internet Connectivity

#### Step 4.1: Create Primary Internet Gateway (`main.tf` lines 89-97)
**Purpose**: Enable internet access for Primary VPC.

```hcl
resource "aws_internet_gateway" "primary_igw" {
  provider = aws.primary
  vpc_id   = aws_vpc.primary_vpc.id

  tags = {
    Name        = "Primary-IGW"
    Environment = "Demo"
  }
}
```

**What an IGW does**:
- Provides a target for internet-bound traffic
- Performs NAT for instances with public IPs
- Horizontally scaled, redundant, and highly available

**Dependency**: Must be attached to a VPC.

---

#### Step 4.2: Create Secondary Internet Gateway (`main.tf` lines 99-107)
```hcl
resource "aws_internet_gateway" "secondary_igw" {
  provider = aws.secondary
  vpc_id   = aws_vpc.secondary_vpc.id

  tags = {
    Name        = "Secondary-IGW"
    Environment = "Demo"
  }
}
```

---

#### Step 4.3: Create Tertiary Internet Gateway (`main.tf` lines 109-119)
```hcl
resource "aws_internet_gateway" "tertiary_igw" {
  provider = aws.tertiary
  vpc_id   = aws_vpc.tertiary_vpc.id

  tags = {
    Name        = "Tertiary-IGW"
    Environment = "Demo"
  }
}
```

**IGW Summary**: One IGW per VPC, all configured identically.

**AWS Console - Internet Gateways**

![Primary Internet Gateway](Assets/07-primary-internet-gateway.png)
*Primary VPC Internet Gateway*

![Secondary Internet Gateway](Assets/15-secondary-internet-gateway.png)
*Secondary VPC Internet Gateway*

![Tertiary Internet Gateway](Assets/21-tertiary-internet-gateway.png)
*Tertiary VPC Internet Gateway*

---

### Phase 5: Route Tables

#### Step 5.1: Create Primary Route Table (`main.tf` lines 121-135)
**Purpose**: Define routing rules for Primary VPC traffic.

```hcl
resource "aws_route_table" "primary_rt" {
  provider = aws.primary
  vpc_id   = aws_vpc.primary_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.primary_igw.id
  }

  tags = {
    Name        = "Primary-Route-Table"
    Environment = "Demo"
  }
}
```

**Route Explanation**:
- `cidr_block = "0.0.0.0/0"`: Default route (all internet traffic)
- `gateway_id`: Points to Internet Gateway
- **Meaning**: "Send all internet-bound traffic to the IGW"

**Additional Routes**: Peering routes will be added later as separate resources.

---

#### Step 5.2: Create Secondary Route Table (`main.tf` lines 137-151)
```hcl
resource "aws_route_table" "secondary_rt" {
  provider = aws.secondary
  vpc_id   = aws_vpc.secondary_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.secondary_igw.id
  }

  tags = {
    Name        = "Secondary-Route-Table"
    Environment = "Demo"
  }
}
```

---

#### Step 5.3: Create Tertiary Route Table (`main.tf` lines 153-167)
```hcl
resource "aws_route_table" "tertiary_rt" {
  provider = aws.tertiary
  vpc_id   = aws_vpc.tertiary_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.tertiary_igw.id
  }

  tags = {
    Name        = "Tertiary-Route-Table"
    Environment = "Demo"
  }
}
```

**Route Table Summary**: Each VPC has its own route table with internet access configured.

**AWS Console - Route Tables**

![Primary Route Table](Assets/06-primary-route-table-details.png)
*Primary VPC route table with peering routes*

![Secondary Route Table](Assets/14-secondary-route-table.png)
*Secondary VPC route table configuration*

![Tertiary Route Table](Assets/20-tertiary-route-table.png)
*Tertiary VPC route table configuration*

---

### Phase 6: Route Table Associations

#### Step 6.1: Associate Primary Route Table (`main.tf` lines 169-174)
**Purpose**: Link the route table to the subnet.

```hcl
resource "aws_route_table_association" "primary_rta" {
  provider       = aws.primary
  subnet_id      = aws_subnet.primary_subnet.id
  route_table_id = aws_route_table.primary_rt.id
}
```

**What this does**: Tells AWS to use `primary_rt` for all traffic from `primary_subnet`.

---

#### Step 6.2: Associate Secondary Route Table (`main.tf` lines 176-181)
```hcl
resource "aws_route_table_association" "secondary_rta" {
  provider       = aws.secondary
  subnet_id      = aws_subnet.secondary_subnet.id
  route_table_id = aws_route_table.secondary_rt.id
}
```

---

#### Step 6.3: Associate Tertiary Route Table (`main.tf` lines 183-188)
```hcl
resource "aws_route_table_association" "tertiary_rta" {
  provider       = aws.tertiary
  subnet_id      = aws_subnet.tertiary_subnet.id
  route_table_id = aws_route_table.tertiary_rt.id
}
```

**Association Summary**: All subnets now have routing tables with internet access.

---

### Phase 7: VPC Peering Connections

#### Step 7.1: Create Primary-Secondary Peering (`main.tf` lines 190-203)
**Purpose**: Establish peering between Primary and Secondary VPCs.

```hcl
resource "aws_vpc_peering_connection" "primary_to_secondary" {
  provider    = aws.primary
  vpc_id      = aws_vpc.primary_vpc.id
  peer_vpc_id = aws_vpc.secondary_vpc.id
  peer_region = var.secondary_region
  auto_accept = false

  tags = {
    Name        = "Primary-to-Secondary-Peering"
    Environment = "Demo"
    Side        = "Requester"
  }
}
```

**Configuration Breakdown**:
- `provider = aws.primary`: Requester is in us-east-1
- `vpc_id`: Local VPC (Primary)
- `peer_vpc_id`: Remote VPC (Secondary)
- `peer_region`: Cross-region peering to us-west-2
- `auto_accept = false`: Requires explicit acceptance

**Peering Process**:
1. Primary VPC sends peering request
2. Request goes to Secondary VPC in us-west-2
3. Status: "pending-acceptance"
4. Needs accepter resource to complete

---

#### Step 7.2: Accept Primary-Secondary Peering (`main.tf` lines 205-216)
**Purpose**: Accept the peering request from Secondary VPC side.

```hcl
resource "aws_vpc_peering_connection_accepter" "secondary_accepter" {
  provider                  = aws.secondary
  vpc_peering_connection_id = aws_vpc_peering_connection.primary_to_secondary.id
  auto_accept               = true

  tags = {
    Name        = "Secondary-Peering-Accepter"
    Environment = "Demo"
    Side        = "Accepter"
  }
}
```

**What happens**:
1. Uses secondary provider (us-west-2)
2. References the peering connection ID
3. `auto_accept = true`: Automatically accepts the request
4. Status changes to "active"

**Result**: Primary and Secondary VPCs are now peered!

**AWS Console - VPC Peering Connections**

![Primary to Secondary Peering](Assets/08-primary-to-secondary-peering-connection.png)
*Primary to Secondary VPC peering connection (Active)*

![Primary to Tertiary Peering](Assets/09-primary-to-tertiary-peering-connection.png)
*Primary to Tertiary VPC peering connection (Active)*

---

#### Step 7.3: Create Primary-Tertiary Peering (`main.tf` lines 237-250)
**Purpose**: Establish peering between Primary (us-east-1) and Tertiary (eu-west-2).

```hcl
resource "aws_vpc_peering_connection" "primary_to_tertiary" {
  provider    = aws.primary
  vpc_id      = aws_vpc.primary_vpc.id
  peer_vpc_id = aws_vpc.tertiary_vpc.id
  peer_region = var.tertiary_region
  auto_accept = false

  tags = {
    Name        = "Primary-to-Tertiary-Peering"
    Environment = "Demo"
    Side        = "Requester"
  }
}
```

**Cross-Region Details**:
- Requester: us-east-1 (Primary)
- Accepter: eu-west-2 (Tertiary)
- Spans North America to Europe

---

#### Step 7.4: Accept Primary-Tertiary Peering (`main.tf` lines 252-263)
```hcl
resource "aws_vpc_peering_connection_accepter" "tertiary_accepter_primary" {
  provider                  = aws.tertiary
  vpc_peering_connection_id = aws_vpc_peering_connection.primary_to_tertiary.id
  auto_accept               = true

  tags = {
    Name        = "Tertiary-Peering-Accepter-Primary"
    Environment = "Demo"
    Side        = "Accepter"
  }
}
```

---

#### Step 7.5: Create Secondary-Tertiary Peering (`main.tf` lines 265-278)
**Purpose**: Establish peering between Secondary (us-west-2) and Tertiary (eu-west-2).

```hcl
resource "aws_vpc_peering_connection" "secondary_to_tertiary" {
  provider    = aws.secondary
  vpc_id      = aws_vpc.secondary_vpc.id
  peer_vpc_id = aws_vpc.tertiary_vpc.id
  peer_region = var.tertiary_region
  auto_accept = false

  tags = {
    Name        = "Secondary-to-Tertiary-Peering"
    Environment = "Demo"
    Side        = "Requester"
  }
}
```

**Cross-Region Details**:
- Requester: us-west-2 (Secondary)
- Accepter: eu-west-2 (Tertiary)
- Spans West Coast USA to Europe

---

#### Step 7.6: Accept Secondary-Tertiary Peering (`main.tf` lines 280-291)
```hcl
resource "aws_vpc_peering_connection_accepter" "tertiary_accepter_secondary" {
  provider                  = aws.tertiary
  vpc_peering_connection_id = aws_vpc_peering_connection.secondary_to_tertiary.id
  auto_accept               = true

  tags = {
    Name        = "Tertiary-Peering-Accepter-Secondary"
    Environment = "Demo"
    Side        = "Accepter"
  }
}
```

**Peering Summary**:
- 3 peering connections established
- All connections are "active"
- Full mesh topology created

**AWS Console - Peering Accepters**

![Secondary Peering Accepter](Assets/16-secondary-peering-accepter.png)
*Secondary VPC accepting peering from Primary*

![Secondary to Tertiary Peering](Assets/17-secondary-to-tertiary-peering.png)
*Secondary to Tertiary VPC peering connection*

![Tertiary Peering Accepter Secondary](Assets/22-tertiary-peering-accepter-secondary.png)
*Tertiary VPC accepting peering from Secondary*

![Tertiary Peering Accepter Primary](Assets/23-tertiary-peering-accepter-primary.png)
*Tertiary VPC accepting peering from Primary*

---

### Phase 8: Peering Routes

#### Step 8.1: Primary to Secondary Route (`main.tf` lines 218-226)
**Purpose**: Add route in Primary VPC to reach Secondary VPC.

```hcl
resource "aws_route" "primary_to_secondary" {
  provider                  = aws.primary
  route_table_id            = aws_route_table.primary_rt.id
  destination_cidr_block    = var.secondary_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.primary_to_secondary.id

  depends_on = [aws_vpc_peering_connection_accepter.secondary_accepter]
}
```

**Route Explanation**:
- **Destination**: 10.1.0.0/16 (Secondary VPC)
- **Target**: Peering connection ID
- **Meaning**: "To reach 10.1.0.0/16, use the peering connection"

**Dependency**: Must wait for peering to be accepted before adding route.

---

#### Step 8.2: Secondary to Primary Route (`main.tf` lines 228-236)
**Purpose**: Add reverse route in Secondary VPC.

```hcl
resource "aws_route" "secondary_to_primary" {
  provider                  = aws.secondary
  route_table_id            = aws_route_table.secondary_rt.id
  destination_cidr_block    = var.primary_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.primary_to_secondary.id

  depends_on = [aws_vpc_peering_connection_accepter.secondary_accepter]
}
```

**Bidirectional Routing**: Both VPCs need routes to each other.

---

#### Step 8.3: Primary to Tertiary Route (`main.tf` lines 293-301)
```hcl
resource "aws_route" "primary_to_tertiary" {
  provider                  = aws.primary
  route_table_id            = aws_route_table.primary_rt.id
  destination_cidr_block    = var.tertiary_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.primary_to_tertiary.id

  depends_on = [aws_vpc_peering_connection_accepter.tertiary_accepter_primary]
}
```

**Route**: Primary (10.0.0.0/16) → Tertiary (10.2.0.0/16)

---

#### Step 8.4: Tertiary to Primary Route (`main.tf` lines 303-311)
```hcl
resource "aws_route" "tertiary_to_primary" {
  provider                  = aws.tertiary
  route_table_id            = aws_route_table.tertiary_rt.id
  destination_cidr_block    = var.primary_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.primary_to_tertiary.id

  depends_on = [aws_vpc_peering_connection_accepter.tertiary_accepter_primary]
}
```

**Route**: Tertiary (10.2.0.0/16) → Primary (10.0.0.0/16)

---

#### Step 8.5: Secondary to Tertiary Route (`main.tf` lines 313-321)
```hcl
resource "aws_route" "secondary_to_tertiary" {
  provider                  = aws.secondary
  route_table_id            = aws_route_table.secondary_rt.id
  destination_cidr_block    = var.tertiary_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.secondary_to_tertiary.id

  depends_on = [aws_vpc_peering_connection_accepter.tertiary_accepter_secondary]
}
```

**Route**: Secondary (10.1.0.0/16) → Tertiary (10.2.0.0/16)

---

#### Step 8.6: Tertiary to Secondary Route (`main.tf` lines 323-331)
```hcl
resource "aws_route" "tertiary_to_secondary" {
  provider                  = aws.tertiary
  route_table_id            = aws_route_table.tertiary_rt.id
  destination_cidr_block    = var.secondary_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.secondary_to_tertiary.id

  depends_on = [aws_vpc_peering_connection_accepter.tertiary_accepter_secondary]
}
```

**Route**: Tertiary (10.2.0.0/16) → Secondary (10.1.0.0/16)

**Routing Summary**:
- 8 routes total (2 per peering connection)
- All routes are bidirectional
- Complete connectivity between all VPCs

---

### Phase 9: Security Groups

#### Step 9.1: Create Primary Security Group (`main.tf` lines 337-393)
**Purpose**: Control inbound/outbound traffic for Primary VPC instances.

```hcl
resource "aws_security_group" "primary_sg" {
  provider    = aws.primary
  name        = "primary-vpc-sg"
  description = "Security group for Primary VPC instance"
  vpc_id      = aws_vpc.primary_vpc.id

  # SSH from anywhere
  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ICMP from Secondary VPC
  ingress {
    description = "ICMP from Secondary VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.secondary_vpc_cidr]
  }

  # All TCP from Secondary VPC
  ingress {
    description = "All traffic from Secondary VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.secondary_vpc_cidr]
  }

  # ICMP from Tertiary VPC
  ingress {
    description = "ICMP from Tertiary VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.tertiary_vpc_cidr]
  }

  # All TCP from Tertiary VPC
  ingress {
    description = "All traffic from Tertiary VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.tertiary_vpc_cidr]
  }

  # Allow all outbound
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "Primary-VPC-SG"
    Environment = "Demo"
  }
}
```

**Security Rules Breakdown**:

1. **SSH (Port 22)**:
   - Source: 0.0.0.0/0 (anywhere)
   - Purpose: Remote access for management
   - ⚠️ Demo only - restrict in production

2. **ICMP from Secondary**:
   - Source: 10.1.0.0/16
   - Purpose: Allow ping from Secondary VPC
   - Protocol: ICMP (ping)

3. **All TCP from Secondary**:
   - Source: 10.1.0.0/16
   - Ports: 0-65535
   - Purpose: Allow all TCP traffic from Secondary

4. **ICMP from Tertiary**:
   - Source: 10.2.0.0/16
   - Purpose: Allow ping from Tertiary VPC

5. **All TCP from Tertiary**:
   - Source: 10.2.0.0/16
   - Ports: 0-65535
   - Purpose: Allow all TCP traffic from Tertiary

6. **Egress (Outbound)**:
   - Destination: 0.0.0.0/0 (anywhere)
   - Protocol: All (-1)
   - Purpose: Allow all outbound traffic

---

#### Step 9.2: Create Secondary Security Group (`main.tf` lines 395-451)
**Purpose**: Control traffic for Secondary VPC instances.

```hcl
resource "aws_security_group" "secondary_sg" {
  provider    = aws.secondary
  name        = "secondary-vpc-sg"
  description = "Security group for Secondary VPC instance"
  vpc_id      = aws_vpc.secondary_vpc.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ICMP from Primary VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.primary_vpc_cidr]
  }

  ingress {
    description = "All traffic from Primary VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.primary_vpc_cidr]
  }

  ingress {
    description = "ICMP from Tertiary VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.tertiary_vpc_cidr]
  }

  ingress {
    description = "All traffic from Tertiary VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.tertiary_vpc_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "Secondary-VPC-SG"
    Environment = "Demo"
  }
}
```

**Same pattern**: Allows SSH, ICMP, and TCP from both Primary and Tertiary VPCs.

---

#### Step 9.3: Create Tertiary Security Group (`main.tf` lines 453-515)
**Purpose**: Control traffic for Tertiary VPC instances (Hub).

```hcl
resource "aws_security_group" "tertiary_sg" {
  provider    = aws.tertiary
  name        = "tertiary-vpc-sg"
  description = "Security group for Tertiary VPC instance"
  vpc_id      = aws_vpc.tertiary_vpc.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ICMP from Primary VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.primary_vpc_cidr]
  }

  ingress {
    description = "All traffic from Primary VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.primary_vpc_cidr]
  }

  ingress {
    description = "ICMP from Secondary VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.secondary_vpc_cidr]
  }

  ingress {
    description = "All traffic from Secondary VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.secondary_vpc_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "Tertiary-VPC-SG"
    Environment = "Demo"
  }
}
```

**Security Group Summary**:
- All 3 SGs allow SSH from anywhere (demo purposes)
- Each SG allows ICMP and TCP from the other 2 VPCs
- All allow unrestricted outbound traffic

**AWS Console - Security Groups**

![Primary VPC Security Group](Assets/10-primary-vpc-security-group.png)
*Primary VPC security group with inbound rules for SSH, ICMP, and TCP*

![Secondary VPC Security Group](Assets/11-secondary-vpc-security-group.png)
*Secondary VPC security group configuration*

![Tertiary VPC Security Group](Assets/24-tertiary-vpc-security-group.png)
*Tertiary VPC security group configuration*

---

### Phase 10: User Data Scripts

#### Step 10.1: Create User Data Locals (`locals.tf`)
**Purpose**: Define bootstrap scripts for EC2 instances.

```hcl
locals {
  # Primary instance user data
  primary_user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y apache2
    systemctl start apache2
    systemctl enable apache2
    echo "<h1>Primary VPC Instance - ${var.primary_region}</h1>" > /var/www/html/index.html
    echo "<p>Private IP: $(hostname -I)</p>" >> /var/www/html/index.html
  EOF

  # Secondary instance user data
  secondary_user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y apache2
    systemctl start apache2
    systemctl enable apache2
    echo "<h1>Secondary VPC Instance - ${var.secondary_region}</h1>" > /var/www/html/index.html
    echo "<p>Private IP: $(hostname -I)</p>" >> /var/www/html/index.html
  EOF

  # Tertiary instance user data
  tertiary_user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y apache2
    systemctl start apache2
    systemctl enable apache2
    echo "<h1>Tertiary VPC Instance - ${var.tertiary_region}</h1>" > /var/www/html/index.html
    echo "<p>Private IP: $(hostname -I)</p>" >> /var/www/html/index.html
  EOF
}
```

**Script Breakdown**:
1. `apt-get update -y`: Update package lists
2. `apt-get install -y apache2`: Install Apache web server
3. `systemctl start apache2`: Start Apache service
4. `systemctl enable apache2`: Enable Apache to start on boot
5. `echo "<h1>...</h1>"`: Create custom HTML page
6. Shows VPC name and private IP address

**Purpose**: Each instance will serve a simple web page identifying itself.

---

### Phase 11: EC2 Instances

#### Step 11.1: Create Primary Instance (`main.tf` lines 517-535)
**Purpose**: Launch EC2 instance in Primary VPC.

```hcl
resource "aws_instance" "primary_instance" {
  provider               = aws.primary
  ami                    = data.aws_ami.primary_ami.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.primary_subnet.id
  vpc_security_group_ids = [aws_security_group.primary_sg.id]
  key_name               = var.primary_key_name

  user_data = local.primary_user_data

  tags = {
    Name        = "Primary-VPC-Instance"
    Environment = "Demo"
    Region      = var.primary_region
  }

  depends_on = [aws_vpc_peering_connection_accepter.secondary_accepter]
}
```

**Configuration Details**:
- `ami`: Ubuntu 24.04 LTS (from data source)
- `instance_type`: t2.micro (free tier eligible)
- `subnet_id`: Placed in primary_subnet
- `vpc_security_group_ids`: Uses primary_sg
- `key_name`: SSH key for access
- `user_data`: Runs bootstrap script
- `depends_on`: Waits for peering to be active

**What happens on launch**:
1. Instance boots with Ubuntu 24.04
2. User data script runs automatically
3. Apache is installed and configured
4. Web page is created
5. Instance gets public and private IPs

---

#### Step 11.2: Create Secondary Instance (`main.tf` lines 537-555)
```hcl
resource "aws_instance" "secondary_instance" {
  provider               = aws.secondary
  ami                    = data.aws_ami.secondary_ami.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.secondary_subnet.id
  vpc_security_group_ids = [aws_security_group.secondary_sg.id]
  key_name               = var.secondary_key_name

  user_data = local.secondary_user_data

  tags = {
    Name        = "Secondary-VPC-Instance"
    Environment = "Demo"
    Region      = var.secondary_region
  }

  depends_on = [aws_vpc_peering_connection_accepter.secondary_accepter]
}
```

**Deployed in**: us-west-2 using secondary provider.

---

#### Step 11.3: Create Tertiary Instance (`main.tf` lines 557-579)
```hcl
resource "aws_instance" "tertiary_instance" {
  provider               = aws.tertiary
  ami                    = data.aws_ami.tertiary_ami.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.tertiary_subnet.id
  vpc_security_group_ids = [aws_security_group.tertiary_sg.id]
  key_name               = var.tertiary_key_name

  user_data = local.tertiary_user_data

  tags = {
    Name        = "Tertiary-VPC-Instance"
    Environment = "Demo"
    Region      = var.tertiary_region
  }

  depends_on = [
    aws_vpc_peering_connection_accepter.tertiary_accepter_primary,
    aws_vpc_peering_connection_accepter.tertiary_accepter_secondary
  ]
}
```

**Special dependency**: Waits for BOTH peering connections to be active.

**Instance Summary**:
- 3 instances total
- All running Ubuntu 24.04 LTS
- All running Apache web server
- All accessible via SSH and HTTP

**AWS Console - Additional VPC Resources**

![Secondary VPC us-west-2](Assets/12-secondary-vpc-us-west-2.png)
*Secondary VPC overview in us-west-2*

![Tertiary VPC eu-west-2](Assets/18-tertiary-vpc-eu-west-2.png)
*Tertiary VPC overview in eu-west-2*

---

### Phase 12: Outputs

#### Step 12.1: VPC Outputs (`outputs.tf` lines 3-21)
**Purpose**: Export VPC information for reference.

```hcl
output "primary_vpc_id" {
  description = "ID of the Primary VPC"
  value       = aws_vpc.primary_vpc.id
}

output "secondary_vpc_id" {
  description = "ID of the Secondary VPC"
  value       = aws_vpc.secondary_vpc.id
}

output "tertiary_vpc_id" {
  description = "ID of the Tertiary VPC"
  value       = aws_vpc.tertiary_vpc.id
}

output "primary_vpc_cidr" {
  description = "CIDR block of the Primary VPC"
  value       = aws_vpc.primary_vpc.cidr_block
}

# ... similar for secondary and tertiary
```

**Why outputs?**: Makes it easy to reference values without digging through AWS console.

---

#### Step 12.2: Peering Outputs (`outputs.tf` lines 23-31)
```hcl
output "vpc_peering_connection_id" {
  description = "ID of the VPC Peering Connection"
  value       = aws_vpc_peering_connection.primary_to_secondary.id
}

output "vpc_peering_primary_tertiary_id" {
  description = "ID of the Primary-Tertiary VPC Peering Connection"
  value       = aws_vpc_peering_connection.primary_to_tertiary.id
}

output "vpc_peering_secondary_tertiary_id" {
  description = "ID of the Secondary-Tertiary VPC Peering Connection"
  value       = aws_vpc_peering_connection.secondary_to_tertiary.id
}
```

---

#### Step 12.3: Instance Outputs (`outputs.tf` lines 33-61)
```hcl
output "primary_instance_id" {
  description = "ID of the Primary EC2 Instance"
  value       = aws_instance.primary_instance.id
}

output "primary_instance_private_ip" {
  description = "Private IP of the Primary EC2 Instance"
  value       = aws_instance.primary_instance.private_ip
}

output "primary_instance_public_ip" {
  description = "Public IP of the Primary EC2 Instance"
  value       = aws_instance.primary_instance.public_ip
}

# ... similar for secondary and tertiary
```

**Most useful outputs**: Public and private IPs for testing connectivity.

---

#### Step 12.4: Test Commands Output (`outputs.tf` lines 98-126)
**Purpose**: Provide ready-to-use test commands.

```hcl
output "test_connectivity_command" {
  description = "Command to test connectivity between VPCs"
  value       = <<-EOT
    Hub-and-Spoke VPC Peering Connectivity Tests:
    
    === Direct Peering Tests (Should Work) ===
    
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
  EOT
}
```

**Convenience**: Copy-paste commands with actual IP addresses filled in.

---

## 📁 Configuration Files

### File Structure
```
terraform/
├── main.tf                 # Core infrastructure (580 lines)
├── variables.tf            # Variable definitions (100 lines)
├── data.tf                 # Data sources (65 lines)
├── providers.tf            # Provider configuration (31 lines)
├── locals.tf               # Local values (37 lines)
├── outputs.tf              # Output values (126 lines)
├── backend.tf              # Backend configuration (7 lines)
└── terraform.tfvars.example # Example variables (31 lines)
```

### Total Code Statistics
- **Total Lines**: ~977 lines
- **Resources**: ~35 AWS resources
- **Variables**: 16 input variables
- **Outputs**: 15 output values
- **Data Sources**: 6 data sources
- **Locals**: 3 local values

**Terraform State Management**

![Terraform State File S3](Assets/25-terraform-state-file-s3.png)
*Terraform state file stored in S3 bucket for remote state management*

---

## 🧪 Testing & Validation

### Pre-Deployment Validation

#### 1. Terraform Validate
```bash
cd terraform
terraform validate
```
**Expected**: "Success! The configuration is valid."

#### 2. Terraform Format Check
```bash
terraform fmt -check
```
**Expected**: No output (all files formatted correctly)

#### 3. Terraform Plan
```bash
terraform plan
```
**Expected**: Plan to create ~35 resources

---

### Post-Deployment Testing

#### Test 1: Verify VPC Creation
```bash
# Check Primary VPC
aws ec2 describe-vpcs \
  --region us-east-1 \
  --filters "Name=tag:Name,Values=Primary-VPC-us-east-1"

# Check Secondary VPC
aws ec2 describe-vpcs \
  --region us-west-2 \
  --filters "Name=tag:Name,Values=Secondary-VPC-us-west-2"

# Check Tertiary VPC
aws ec2 describe-vpcs \
  --region eu-west-2 \
  --filters "Name=tag:Name,Values=Tertiary-VPC-eu-west-2"
```

---

#### Test 2: Verify Peering Status
```bash
# Check all peering connections
aws ec2 describe-vpc-peering-connections \
  --region us-east-1 \
  --filters "Name=status-code,Values=active"
```
**Expected**: 3 active peering connections

---

#### Test 3: Test Connectivity (Primary → Secondary)
```bash
# Get IPs from Terraform output
terraform output

# SSH into Primary instance
ssh -i vpc-peering-demo-east.pem ubuntu@<PRIMARY_PUBLIC_IP>

# From Primary instance, ping Secondary
ping <SECONDARY_PRIVATE_IP>

# Test HTTP
curl http://<SECONDARY_PRIVATE_IP>
```

**Expected**:
- Ping succeeds
- HTTP returns HTML page with "Secondary VPC Instance"

---

#### Test 4: Test Connectivity (Primary → Tertiary)
```bash
# SSH into Primary instance
ssh -i vpc-peering-demo-east.pem ubuntu@<PRIMARY_PUBLIC_IP>

# Ping Tertiary
ping <TERTIARY_PRIVATE_IP>

# Test HTTP
curl http://<TERTIARY_PRIVATE_IP>
```

**Expected**:
- Ping succeeds
- HTTP returns HTML page with "Tertiary VPC Instance"

---

#### Test 5: Test Connectivity (Secondary → Tertiary)
```bash
# SSH into Secondary instance
ssh -i vpc-peering-demo-west.pem ubuntu@<SECONDARY_PUBLIC_IP>

# Ping Tertiary
ping <TERTIARY_PRIVATE_IP>

# Test HTTP
curl http://<TERTIARY_PRIVATE_IP>
```

**Expected**:
- Ping succeeds
- HTTP returns HTML page with "Tertiary VPC Instance"

---

#### Test 6: Verify Web Servers
```bash
# Test from local machine
curl http://<PRIMARY_PUBLIC_IP>
curl http://<SECONDARY_PUBLIC_IP>
curl http://<TERTIARY_PUBLIC_IP>
```

**Expected**: Each returns HTML page with VPC name and private IP.

### Connectivity Test Results

**Test Results - SSH and Ping Tests**

![SSH Ping Test Primary VPC](Assets/26-ssh-ping-test-primary-vpc.png)
*SSH connection and ping test from Primary VPC instance*

![SSH Ping Test Tertiary VPC](Assets/27-ssh-ping-test-tertiary-vpc.png)
*SSH connection and ping test from Tertiary VPC instance*

![Ping Connectivity Test All VPCs](Assets/28-ping-connectivity-test-all-vpcs.png)
*Complete connectivity test showing successful ping between all three VPCs*

**Test Summary**:
- ✅ Primary → Secondary: Successful ping and HTTP
- ✅ Primary → Tertiary: Successful ping and HTTP  
- ✅ Secondary → Tertiary: Successful ping and HTTP
- ✅ All VPC peering connections are working correctly
- ✅ Full mesh topology verified

---

## 🔧 Troubleshooting

### Issue 1: Terraform Validate Fails
**Symptom**: Syntax errors or missing resources

**Solutions**:
1. Check for typos in resource names
2. Verify all variables are defined
3. Ensure provider aliases are correct
4. Run `terraform fmt` to fix formatting

---

### Issue 2: Peering Connection Stuck in "pending-acceptance"
**Symptom**: Peering shows as pending, not active

**Solutions**:
1. Verify accepter resource exists
2. Check `auto_accept = true` in accepter
3. Ensure correct provider is used
4. Check IAM permissions for cross-region peering

---

### Issue 3: Cannot SSH to Instances
**Symptom**: Connection timeout or refused

**Solutions**:
1. Verify security group allows SSH (port 22)
2. Check instance has public IP
3. Verify key pair exists and has correct permissions
4. Check internet gateway and route table
5. Verify NACL rules (if configured)

---

### Issue 4: Cannot Ping Between VPCs
**Symptom**: Ping fails between instances

**Solutions**:
1. Verify peering connection is "active"
2. Check route tables have peering routes
3. Verify security groups allow ICMP
4. Check source/destination IP addresses
5. Verify CIDR blocks don't overlap

---

### Issue 5: HTTP Requests Fail Between VPCs
**Symptom**: curl fails or times out

**Solutions**:
1. Verify Apache is running: `systemctl status apache2`
2. Check security groups allow TCP traffic
3. Verify peering routes exist
4. Test with ping first (ICMP)
5. Check instance firewall (ufw)

---

### Issue 6: User Data Script Didn't Run
**Symptom**: Apache not installed or web page missing

**Solutions**:
1. Check user data logs: `/var/log/cloud-init-output.log`
2. Manually run script commands
3. Verify internet connectivity from instance
4. Check for script syntax errors
5. Reboot instance to retry user data

---

## 📊 Resource Dependency Graph

```
Providers (3)
    ↓
Variables (16)
    ↓
Data Sources (6: AMIs, AZs)
    ↓
VPCs (3)
    ↓
Subnets (3) ← VPCs
    ↓
Internet Gateways (3) ← VPCs
    ↓
Route Tables (3) ← VPCs, IGWs
    ↓
Route Table Associations (3) ← Route Tables, Subnets
    ↓
VPC Peering Connections (3) ← VPCs
    ↓
VPC Peering Accepters (3) ← Peering Connections
    ↓
Peering Routes (8) ← Route Tables, Peering Connections, Accepters
    ↓
Security Groups (3) ← VPCs
    ↓
EC2 Instances (3) ← Subnets, Security Groups, AMIs, Peering Accepters
    ↓
Outputs (15) ← All Resources
```

---

## 🎯 Key Takeaways

### What You've Built
1. **Multi-Region Infrastructure**: 3 VPCs across 3 continents
2. **Full Mesh Peering**: All VPCs can communicate
3. **Complete Networking**: Subnets, IGWs, route tables, security groups
4. **Working Applications**: 3 web servers demonstrating connectivity
5. **Production-Ready Code**: Well-structured, documented, validated

### Skills Demonstrated
1. **Terraform Multi-Provider**: Managing multiple AWS regions
2. **VPC Peering**: Cross-region peering configuration
3. **Network Routing**: Route table and peering route management
4. **Security Groups**: Cross-VPC traffic rules
5. **EC2 Deployment**: Instance launch with user data
6. **Infrastructure as Code**: Modular, reusable code

### Important Concepts
1. **VPC Peering is NOT Transitive**: Traffic cannot route through a hub
2. **CIDR Blocks Must Not Overlap**: Required for peering
3. **Bidirectional Routes Required**: Both VPCs need routes
4. **Security Groups are Stateful**: Return traffic automatically allowed
5. **Provider Aliases**: Enable multi-region deployments

---

## 📚 Next Steps

### Enhancements You Could Add
1. **Private Subnets**: Add private subnets with NAT gateways
2. **VPC Flow Logs**: Enable traffic monitoring
3. **Application Load Balancers**: Distribute traffic across instances
4. **Auto Scaling**: Automatically scale instances
5. **CloudWatch Alarms**: Monitor resource health
6. **Systems Manager**: Keyless SSH access
7. **Transit Gateway**: More scalable multi-VPC connectivity

### Learning Resources
- [AWS VPC Peering Documentation](https://docs.aws.amazon.com/vpc/latest/peering/)
- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [VPC Peering Best Practices](https://docs.aws.amazon.com/vpc/latest/peering/vpc-peering-basics.html)

---

## ✅ Deployment Checklist

- [ ] AWS CLI installed and configured
- [ ] Terraform >= 1.6.0 installed
- [ ] SSH key pairs created in all 3 regions
- [ ] `terraform.tfvars` created from example
- [ ] Backend configured (S3 or local)
- [ ] Run `terraform init`
- [ ] Run `terraform validate`
- [ ] Run `terraform plan` and review
- [ ] Run `terraform apply`
- [ ] Test connectivity between all VPCs
- [ ] Verify web servers are running
- [ ] Document any issues
- [ ] Run `terraform destroy` when done

---

**Project Status**: ✅ Ready for Deployment

**Total Implementation Time**: ~2-3 hours (including testing)

**Estimated Deployment Time**: ~10 minutes

**Estimated Monthly Cost**: ~$15-25 (if left running)

---

*This implementation guide provides complete details of every resource, configuration, and step required to deploy a production-ready hub-and-spoke VPC peering architecture across three AWS regions.*
