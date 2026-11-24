# ============================================================
# 05_binary_logistic.R
# Phase 5: Binary Logistic Regression
# Target: Highest Medical Cost Level (y = 8)
# ============================================================

# Set TRUE only after model and threshold are approved.
RUN_FINAL_VALIDATION <- TRUE
packages <- c("detectseparation", "logistf", "pROC", "PRROC")
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) stop("Install packages: ", paste(missing, collapse = ", "))
if (!file.exists("data/processed/insurance_model_data.rds")) stop("Run from the project root.")
# 1. 数据读取与检查 -------------------------------------------

data_path <- "data/processed/insurance_model_data.rds"

df <- readRDS(data_path)

required_vars <- c(
  "y", "age", "sex", "bmi",
  "children", "smoker", "region"
)

stopifnot(
  all(required_vars %in% names(df)),
  nrow(df) == 1338,
  !anyNA(df[, required_vars])
)

# 设置分类变量
df$sex <- factor(df$sex)
df$smoker <- factor(df$smoker)
df$region <- factor(df$region)

# 构造二分类目标
# 注意：原始 y 为有序因子，不能直接 as.numeric(y)
df$y_binary <- as.integer(as.character(df$y) == "8")

stopifnot(
  all(df$y_binary %in% c(0, 1)),
  sum(df$y_binary) == 113
)


# 2. 目标变量分布 ---------------------------------------------

cat("\n========== Binary Target Distribution ==========\n")

print(table(df$y_binary))
print(round(prop.table(table(df$y_binary)), 4))

cat("\nSmoking Status vs Binary Target:\n")

print(table(
  Smoker = df$smoker,
  Target = df$y_binary
))


# 3. 分层随机划分 ---------------------------------------------

set.seed(42)

split_path <- "data/processed/binary_split_indices.rds"

# 如果已有划分索引，则直接复用
if (file.exists(split_path)) {
  
  binary_split <- readRDS(split_path)
  
} else {
  
  train_idx <- integer(0)
  test_idx <- integer(0)
  valid_idx <- integer(0)
  
  for (class in c(0, 1)) {
    
    idx <- which(df$y_binary == class)
    idx <- sample(idx)
    
    n <- length(idx)
    
    n_train <- round(n * 0.70)
    n_test <- round(n * 0.15)
    
    train_idx <- c(
      train_idx,
      idx[seq_len(n_train)]
    )
    
    test_idx <- c(
      test_idx,
      idx[seq.int(
        n_train + 1,
        n_train + n_test
      )]
    )
    
    valid_idx <- c(
      valid_idx,
      idx[seq.int(
        n_train + n_test + 1,
        n
      )]
    )
  }
  
  binary_split <- list(
    train = sort(train_idx),
    test = sort(test_idx),
    validation = sort(valid_idx)
  )
  
  saveRDS(binary_split, split_path)
}


# 4. 验证数据划分 ---------------------------------------------

all_idx <- unlist(
  binary_split,
  use.names = FALSE
)

stopifnot(
  length(all_idx) == nrow(df),
  !anyDuplicated(all_idx),
  setequal(all_idx, seq_len(nrow(df)))
)

train_data <- df[
  binary_split$train, ,
  drop = FALSE
]

test_data <- df[
  binary_split$test, ,
  drop = FALSE
]

valid_data <- df[
  binary_split$validation, ,
  drop = FALSE
]


# 5. 数据划分统计 ---------------------------------------------

split_summary <- function(data, name) {
  
  data.frame(
    dataset = name,
    n = nrow(data),
    negative = sum(data$y_binary == 0),
    positive = sum(data$y_binary == 1),
    positive_rate = mean(data$y_binary)
  )
}

split_results <- rbind(
  split_summary(train_data, "Training"),
  split_summary(test_data, "Testing"),
  split_summary(valid_data, "Validation")
)

cat("\n========== Binary Data Split ==========\n")

print(split_results)

cat("\nTraining Smoking vs Binary Target:\n")

print(table(
  Smoker = train_data$smoker,
  Target = train_data$y_binary
))

