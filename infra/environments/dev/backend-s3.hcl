bucket                      = "atlas-tf-7612"
key                         = "terraform/atlas-idp/terraform.tfstate"
region                      = "eu-central-003"
endpoints = {
  s3 = "https://s3.eu-central-003.backblazeb2.com"
}
skip_credentials_validation = true
skip_metadata_api_check     = true
skip_region_validation      = true
skip_requesting_account_id  = true
