terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

locals {
  # Governance Policy Inputs
  project_name = "simple-pay-2025"
  environment  = "production"
  region       = "uksouth"

  # Naming conventions based on Governance Policy rules
  rg_name  = "rg-${local.project_name}-${local.environment}-${local.region}"
  vnet_name = "vnet-${local.project_name}-${local.environment}"
  aks_name  = "aks-${local.project_name}-${local.environment}"
  sb_ns_name = "sb-${local.project_name}-${local.environment}"

  # Derived naming patterns for resources not explicitly defined in governance rules
  # Pattern: resource_type-project-env
  sql_server_name = "sql-${local.project_name}-${local.environment}"
  sql_db_name     = "sqldb-${local.project_name}-${local.environment}"
  
  # Subnet naming patterns
  subnet_aks_name = "snet-aks-${local.project_name}-${local.environment}"
  subnet_pe_name  = "snet-pe-${local.project_name}-${local.environment}"
  nsg_aks_name    = "nsg-${local.subnet_aks_name}"

  # Architecture Inputs
  vnet_cidr = "11.1.0.0/16"
  # Carving subnets out of the VNet CIDR
  subnet_aks_cidr = "11.1.0.0/20"  # Addresses 11.1.0.0 - 11.1.15.255
  subnet_pe_cidr  = "11.1.16.0/24" # Addresses 11.1.16.0 - 11.1.16.255
  aks_min_nodes   = 3

  tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "Terraform"
  }
}

#---------------------------------------------------------------
# Resource Group
#---------------------------------------------------------------
resource "azurerm_resource_group" "rg" {
  name     = local.rg_name
  location = local.region
  tags     = local.tags
}

#---------------------------------------------------------------
# Networking (VNet & Subnets) - Highest Security
#---------------------------------------------------------------
resource "azurerm_virtual_network" "vnet" {
  name                = local.vnet_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = [local.vnet_cidr]
  tags                = local.tags
}

# Subnet for AKS (Application Subnet)
resource "azurerm_subnet" "aks_subnet" {
  name                 = local.subnet_aks_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.subnet_aks_cidr]
  
  # Governance tip: "Use ignore_missing_vnet_service_endpoint"
  # Enabling service endpoints as a best practice alongside Private Endpoints for depth.
  service_endpoints    = ["Microsoft.Sql", "Microsoft.ServiceBus"]
}

# Subnet for Private Endpoints (Database & Queue)
resource "azurerm_subnet" "pe_subnet" {
  name                                      = local.subnet_pe_name
  resource_group_name                       = azurerm_resource_group.rg.name
  virtual_network_name                      = azurerm_virtual_network.vnet.name
  address_prefixes                          = [local.subnet_pe_cidr]
  private_endpoint_network_policies_enabled = false
}

# Network Security Group for AKS Subnet
resource "azurerm_network_security_group" "aks_nsg" {
  name                = local.nsg_aks_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags

  security_rule {
    name                       = "AllowHTTPSInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Deny all other inbound traffic for high security
  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "aks_subnet_nsg" {
  subnet_id                 = azurerm_subnet.aks_subnet.id
  network_security_group_id = azurerm_network_security_group.aks_nsg.id
}

#---------------------------------------------------------------
# Private DNS Zones (for Private Endpoints)
#---------------------------------------------------------------
resource "azurerm_private_dns_zone" "sql_dns" {
  name                = "privatelink.database.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql_dns_link" {
  name                  = "sql-dns-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.sql_dns.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "azurerm_private_dns_zone" "sb_dns" {
  name                = "privatelink.servicebus.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "sb_dns_link" {
  name                  = "sb-dns-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.sb_dns.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

#---------------------------------------------------------------
# Azure Kubernetes Service (AKS) - deploymentFabric
#---------------------------------------------------------------
resource "azurerm_kubernetes_cluster" "aks" {
  name                = local.aks_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = local.aks_name
  tags                = local.tags

  default_node_pool {
    name           = "default"
    node_count     = local.aks_min_nodes
    vm_size        = "Standard_D2s_v3"
    vnet_subnet_id = azurerm_subnet.aks_subnet.id
    enable_auto_scaling = true
    min_count           = local.aks_min_nodes
    max_count           = local.aks_min_nodes + 2
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    network_policy    = "azure"
  }
}

#---------------------------------------------------------------
# Azure SQL Database - paymentDB
# Governance SKU: Azure SQL Server Standard
#---------------------------------------------------------------
resource "random_password" "sql_admin" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_mssql_server" "sql_server" {
  name                          = local.sql_server_name
  resource_group_name           = azurerm_resource_group.rg.name
  location                      = azurerm_resource_group.rg.location
  version                       = "12.0"
  administrator_login           = "sqladmin"
  administrator_login_password  = random_password.sql_admin.result
  public_network_access_enabled = false # High Security requirement
  tags                          = local.tags
}

resource "azurerm_mssql_database" "sql_db" {
  name      = local.sql_db_name
  server_id = azurerm_mssql_server.sql_server.id
  # Governance: "Azure SQL Server Standard". Mapping to DTU based Standard tier (S1) for production.
  sku_name  = "S1" 
  tags      = local.tags
}

resource "azurerm_private_endpoint" "sql_pe" {
  name                = "pe-${local.sql_server_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.pe_subnet.id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-${local.sql_server_name}"
    private_connection_resource_id = azurerm_mssql_server.sql_server.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdzg-${local.sql_server_name}"
    private_dns_zone_ids = [azurerm_private_dns_zone.sql_dns.id]
  }
}

#---------------------------------------------------------------
# Azure Service Bus - notificationQueue
# Governance SKU: Service Bus Premium
#---------------------------------------------------------------
resource "azurerm_servicebus_namespace" "sb" {
  name                          = local.sb_ns_name
  location                      = azurerm_resource_group.rg.location
  resource_group_name           = azurerm_resource_group.rg.name
  sku                           = "Premium" # Governance requirement
  capacity                      = 1
  public_network_access_enabled = false     # High Security requirement
  tags                          = local.tags
}

# Input 1 defines this as a "Topic" type
resource "azurerm_servicebus_topic" "sb_topic" {
  name         = "notification-topic"
  namespace_id = azurerm_servicebus_namespace.sb.id
}

resource "azurerm_private_endpoint" "sb_pe" {
  name                = "pe-${local.sb_ns_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.pe_subnet.id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-${local.sb_ns_name}"
    private_connection_resource_id = azurerm_servicebus_namespace.sb.id
    subresource_names              = ["namespace"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdzg-${local.sb_ns_name}"
    private_dns_zone_ids = [azurerm_private_dns_zone.sb_dns.id]
  }
}