cat("\nData split verification passed.\n")


# 6. 保存划分统计 ---------------------------------------------

dir.create(
  "results/tables",
  recursive = TRUE,
  showWarnings = FALSE
)

write.csv(
  split_results,
  "results/tables/binary_split_summary.csv",
  row.names = FALSE
)

cat("\n========== Data Preparation Completed ==========\n")

# 7. 基础二分类 Logistic 回归 ---------------------------------

cat("\n========== Baseline Binary Logistic ==========\n")

binary_formula <- y_binary ~ age + sex + bmi +
  children + smoker + region

model_binary_base <- glm(
  formula = binary_formula,
  data = train_data,
  family = binomial(link = "logit"),
  control = glm.control(maxit = 100)
)

# 模型参数估计与显著性检验
print(summary(model_binary_base))


# 8. 模型整体显著性检验 ---------------------------------------

model_binary_null <- glm(
  y_binary ~ 1,
  data = train_data,
  family = binomial(link = "logit")
)

cat("\n========== Overall LR Test ==========\n")

print(anova(
  model_binary_null,
  model_binary_base,
  test = "Chisq"
))


# 9. 数值稳定性检查 -------------------------------------------

cat("\n========== Numerical Diagnostics ==========\n")

cat("Converged:", model_binary_base$converged, "\n")

cat("Iterations:", model_binary_base$iter, "\n")

cat("\nCoefficient Estimates:\n")
print(coef(model_binary_base))

cat("\nStandard Errors:\n")
print(sqrt(diag(vcov(model_binary_base))))

cat("\nFitted Probability Range:\n")
print(range(fitted(model_binary_base)))

cat("\nNear-zero Probabilities:\n")
print(sum(fitted(model_binary_base) < 1e-8))

cat("\nNear-one Probabilities:\n")
print(sum(fitted(model_binary_base) > 1 - 1e-8))

cat("\n========== Separation Detection ==========\n")

separation_result <- glm(
  formula = binary_formula,
  data = train_data,
  family = binomial(link = "logit"),
  method = detectseparation::detect_separation
)

print(separation_result)
# 16. 数值稳定性预处理 ---------------------------------------

# 中心化参数仅从训练集计算
age_center <- mean(train_data$age)
bmi_center <- mean(train_data$bmi)

center_data <- function(data) {
  data$age_c <- data$age - age_center
  data$bmi_c <- data$bmi - bmi_center
  data
}

train_centered <- center_data(train_data)


# 17. 设置 Firth 优化控制参数 --------------------------------

firth_control <- logistf::logistf.control(
  maxit = 1000,
  maxstep = 1,
  lconv = 1e-7,
  gconv = 1e-5,
  xconv = 1e-5
)


# Candidate formulas: all transformations use training means.
formulas <- list(
  baseline = y_binary ~ age_c + sex + bmi_c + children + smoker + region,
  interaction = y_binary ~ age_c + sex + bmi_c * smoker + children + region,
  spline = y_binary ~ age_c + sex + splines::ns(bmi_c, df = 3) * smoker + children + region,
  quadratic = y_binary ~ age_c + I(age_c^2) + sex + bmi_c + I(bmi_c^2) + children + smoker + region
)
fit_firth <- function(f, profile = FALSE) {
  logistf::logistf(formula = f, data = train_centered, firth = TRUE,
                   pl = profile, control = firth_control)
}
firth_models <- lapply(formulas, fit_firth)
diagnostic_results <- data.frame()

