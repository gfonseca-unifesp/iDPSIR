# =====================================================
# DPSIR RESPONSE SIMULATION (schema-aware)
# =====================================================
#
# Adaptado de R/dpsir/core_dpsir_responses.R (preservado, nao sourceado)
# mais find_response_targets, que vivia em R/dpsir/core_dpsir_pathways.R
# (superado por R/pathways.R na Fase 2, mas essa funcao especifica de
# Response nao foi migrada la). Categoria "Response" fixa vira
# get_feedback_categories(schema) (role == "feedback"), no mesmo padrao
# ja usado em R/pathways.R.

get_feedback_categories <- function(schema) {
  validate_schema(schema)
  schema$name[!is.na(schema$role) & schema$role == "feedback"]
}
