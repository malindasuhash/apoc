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
  # Input 2 Governance: Approved Region
  location = "uksouth"
  env_name = "production"
  prefix   = "pay-prod"

  tags = {
    Environment = local.env_name
    Project     = "Payment Service"
    ManagedBy   = "Terraform"
  }

  # Input 1 Architecture: VNet CIDR
  vnet_cidr = "11.1.0.0/16"
  # Subnet planning based on VNet CIDR
  app_subnet_cidr      = "11.1.1.0/24"
  resource_subnet_cidr = "11.1.2.0/24"
}

# Generate secure passwords for infrastructure
resource "random_password" "sql_admin" {
  length           = 32
  special          = true
  override_special = "_%@"
}

# ==============================================================================
# Base Infrastructure (Input 1: env, region, network)
# ==============================================================================

resource "azurerm_resource_group" "main" {
  name     = "${local.prefix}-rg"
  location = local.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "main" {
  name                = "${local.prefix}-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [local.vnet_cidr]
  tags                = local.tags
}

# Application Subnet for AKS
resource "azurerm_subnet" "application" {
  name                 = "application-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [local.app_subnet_cidr]
}

# Resource Subnet for DB and Queue (Private PaaS services)
resource "azurerm_subnet" "resources" {
  name                 = "resource-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [local.resource_subnet_cidr]

  # Required for VNet integration with SQL and ServiceBus
  service_endpoints = [
    "Microsoft.Sql",
    "Microsoft.ServiceBus"
  ]
}

# ==============================================================================
# Database Infrastructure
# Input 1: relationalDatabase
# Input 2 Governance: Azure SQL Server Standard
# ==============================================================================

resource "azurerm_mssql_server" "main" {
  # Ensure global uniqueness
  name                         = "${local.prefix}-sqlsvr-${random_password.sql_admin.result}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = random_password.sql_admin.result
  minimum_tls_version          = "1.2"

  tags = local.tags
}

resource "azurerm_mssql_database" "payment_db" {
  name      = "paymentDB"
  server_id = azurerm_mssql_server.main.id
  collation = "SQL_Latin1_General_CP1_CI_AS"
  # Governance: "Azure SQL Server Standard". S1 is a baseline Standard SKU.
  sku_name = "S1"

  tags = local.tags
}

# Allow the Resource Subnet to talk to SQL Server
resource "azurerm_mssql_virtual_network_rule" "sql_vnet_rule" {
  name      = "sql-vnet-rule"
  server_id = azurerm_mssql_server.main.id
  subnet_id = azurerm_subnet.resources.id
  # Governance Tip: Use ignore_missing_vnet_service_endpoint
  ignore_missing_vnet_service_endpoint = true
}

# ==============================================================================
# Messaging Infrastructure
# Input 1: topicOrQueue
# Input 2 Governance: Service Bus Standard
# ==============================================================================

resource "azurerm_servicebus_namespace" "main" {
  # Ensure global uniqueness with a random suffix if necessary, using prefix for now
  name                = "${local.prefix}-sbns"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  # Governance: Service Bus Standard
  sku = "Standard"

  tags = local.tags
}

resource "azurerm_servicebus_queue" "notification" {
  name         = "notificationQueue"
  namespace_id = azurerm_servicebus_namespace.main.id

  enable_partitioning = true
}

# Allow the Resource Subnet to talk to Service Bus
resource "azurerm_servicebus_namespace_network_rule_set" "sb_vnet_rule" {
  namespace_id                  = azurerm_servicebus_namespace.main.id
  default_action                = "Deny"
  public_network_access_enabled = false

  network_rules {
    subnet_id = azurerm_subnet.resources.id
    # Governance Tip: Use ignore_missing_vnet_service_endpoint
    ignore_missing_vnet_service_endpoint = true
  }
}

# ==============================================================================
# Compute Fabric (Kubernetes)
# Input 1: k8s, minimumNodes: 3
# ==============================================================================

resource "azurerm_kubernetes_cluster" "main" {
  name                = "${local.prefix}-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${local.prefix}-aks"

  default_node_pool {
    name       = "default"
    # Input 1 Metadata: minimumNodes: "3"
    node_count = 3
    vm_size    = "Standard_DS2_v2"
    # Deploy into Application Subnet
    vnet_subnet_id = azurerm_subnet.application.id
  }

  # Using Azure CNI for advanced VNet integration
  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    service_cidr      = "10.0.0.0/16"
    dns_service_ip    = "10.0.0.10"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

# ==============================================================================
# Outputs
# ==============================================================================

output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "sql_server_name" {
  value = azurerm_mssql_server.main.name
  sensitive = true
}

output "sql_database_name" {
  value = azurerm_mssql_database.payment_db.name
}

output "servicebus_namespace_name" {
  value = azurerm_servicebus_namespace.main.name
}

output "servicebus_queue_name" {
  value = azurerm_servicebus_queue.notification.name
}

# Sensitive output for initial setup - in real prod this might go to KeyVault
output "sql_admin_password" {
  value     = random_password.sql_admin.result
  sensitive = true
}