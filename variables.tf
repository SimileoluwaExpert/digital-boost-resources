variable "name" {
  type        = string
  description = "Please type in the name of your resource group"
}
variable "location" {
  type        = string
  description = "Please type in your location"
}
variable "network_address_space" {
  type        = string
  description = "Azure VNET Address Space"
}

variable "front_door_sku_name" {
  type        = string
  description = "The SKU for the Front Door profile. Possible values include: Standard_AzureFrontDoor, Premium_AzureFrontDoor"
  validation {
    condition     = contains(["Standard_AzureFrontDoor", "Premium_AzureFrontDoor"], var.front_door_sku_name)
    error_message = "The SKU value must be one of the following: Standard_AzureFrontDoor, Premium_AzureFrontDoor."
  }
}