for (model_name in names(firth_models)) {
  
  fit <- firth_models[[model_name]]
  
  prob <- predict(
    fit,
    newdata = train_centered,
    type = "response"
  )
  
  conv <- abs(fit$conv)
  
  converged <- (
    length(conv) == 3 &&
      all(is.finite(conv)) &&
      conv[1] <= 1e-7 &&
      conv[2] <= 1e-5 &&
      conv[3] <= 1e-5
  )
  
  result <- data.frame(
    model = model_name,
    parameters = length(coef(fit)),
    iterations = fit$iter[1],
    converged = converged,
    finite_coefficients = all(is.finite(coef(fit))),
    max_score = conv[2],
    beta_change = conv[3],
    min_prob = min(prob),
    max_prob = max(prob),
    invalid_prob = sum(
      !is.finite(prob) | prob < 0 | prob > 1
    )
  )
  
  diagnostic_results <- rbind(
    diagnostic_results,
    result
  )
  
  cat("\n==========", model_name, "==========\n")
  
  cat("Convergence criteria:\n")
  print(fit$conv)
  
  cat("Iterations:\n")
  print(fit$iter)
  
  cat("Coefficients:\n")
  print(coef(fit))
  
  cat("Standard errors:\n")
  print(sqrt(diag(vcov(fit))))
}


# 20. 汇总诊断结果 -------------------------------------------

cat("\n========== Model Diagnostics Summary ==========\n")

print(diagnostic_results, row.names = FALSE)

cat("\n========== Candidate Models Completed ==========\n")

# Exclude failed candidates before test-set evaluation.
eligible <- with(diagnostic_results, model[converged & finite_coefficients & invalid_prob == 0])
if (!length(eligible)) stop("No numerically valid candidate.")
write.csv(diagnostic_results, "results/tables/binary_model_diagnostics.csv", row.names = FALSE)
if ("quadratic" %in% eligible) {
  model_firth_quadratic <- firth_models$quadratic
cat("\n========== Quadratic Term Diagnostics ==========\n")

print(model_firth_quadratic$conv)

quadratic_terms <- c(
  "I(age_c^2)",
  "I(bmi_c^2)"
)

quad_beta <- coef(model_firth_quadratic)[quadratic_terms]

quad_se <- sqrt(
  diag(vcov(model_firth_quadratic))
)[quadratic_terms]

quad_z <- quad_beta / quad_se

quadratic_diagnostics <- data.frame(
  variable = quadratic_terms,
  estimate = as.numeric(quad_beta),
  std_error = as.numeric(quad_se),
  z_value = as.numeric(quad_z),
  p_value = as.numeric(
    2 * pnorm(-abs(quad_z))
  )
)

print(quadratic_diagnostics)

  write.csv(quadratic_diagnostics, "results/tables/binary_linearity_diagnostics.csv", row.names = FALSE)
}
firth_models <- firth_models[eligible]
# 22. 检验集预处理 ------------------------------------------

# 使用训练集的中心化参数
test_centered <- center_data(test_data)

# 确保真实标签为 0 和 1
test_actual <- as.integer(
  as.character(test_centered$y_binary)
)

stopifnot(
  all(test_actual %in% c(0, 1)),
  length(unique(test_actual)) == 2
)

cat("\n========== Testing Set ==========\n")

cat("Samples:", nrow(test_centered), "\n")
cat("Positive samples:", sum(test_actual == 1), "\n")
cat("Positive rate:", mean(test_actual), "\n")


# 23. 定义概率评价函数 --------------------------------------

evaluate_binary <- function(actual, prob) {
  
  stopifnot(
    length(actual) == length(prob),
    all(is.finite(prob)),
    all(prob >= 0 & prob <= 1)
  )
  
  # ROC-AUC
  roc_obj <- pROC::roc(
    response = actual,
    predictor = prob,
    levels = c(0, 1),
    direction = "<",
    quiet = TRUE
  )
  
  roc_auc <- as.numeric(pROC::auc(roc_obj))
  
  # PR-AUC
  pr_obj <- PRROC::pr.curve(
    scores.class0 = prob[actual == 1],
    scores.class1 = prob[actual == 0],
    curve = FALSE
  )
  
  pr_auc <- pr_obj$auc.integral
  
  # 避免 log(0)
  eps <- 1e-15
  prob_safe <- pmin(pmax(prob, eps), 1 - eps)
  
  # Log Loss
  log_loss <- -mean(
    actual * log(prob_safe) +
      (1 - actual) * log(1 - prob_safe)
  )
  
  # Brier Score
  brier_score <- mean((actual - prob)^2)
  
  data.frame(
    roc_auc = roc_auc,
    pr_auc = pr_auc,
    log_loss = log_loss,
    brier_score = brier_score
  )
}


