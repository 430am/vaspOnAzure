plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
rule "terraform_documented_variables" {
  enabled = false
}
rule "terraform_documented_outputs" {
  enabled = false
}
