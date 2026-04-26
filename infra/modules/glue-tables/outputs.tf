output "table_names" {
  description = "Map <datamart>__<table> -> nome registrado no Glue."
  value       = { for k, t in aws_glue_catalog_table.this : k => t.name }
}

output "table_count" {
  description = "Quantidade de tabelas criadas."
  value       = length(aws_glue_catalog_table.this)
}