# 24. 检验集模型比较 ----------------------------------------

cat("\n========== Testing Set Model Comparison ==========\n")

binary_comparison <- data.frame()

test_predictions <- list()

for (model_name in names(firth_models)) {
  
  fit <- firth_models[[model_name]]
  
  prob <- predict(
    fit,
    newdata = test_centered,
    type = "response"
  )
  
  prob <- as.numeric(prob)
  
  test_predictions[[model_name]] <- prob
  
  metrics <- evaluate_binary(
    actual = test_actual,
    prob = prob
  )
  
  result <- data.frame(
    model = model_name,
    parameters = length(coef(fit)),
    metrics
  )
  
  binary_comparison <- rbind(
    binary_comparison,
    result
  )
}


# 25. 输出模型比较结果 --------------------------------------

binary_comparison <- binary_comparison[
  order(-binary_comparison$pr_auc),
]

rownames(binary_comparison) <- NULL

print(binary_comparison, digits = 6)


# 26. 保存模型比较结果 --------------------------------------

dir.create(
  "results/tables",
  recursive = TRUE,
  showWarnings = FALSE
)

write.csv(
  binary_comparison,
  "results/tables/binary_model_comparison.csv",
  row.names = FALSE
)

cat("\n========== Model Comparison Completed ==========\n")

cat("Final validation set has not been evaluated.\n")

# Exploratory parsimony rule: retain candidates within 0.005 PR-AUC
# and 0.005 log loss of the respective best; choose fewest parameters.
# If no candidate meets both tolerances, prioritize PR-AUC then log loss.
# 综合统计诊断与检验集预测表现
# 优先考虑 PR-AUC，其次考虑 Log Loss
# 指标相同时优先选择参数较少的模型

selection_results <- binary_comparison[
  order(
    -binary_comparison$pr_auc,
    binary_comparison$log_loss,
    binary_comparison$parameters
  ),
  ,
  drop = FALSE
]

selected_model_name <- as.character(
  selection_results$model[1]
)
model_binary_final <- firth_models[[selected_model_name]]

selected_test_prob <- test_predictions[[selected_model_name]]

cat("\n========== Selected Binary Model ==========\n")
cat("Selected model:", selected_model_name, "\n")


# 28. 定义分类评价函数 ---------------------------------------

evaluate_classification <- function(actual, prob, threshold) {
  
  predicted <- as.integer(prob >= threshold)
  
  TP <- sum(actual == 1 & predicted == 1)
  TN <- sum(actual == 0 & predicted == 0)
  FP <- sum(actual == 0 & predicted == 1)
  FN <- sum(actual == 1 & predicted == 0)
  
  safe_divide <- function(a, b) {
    if (b == 0) return(0)
    a / b
  }
  
  accuracy <- (TP + TN) / length(actual)
  
  precision <- safe_divide(TP, TP + FP)
  recall <- safe_divide(TP, TP + FN)
  specificity <- safe_divide(TN, TN + FP)
  
  f1 <- safe_divide(
    2 * precision * recall,
    precision + recall
  )
  
  data.frame(
    threshold = threshold,
    accuracy = accuracy,
    precision = precision,
    recall = recall,
    specificity = specificity,
    f1 = f1,
    youden = recall + specificity - 1,
    TP = TP,
    TN = TN,
    FP = FP,
    FN = FN
  )
}


# 29. 搜索分类阈值 -------------------------------------------

# 使用检验集的实际预测概率作为候选阈值
# 避免固定步长搜索遗漏最优分类结果

threshold_grid <- sort(unique(
  c(0, selected_test_prob, 0.5, 1)
))

threshold_results <- do.call(
  rbind,
  lapply(
    threshold_grid,
    function(t) {
      evaluate_classification(
        actual = test_actual,
        prob = selected_test_prob,
        threshold = t
      )
    }
  )
)


# 30. 确定三种阈值策略 ---------------------------------------

# 默认阈值
default_result <- evaluate_classification(
  test_actual,
  selected_test_prob,
  threshold = 0.5
)

