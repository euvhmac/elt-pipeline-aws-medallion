output "database_names" {
  description = "Map de layer => nome do database Glue"
  value       = { for k, db in aws_glue_catalog_database.this : k => db.name }
}
