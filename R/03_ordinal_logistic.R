# 03_ordinal_logistic.R
# Phase 3: ordinal logistic modeling and diagnostics
# Run from the RStudio project root. Requires package: ordinal.

if (!requireNamespace("ordinal", quietly = TRUE)) {
  stop("Please install ordinal first: install.packages('ordinal')")
}

for (p in c("results/tables", "results/models", "data/processed")) {
  dir.create(p, recursive = TRUE, showWarnings = FALSE)
}

# 1. Load preprocessed data (do not alter the raw CSV).
data_path <- "data/processed/insurance_model_data.rds"
if (!file.exists(data_path)) stop("Missing processed data: ", data_path)
df <- readRDS(data_path)
required <- c("y", "age", "sex", "bmi", "children", "smoker", "region")
stopifnot(is.data.frame(df), all(required %in% names(df)), nrow(df) == 1338L)
stopifnot(!anyNA(df[, required]))
df$y <- ordered(as.character(df$y), levels = as.character(0:8))
stopifnot(!anyNA(df$y))
for (v in c("sex", "smoker", "region")) df[[v]] <- factor(df[[v]])

# 2. Preserve the existing 70:30 split. Never silently replace old indices.
split_path <- "data/processed/ordinal_split_indices.rds"
if (!file.exists(split_path)) {
  stop("Missing saved split: ", split_path,
       "\nSave the ORIGINAL 933/405 train/validation indices first; do not resample.")
}
s <- readRDS(split_path)
train_idx <- if (!is.null(s$train)) s$train else s$train_index
valid_idx <- if (!is.null(s$validation)) s$validation else s$valid_index
if (is.null(valid_idx)) valid_idx <- s$validation_index
stopifnot(is.numeric(train_idx), is.numeric(valid_idx),
          length(train_idx) == 933L, length(valid_idx) == 405L,
          !anyDuplicated(train_idx), !anyDuplicated(valid_idx),
          setequal(c(train_idx, valid_idx), seq_len(nrow(df))),
          length(intersect(train_idx, valid_idx)) == 0L)
train_data <- df[train_idx, , drop = FALSE]
valid_data <- df[valid_idx, , drop = FALSE] # Not used for selection/diagnostics
cat("Train:", nrow(train_data), "Validation (held out):", nrow(valid_data), "\n")
print(table(train_data$y))

# 3. Models: baseline, linear interaction, spline interaction.
f_base <- y ~ age + sex + bmi + children + smoker + region
f_inter <- y ~ age + sex + bmi * smoker + children + region
f_spline <- y ~ age + sex + splines::ns(bmi, df = 3) * smoker + children + region

model_null <- ordinal::clm(y ~ 1, data = train_data, link = "logit", Hess = TRUE)
model_base <- ordinal::clm(f_base, data = train_data, link = "logit", Hess = TRUE)
model_interaction <- ordinal::clm(f_inter, data = train_data, link = "logit", Hess = TRUE)
model_spline <- ordinal::clm(f_spline, data = train_data, link = "logit", Hess = TRUE)

cat("\n--- Baseline summary ---\n"); print(summary(model_base))
cat("\n--- Linear interaction summary ---\n"); print(summary(model_interaction))
cat("\n--- Spline summary ---\n"); print(summary(model_spline))
cat("\n--- Overall LR test ---\n"); print(anova(model_null, model_base))
cat("\n--- Baseline vs interaction ---\n"); print(anova(model_base, model_interaction))
cat("\n--- Interaction vs spline ---\n"); print(anova(model_interaction, model_spline))

# 4. Baseline ORs. clm location coefficients correspond to higher-category odds.
coef_or <- function(m) {
  b <- m$beta
  V <- vcov(m)
  se <- sqrt(diag(V)[names(b)])
  z <- b / se
  data.frame(term = names(b), estimate = unname(b), SE = unname(se),
             z = unname(z), p = 2 * pnorm(abs(z), lower.tail = FALSE),
             OR = unname(exp(b)),
             OR_low_95 = unname(exp(b - qnorm(.975) * se)),
             OR_high_95 = unname(exp(b + qnorm(.975) * se)),
             row.names = NULL)
}
write.csv(coef_or(model_base), "results/tables/ordinal_baseline_OR.csv", row.names = FALSE)
write.csv(coef_or(model_interaction), "results/tables/ordinal_interaction_OR.csv", row.names = FALSE)

# BMI slope among smoker=1: combine main effect and interaction with covariance.
b <- model_interaction$beta
V <- vcov(model_interaction)
if (all(c("bmi", "bmi:smoker1") %in% names(b))) {
  nm <- c("bmi", "bmi:smoker1")
  est <- sum(b[nm])
  se <- sqrt(sum(V[nm, nm]))
  smoker_bmi <- data.frame(estimate = est, SE = se,
                           OR = exp(est), OR_low_95 = exp(est - 1.96 * se),
                           OR_high_95 = exp(est + 1.96 * se))
  print(smoker_bmi)
  write.csv(smoker_bmi, "results/tables/ordinal_smoker_BMI_effect.csv", row.names = FALSE)
}