# Youden 最优阈值
# 并列时优先选择召回率更高的方案
youden_result <- threshold_results[
  order(
    -threshold_results$youden,
    -threshold_results$recall,
    -threshold_results$threshold
  ),
][1, ]

# F1 最优阈值
# 并列时优先选择召回率更高的方案
f1_result <- threshold_results[
  order(
    -threshold_results$f1,
    -threshold_results$recall,
    -threshold_results$threshold
  ),
][1, ]


# 31. 汇总阈值比较结果 ---------------------------------------

threshold_comparison <- rbind(
  data.frame(
    strategy = "Default",
    default_result
  ),
  data.frame(
    strategy = "Youden",
    youden_result
  ),
  data.frame(
    strategy = "Max_F1",
    f1_result
  )
)

rownames(threshold_comparison) <- NULL

cat("\n========== Threshold Comparison ==========\n")

print(
  threshold_comparison,
  digits = 6,
  row.names = FALSE
)


# 32. 锁定最终分类阈值 ---------------------------------------

selected_threshold <- f1_result$threshold

cat("\n========== Selected Threshold ==========\n")

cat("Strategy: Max F1\n")
cat("Threshold:", selected_threshold, "\n")


# 33. 保存阈值优化结果 ---------------------------------------

write.csv(
  threshold_results,
  "results/tables/binary_threshold_search.csv",
  row.names = FALSE
)

write.csv(
  threshold_comparison,
  "results/tables/binary_threshold_comparison.csv",
  row.names = FALSE
)

cat("\n========== Threshold Optimization Completed ==========\n")

cat("Final validation set has not been evaluated.\n")

# Profile penalized likelihood inference for selected model.
model_firth <- fit_firth(formulas[[selected_model_name]], profile = TRUE)
print(summary(model_firth))
if (!isTRUE(all.equal(unname(coef(model_firth)), unname(coef(model_binary_final)), tolerance = 1e-6))) stop("Profile refit differs from selected fit.")
firth_coef <- data.frame(
  variable = names(coef(model_firth)),
  estimate = unname(coef(model_firth)),
  std_error = sqrt(diag(model_firth$var)),
  p_value = model_firth$prob,
  CI_lower = model_firth$ci.lower,
  CI_upper = model_firth$ci.upper,
  OR = exp(coef(model_firth)),
  OR_lower = exp(model_firth$ci.lower),
  OR_upper = exp(model_firth$ci.upper),
  row.names = NULL
)

cat("\n========== Firth Coefficients and OR ==========\n")

print(firth_coef, digits = 5)
write.csv(
  firth_coef,
  "results/tables/binary_firth_coefficients.csv",
  row.names = FALSE
)

# Baseline MLE versus Firth comparison on the same uncentered scale.
base_firth <- logistf::logistf(binary_formula, data = train_data, firth = TRUE, pl = FALSE, control = firth_control)
coef_comparison <- data.frame(variable = names(coef(model_binary_base)),
 MLE_estimate = unname(coef(model_binary_base)), MLE_SE = sqrt(diag(vcov(model_binary_base))),
 Firth_estimate = unname(coef(base_firth)), Firth_SE = sqrt(diag(base_firth$var)))
write.csv(coef_comparison, "results/tables/binary_mle_vs_firth.csv", row.names = FALSE)
# 34. 最终模型设计矩阵诊断 ----------------------------------

cat("\n========== Final Model Collinearity ==========\n")

X_binary <- model.matrix(formulas[[selected_model_name]], data = train_centered)
X_binary_scaled <- scale(
  X_binary[, -1, drop = FALSE]
)

cat("Matrix rank:", qr(X_binary)$rank, "\n")
cat("Matrix columns:", ncol(X_binary), "\n")

cat(
  "Standardized condition number:",
  kappa(X_binary_scaled, exact = TRUE),
  "\n"
)

# 计算各设计矩阵列的 VIF
binary_vif <- diag(
  solve(cor(X_binary_scaled))
)

print(binary_vif)
# 36. Pearson 残差诊断 --------------------------------------

