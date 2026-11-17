variable "alert_email" {
  description = "Адреса для сповіщень. Передавати через TF_VAR_alert_email, не комітити."
  type        = string
}

variable "min_tasks" {
  default = 1
}

variable "max_tasks" {
  default = 4
  validation {
    condition     = var.max_tasks <= 4 && var.max_tasks >= var.min_tasks
    error_message = "За умовами лаби max_tasks <= 4 і не менше min_tasks."
  }
}

variable "cpu_target" {
  description = "Цільове середнє завантаження CPU (%) для політики масштабування"
  default     = 60
}

# ---- кеш (завдання 5) ----
variable "enable_cache" {
  description = "Створити ElastiCache Redis (платний, не Free Tier). Вмикати лише на час тестів."
  type        = bool
  default     = false
}

variable "cache_enabled" {
  description = "Чи користується застосунок кешем (для порівняння «без кешу / з кешем»)"
  type        = bool
  default     = false
}

variable "cache_ttl" {
  type    = number
  default = 30
}

variable "cache_invalidate" {
  description = "Видаляти список з кешу при POST/DELETE"
  type        = bool
  default     = false
}
