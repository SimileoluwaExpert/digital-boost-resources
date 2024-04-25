resource "azurerm_resource_group" "resource-group" {
  name     = "${var.name}-rg"
  location = var.location
}

resource "azurerm_storage_account" "storageaccount" {
  name                     = "${var.name}-storageaccount"
  resource_group_name      = azurerm_resource_group.resource-group.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_virtual_network" "virtual_network" {
  name                = "${var.name}-vnet"
  location            = var.location
  resource_group_name = azurerm_resource_group.resource-group.name
  address_space       = [var.network_address_space]
}

resource "azurerm_subnet" "subnet_str" {
  address_prefixes     = ["10.0.1.0/24"]
  name                 = "${var.name}-appsubnet"
  resource_group_name  = azurerm_resource_group.resource-group.name
  virtual_network_name = azurerm_virtual_network.virtual_network.name
  service_endpoints    = ["Microsoft.Storage"]

}

resource "azurerm_subnet" "subnet_db" {
  address_prefixes     = ["10.0.2.0/24"]
  name                 = "${var.name}-appsubnet"
  resource_group_name  = azurerm_resource_group.resource-group.name
  virtual_network_name = azurerm_virtual_network.virtual_network.name
  service_endpoints    = ["Microsoft.Storage"]

  delegation {
    name = "${var.name}-delegation"

    service_delegation {
      name = "Microsoft.DBforMySQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}


resource "azurerm_dns_zone" "dns_zone" {
  name                = "sub-domain.digital-boost.com"
  resource_group_name = azurerm_resource_group.resource-group.name
}

resource "azurerm_private_endpoint" "private_endpoint" {
  name                = "${var.name}-private_endpoint"
  location            = var.location
  resource_group_name = azurerm_resource_group.resource-group.name
  subnet_id           = "${var.name}-appsubnet"

  private_service_connection {
    name                           = "${var.name}-private_sc"
    private_connection_resource_id = azurerm_storage_account.storageaccount.id
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "${var.name}-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.private_endpoint.id]
  }
}

resource "azurerm_private_dns_zone" "private_dns_zone" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.resource-group.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "net_lnk" {
  name                  = "${var.name}-link"
  resource_group_name   = azurerm_resource_group.resource-group.name
  private_dns_zone_name = azurerm_private_dns_zone.private_dns_zone.name
  virtual_network_id    = azurerm_virtual_network.virtual_network.id
}

resource "azurerm_cdn_frontdoor_profile" "front_door" {
  name                = "${var.name}-front"
  resource_group_name = azurerm_resource_group.resource-group.name
  sku_name            = var.front_door_sku_name
}

resource "azurerm_cdn_frontdoor_endpoint" "my_endpoint" {
  name                     = "${var.name}-front_door_endpoint_name"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.front_door.id
}

resource "azurerm_cdn_frontdoor_origin_group" "origin_group" {
  name                     = "${var.name}-front_door_origin_group_name"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.front_door.id
  session_affinity_enabled = true

  load_balancing {
    sample_size                 = 3
    successful_samples_required = 2
  }

  health_probe {
    path                = "/"
    request_type        = "HEAD"
    protocol            = "Https"
    interval_in_seconds = 100
  }
}

resource "azurerm_cdn_frontdoor_origin" "my_app_service_origin" {
  name                          = "${var.name}-front_door_origin_name"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.origin_group.id

  enabled                        = true
  host_name                      = azurerm_linux_web_app.web_app.default_hostname
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = azurerm_linux_web_app.web_app.default_hostname
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true
}


resource "azurerm_cdn_frontdoor_firewall_policy" "firewall_policy" {
  name                              = "${var.name}-firewall_policy"
  resource_group_name               = azurerm_resource_group.resource-group.name
  sku_name                          = azurerm_cdn_frontdoor_profile.front_door.sku_name
  enabled                           = true
  mode                              = "Prevention"
  redirect_url                      = "https://www.digital-boost.com"
  custom_block_response_status_code = 403
  custom_block_response_body        = local.response_body

  custom_rule {
    name                           = "${var.name}-rule-1"
    enabled                        = true
    priority                       = 1
    rate_limit_duration_in_minutes = 1
    rate_limit_threshold           = 10
    type                           = "MatchRule"
    action                         = "Block"

    match_condition {
      match_variable     = "RemoteAddr"
      operator           = "IPMatch"
      negation_condition = false
      match_values       = ["10.0.1.0/24", "10.0.0.0/24"]
    }
  }
}

resource "azurerm_service_plan" "app_plan" {
  name                = "${var.name}-asp"
  resource_group_name = azurerm_resource_group.resource-group.name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "P1v2"
}

resource "azurerm_linux_web_app" "web_app" {
  name                = "${var.name}-app"
  resource_group_name = azurerm_resource_group.resource-group.name
  location            = var.location
  service_plan_id     = azurerm_service_plan.app_plan.id

  site_config {
    ftps_state          = "Disabled"
    minimum_tls_version = "1.2"
    ip_restriction {
      service_tag               = "AzureFrontDoor.Backend"
      ip_address                = null
      virtual_network_subnet_id = null
      action                    = "Allow"
      priority                  = 100
      headers {
        x_azure_fdid      = [azurerm_cdn_frontdoor_profile.front_door.resource_guid]
        x_fd_health_probe = []
        x_forwarded_for   = []
        x_forwarded_host  = []
      }
      name = "Allow traffic from Front Door"

    }
  }
}

resource "azurerm_mysql_flexible_server" "db_server" {
  name                         = "${var.name}-flexible-server"
  resource_group_name          = azurerm_resource_group.resource-group.name
  location                     = var.location
  administrator_login          = local.admin
  administrator_password       = local.password
  backup_retention_days        = 7
  delegated_subnet_id          = azurerm_subnet.subnet_str.id
  geo_redundant_backup_enabled = false
  private_dns_zone_id          = azurerm_private_dns_zone.private_dns_zone.id
  sku_name                     = local.db_sku
  high_availability {
    mode = "SameZone"
  }
  maintenance_window {
    day_of_week  = 0
    start_hour   = 8
    start_minute = 0
  }
  storage {
    iops    = 360
    size_gb = 20
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.net_lnk]
}


resource "azurerm_mysql_flexible_server_firewall_rule" "db_firewall" {
  name                = "${var.name}-flexible-server-firewall"
  resource_group_name = azurerm_resource_group.resource-group.name
  server_name         = azurerm_mysql_flexible_server.db_server.name
  start_ip_address    = local.ip_address
  end_ip_address      = local.ip_address
}

resource "azurerm_mysql_flexible_database" "mysql_database" {
  name                = "${var.name}-flexible-db"
  resource_group_name = azurerm_resource_group.resource-group.name
  server_name         = azurerm_mysql_flexible_server.db_server.name
  charset             = "utf8"
  collation           = "utf8_unicode_ci"
}