# 5. Proportional-odds checks. Blank rows are NOT evidence of assumption validity.
po_base <- ordinal::nominal_test(model_base)
po_interaction <- ordinal::nominal_test(model_interaction)
po_spline <- ordinal::nominal_test(model_spline)
cat("\n--- PO test: baseline ---\n"); print(po_base)
cat("\n--- PO test: interaction ---\n"); print(po_interaction)
cat("\n--- PO test: spline ---\n"); print(po_spline)
saveRDS(list(base = po_base, interaction = po_interaction, spline = po_spline),
        "results/models/ordinal_PO_tests.rds")

# 6. Probability and numerical diagnostics on TRAINING data only.
train_x <- train_data[, setdiff(names(train_data), "y"), drop = FALSE]
prob_check <- function(m, name) {
  fit <- predict(m, newdata = train_x, type = "prob")$fit
  if (!is.matrix(fit) || !identical(dim(fit), c(nrow(train_x), 9L))) {
    stop(name, ": expected a 933 x 9 probability matrix")
  }
  finite <- all(is.finite(fit))
  out <- data.frame(model = name, converged = identical(m$convergence$code, 0L),
                    nonfinite = sum(!is.finite(fit)),
                    invalid = sum(fit < -1e-10 | fit > 1 + 1e-10, na.rm = TRUE),
                    min_prob = if (finite) min(fit) else NA_real_,
                    max_prob = if (finite) max(fit) else NA_real_,
                    max_rowsum_error = if (finite) max(abs(rowSums(fit) - 1)) else NA_real_)
  print(out)
  out
}
prob_diag <- do.call(rbind, list(
  prob_check(model_base, "baseline"),
  prob_check(model_interaction, "interaction"),
  prob_check(model_spline, "spline")
))
write.csv(prob_diag, "results/tables/ordinal_probability_diagnostics.csv", row.names = FALSE)

# Spline design-matrix diagnostics; scaling removes column scale but not correlations.
X <- model.matrix(~ age + sex + splines::ns(bmi, df = 3) * smoker +
                    children + region, data = train_data)
X_std <- scale(X[, -1, drop = FALSE])
H <- model_spline$Hessian
numeric_diag <- data.frame(
  matrix_rank = qr(X)$rank, matrix_columns = ncol(X),
  standardized_X_condition = kappa(X_std, exact = TRUE),
  Hessian_condition = kappa(H, exact = TRUE),
  Hessian_min_eigenvalue = min(eigen(H, symmetric = TRUE, only.values = TRUE)$values)
)
cat("\n--- Spline numerical diagnostics ---\n"); print(numeric_diag)
write.csv(numeric_diag, "results/tables/ordinal_spline_numerical_diagnostics.csv", row.names = FALSE)

# 7. Exploratory fits retained for audit; not automatically eligible for prediction.
# PPO may produce negative class probabilities even after successful convergence.
model_ppo <- ordinal::clm(y ~ age + sex + smoker + region,
                          nominal = ~ bmi + children,
                          data = train_data, link = "logit", Hess = TRUE)
train_data$children_factor <- factor(train_data$children)
model_children_factor <- ordinal::clm(
  y ~ age + sex + splines::ns(bmi, df = 3) * smoker + children_factor + region,
  data = train_data, link = "logit", Hess = TRUE)
cat("\n--- Spline vs children factor (exploratory) ---\n")
print(anova(model_spline, model_children_factor))
# PPO check: if negative probabilities appear, exclude it from predictive candidates.
ppo_x <- train_data[, setdiff(names(train_data), c("y", "children_factor")), drop = FALSE]
ppo_fit <- predict(model_ppo, newdata = ppo_x, type = "prob")$fit
ppo_invalid <- sum(!is.finite(ppo_fit) | ppo_fit < -1e-10 | ppo_fit > 1 + 1e-10)
cat("PPO invalid probabilities:", ppo_invalid, "\n")

# 8. Summary tables and model objects for Phase 4.
models <- list(baseline = model_base, interaction = model_interaction,
               spline = model_spline)
comparison <- do.call(rbind, lapply(names(models), function(nm) {
  m <- models[[nm]]
  data.frame(model = nm, logLik = as.numeric(logLik(m)),
             AIC = AIC(m), BIC = BIC(m), parameters = attr(logLik(m), "df"))
}))
print(comparison)
write.csv(comparison, "results/tables/ordinal_training_fit_comparison.csv", row.names = FALSE)
saveRDS(models, "results/models/ordinal_candidates.rds")
saveRDS(list(ppo = model_ppo, children_factor = model_children_factor),
        "results/models/ordinal_exploratory_models.rds")
cat("\nPhase 3 script completed. Validation data were not evaluated.\n")