cat("\n========== Pearson Residual Diagnostics ==========\n")

train_actual <- as.integer(
  as.character(train_centered$y_binary)
)

train_prob <- as.numeric(
  predict(
    model_binary_final,
    newdata = train_centered,
    type = "response"
  )
)

prob_safe <- pmin(
  pmax(train_prob, 1e-15),
  1 - 1e-15
)

pearson_residuals <- (
  train_actual - prob_safe
) / sqrt(prob_safe * (1 - prob_safe))

print(summary(pearson_residuals))

cat(
  "Absolute Pearson residual > 2:",
  sum(abs(pearson_residuals) > 2),
  "\n"
)

cat(
  "Absolute Pearson residual > 3:",
  sum(abs(pearson_residuals) > 3),
  "\n"
)


# 37. 检查残差最大的观测 -------------------------------------

residual_order <- head(
  order(abs(pearson_residuals), decreasing = TRUE),
  10
)

residual_diagnostics <- data.frame(
  observation = residual_order,
  actual = train_actual[residual_order],
  probability = train_prob[residual_order],
  pearson_residual = pearson_residuals[residual_order]
)

cat("\n========== Largest Pearson Residuals ==========\n")

print(residual_diagnostics)


# 38. 杠杆值与潜在影响点筛查 ---------------------------------

cat("\n========== Leverage Diagnostics ==========\n")

W <- train_prob * (1 - train_prob)

X_weighted <- X_binary * sqrt(W)

information_matrix <- crossprod(X_weighted)

# QR-based weighted leverage avoids explicit matrix inversion.
q <- qr(X_weighted)
if (q$rank != ncol(X_weighted)) stop("Weighted design is rank deficient.")
leverage <- rowSums(qr.Q(q)^2)
leverage_cutoff <- 2 * ncol(X_binary) / nrow(X_binary)

cat("Leverage cutoff:", leverage_cutoff, "\n")

cat(
  "High leverage observations:",
  sum(leverage > leverage_cutoff),
  "\n"
)

print(summary(leverage))

influence_screen <- data.frame(
  observation = seq_len(nrow(train_centered)),
  original_row = binary_split$train,
  actual = train_actual,
  probability = train_prob,
  pearson_residual = pearson_residuals,
  leverage = leverage
)

# 同时具有较大残差和较高杠杆值的观测
potential_influence <- subset(
  influence_screen,
  abs(pearson_residual) > 2 &
    leverage > leverage_cutoff
)

cat("\nPotential influential observations:\n")

print(potential_influence)


write.csv(
  influence_screen,
  "results/tables/binary_residual_diagnostics.csv",
  row.names = FALSE
)

cat("\n========== Final Model Diagnostics Completed ==========\n")

cat("Final validation set has not been evaluated.\n")

# Save the locked model and preprocessing parameters.
dir.create("results/models", recursive = TRUE, showWarnings = FALSE)
saveRDS(list(model = model_binary_final, name = selected_model_name,
  threshold = selected_threshold, age_center = age_center, bmi_center = bmi_center),
  "results/models/binary_final_model.rds")
if (RUN_FINAL_VALIDATION) {
  valid_centered <- center_data(valid_data)
  actual <- valid_centered$y_binary
  prob <- as.numeric(predict(model_binary_final, newdata = valid_centered, type = "response"))
  metrics <- cbind(evaluate_binary(actual, prob), evaluate_classification(actual, prob, selected_threshold))
  predicted <- as.integer(prob >= selected_threshold)
  cm <- table(Actual = factor(actual, levels = 0:1), Predicted = factor(predicted, levels = 0:1))
  print(metrics); print(cm)
  write.csv(metrics, "results/tables/binary_validation_metrics.csv", row.names = FALSE)
  write.csv(as.data.frame.matrix(cm), "results/tables/binary_validation_confusion.csv")
  write.csv(data.frame(actual, prob, predicted), "results/tables/binary_validation_predictions.csv", row.names = FALSE)
} else cat("Final validation is disabled.\n")
cat("Phase 5 script completed.\n")
