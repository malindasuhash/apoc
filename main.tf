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
  features {}
}

locals {
  # Governance: Approved Region from Input 2
  location = "uksouth"
  # Architecture: Project ID from Input 1
  project_id = "default"
  env        = "production"

  common_tags = {
    Environment = local.env
    Project     = local.project_id
    ManagedBy   = "Terraform"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.project_id}-${local.env}-${local.location}"
  location = local.location
  tags     = local.common_tags
}

# ==============================================================================
# Networking
# Architecture: Defined in production.deploymentRegion.virtualNetwork
# ==============================================================================

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${local.project_id}-${local.env}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  # Architecture: addressCidr: "11.1.0.0/16"
  address_space       = ["11.1.0.0/16"]
  tags                = local.common_tags
}

# Architecture: production.deploymentRegion.virtualNetwork.applicationSubnet
resource "azurerm_subnet" "app_subnet" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  # Carving out a subnet from the VNet CIDR
  address_prefixes     = ["11.1.1.0/24"]

  # Governance: Enable service endpoints required for PaaS connectivity
  service_endpoints    = ["Microsoft.Sql", "Microsoft.ServiceBus"]
}

# Architecture: production.deploymentRegion.virtualNetwork.resourceSubnet
# Note: While the architecture places DB/Queue logically here, Azure PaaS services 
# often live outside the subnet but are secured *by* subnet rules. 
# We define this subnet for potential future resources or Private Endpoint integration.
resource "azurerm_subnet" "resource_subnet" {
  name                 = "snet-resources"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  # Carving out a subnet from the VNet CIDR
  address_prefixes     = ["11.1.2.0/24"]
}

# ==============================================================================
# Database (Azure SQL)
# Architecture: production.deploymentRegion.virtualNetwork.resourceSubnet.paymentDB
# Governance: "Azure SQL Server Standard"
# ==============================================================================

resource "random_password" "sql_admin" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_mssql_server" "sql_server" {
  name                         = "sql-${local.project_id}-${local.env}-${random_string.suffix.result}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = random_password.sql_admin.result
  minimum_tls_version          = "1.2"

  tags = local.common_tags
}

resource "azurerm_mssql_database" "payment_db" {
  name      = "paymentDB"
  server_id = azurerm_mssql_server.sql_server.id
  
  # Governance: "Azure SQL Server Standard". Mapping to a production Standard SKU.
  sku_name  = "S1" 
  
  tags = local.common_tags
}

# Allow AKS subnet to access SQL Server
resource "azurerm_mssql_virtual_network_rule" "sql_vnet_rule" {
  name      = "allow-app-subnet"
  server_id = azurerm_mssql_server.sql_server.id
  subnet_id = azurerm_subnet.app_subnet.id

  # Governance Tip: "Use ignore_missing_vnet_service_endpoint"
  ignore_missing_vnet_service_endpoint = true
}

# ==============================================================================
# Messaging (Service Bus)
# Architecture: production.deploymentRegion.virtualNetwork.resourceSubnet.notificationQueue
# Governance: "Service Bus Standard"
# ==============================================================================

resource "azurerm_servicebus_namespace" "sb_namespace" {
  name                = "sb-${local.project_id}-${local.env}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Governance: "Service Bus Standard"
  sku                 = "Standard"

  tags = local.common_tags
}

resource "azurerm_servicebus_queue" "notification_queue" {
  name         = "notificationQueue"
  namespace_id = azurerm_servicebus_namespace.sb_namespace.id

  enable_partitioning = true
}

# Allow AKS subnet to access Service Bus
resource "azurerm_servicebus_namespace_network_rule_set" "sb_vnet_rule" {
  namespace_id = azurerm_servicebus_namespace.sb_namespace.id
  default_action = "Deny"
  public_network_access_enabled = false

  network_rules {
    subnet_id = azurerm_subnet.app_subnet.id
    # Governance Tip: "Use ignore_missing_vnet_service_endpoint"
    ignore_missing_vnet_service_endpoint = true
  }
}

# ==============================================================================
# Compute (AKS)
# Architecture: ...applicationSubnet.deploymentFabric (Kubernetes cluster)
# Architecture Metadata: minimumNodes: "3"
# ==============================================================================

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-${local.project_id}-${local.env}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "aks-${local.project_id}-${local.env}"

  default_node_pool {
    name       = "default"
    node_count = 3 # Architecture requirement
    vm_size    = "Standard_D2s_v3" # Production baseline
    
    # Architecture: Placement in applicationSubnet
    vnet_subnet_id = azurerm_subnet.app_subnet.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    service_cidr      = "10.0.0.0/16"
    dns_service_ip    = "10.0.0.10"
  }

  tags = local.common_tags
}

# Random suffix for globally unique resource names (SQL, SB)
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}