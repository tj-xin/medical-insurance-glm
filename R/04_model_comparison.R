
# ============================================================
# Phase 4: Model Comparison and Prediction Evaluation
# Medical Insurance Cost Level Prediction
# ============================================================


# ============================================================
# 1. Environment Setup
# ============================================================

library(ordinal)
library(splines)
library(ggplot2)

set.seed(2026)

classes <- as.character(0:8)
K <- 5

dir.create("data/processed", recursive = TRUE,
           showWarnings = FALSE)

dir.create("results/tables", recursive = TRUE,
           showWarnings = FALSE)

dir.create("results/figures", recursive = TRUE,
           showWarnings = FALSE)

dir.create("results/models", recursive = TRUE,
           showWarnings = FALSE)


# ============================================================
# 2. Load Data and Restore Original Split
# ============================================================

model_data <- readRDS(
  "data/processed/insurance_model_data.rds"
)

split_indices <- readRDS(
  "data/processed/ordinal_split_indices.rds"
)

# 检查原始划分索引
all_indices <- c(
  split_indices$train,
  split_indices$validation
)

stopifnot(
  length(all_indices) == nrow(model_data),
  !anyDuplicated(all_indices),
  setequal(all_indices, seq_len(nrow(model_data)))
)

# 恢复 Phase 3 的训练集
train_data <- model_data[
  split_indices$train, , drop = FALSE
]

stopifnot(
  nrow(train_data) == 933,
  length(split_indices$validation) == 405,
  is.ordered(train_data$y),
  identical(levels(train_data$y), classes),
  !anyNA(train_data)
)

cat("\n========== Data Verification ==========\n")

cat("Training samples:", nrow(train_data), "\n")
cat("Held-out validation samples:",
    length(split_indices$validation), "\n")

cat("Data split verification passed.\n")


# ============================================================
# 3. Evaluation Metrics
# ============================================================

evaluate_ordinal <- function(actual, predicted) {
  
  actual <- as.integer(as.character(actual))
  predicted <- as.integer(as.character(predicted))
  
  stopifnot(
    length(actual) == length(predicted),
    length(actual) > 0,
    !anyNA(actual),
    !anyNA(predicted),
    all(actual %in% 0:8),
    all(predicted %in% 0:8)
  )
  
  # 混淆矩阵
  cm <- table(
    Actual = factor(actual, levels = 0:8),
    Predicted = factor(predicted, levels = 0:8)
  )
  
  # Accuracy
  accuracy <- mean(actual == predicted)
  
  # Mean Absolute Error
  mae <- mean(abs(actual - predicted))
  
  # Quadratic Weighted Kappa
  weights <- outer(
    0:8,
    0:8,
    function(i, j) (i - j)^2 / 8^2
  )
  
  observed <- cm / sum(cm)
  
  expected <- outer(
    rowSums(observed),
    colSums(observed)
  )
  
  observed_disagreement <- sum(weights * observed)
  expected_disagreement <- sum(weights * expected)
  
  qwk <- if (expected_disagreement > 0) {
    1 - observed_disagreement / expected_disagreement
  } else {
    NA_real_
  }
  
  list(
    accuracy = accuracy,
    mae = mae,
    qwk = qwk,
    confusion_matrix = cm
  )
}

# 评价函数单元测试
test_result <- evaluate_ordinal(0:8, 0:8)

stopifnot(
  isTRUE(all.equal(test_result$accuracy, 1)),
  isTRUE(all.equal(test_result$mae, 0)),
  isTRUE(all.equal(test_result$qwk, 1))
)

# 完全反向预测
reverse_test <- evaluate_ordinal(0:8, 8:0)

stopifnot(
  isTRUE(all.equal(reverse_test$qwk, -1))
)

cat("Evaluation metric tests passed.\n")


# ============================================================
# 4. Model Fitting and Prediction Functions
# ============================================================

# 统一模型拟合函数
fit_ordinal <- function(formula, data) {
  
  fit <- ordinal::clm(
    formula = formula,
    data = data,
    link = "logit",
    threshold = "flexible",
    Hess = TRUE
  )
  
  # 检查收敛
  if (!isTRUE(fit$convergence$code == 0)) {
    stop("Ordinal model failed to converge.")
  }
  
  # 检查参数估计
  if (any(!is.finite(coef(fit)))) {
    stop("Non-finite or unidentified coefficients.")
  }
  
  fit
}


# 统一概率预测函数
predict_ordinal <- function(fit, newdata) {
  
  # 必须移除因变量 y
  newdata_x <- newdata[
    , setdiff(names(newdata), "y"),
    drop = FALSE
  ]
  
  # 预测全部九个类别的概率
  prob <- predict(
    fit,
    newdata = newdata_x,
    type = "prob"
  )$fit
  
  # 检查矩阵维度
  if (
    !is.matrix(prob) ||
    nrow(prob) != nrow(newdata) ||
    ncol(prob) != length(classes)
  ) {
    stop("Incorrect probability matrix dimensions.")
  }
  
  # 检查类别名称
  if (
    is.null(colnames(prob)) ||
    !setequal(colnames(prob), classes)
  ) {
    stop("Incorrect probability class labels.")
  }
  
  # 统一类别顺序
  prob <- prob[, classes, drop = FALSE]
  
  # 检查概率有效性
  if (
    any(!is.finite(prob)) ||
    any(prob < -1e-8) ||
    any(prob > 1 + 1e-8) ||
    any(abs(rowSums(prob) - 1) > 1e-6)
  ) {
    stop("Invalid predicted probabilities.")
  }
  
  # 最大概率分类规则
  predicted <- colnames(prob)[
    max.col(prob, ties.method = "first")
  ]
  
  list(
    probability = prob,
    predicted = predicted
  )
}


# ============================================================
# 5. Define Candidate Models
# ============================================================

model_formulas <- list(
  
  baseline =
    y ~ age + sex + bmi + children +
    smoker + region,
  
  interaction =
    y ~ age + sex + bmi * smoker +
    children + region,
  
  spline =
    y ~ age + sex +
    splines::ns(bmi, df = 3) * smoker +
    children + region
  
)

model_names <- names(model_formulas)


# ============================================================
# 6. Stratified 5-Fold Cross-Validation Split
# ============================================================

set.seed(2026)

n <- nrow(train_data)
fold_id <- integer(n)

# 记录各折当前样本数量
fold_sizes <- integer(K)

# 按费用等级分层
for (class in classes) {
  
  idx <- which(train_data$y == class)
  
  # 随机打乱该类别的样本
  idx <- sample(idx)
  
  # 每个折先分配相同数量的样本
  base_n <- length(idx) %/% K
  remainder <- length(idx) %% K
  
  allocation <- rep(seq_len(K), each = base_n)
  
  # 将剩余样本优先分配给样本量较小的折
  if (remainder > 0) {
    
    extra_folds <- order(
      fold_sizes,
      runif(K)
    )[seq_len(remainder)]
    
    allocation <- c(allocation, extra_folds)
  }
  
  fold_id[idx] <- sample(allocation)
  
  fold_sizes <- tabulate(fold_id, nbins = K)
}

stopifnot(
  all(fold_id %in% seq_len(K)),
  length(fold_id) == n,
  all(table(fold_id, train_data$y) > 0)
)

cat("\n========== Cross-Validation Split ==========\n")

cat("\nFold sizes:\n")
print(table(fold_id))

cat("\nClass distribution by fold:\n")
print(table(fold_id, train_data$y))

# 保存交叉验证索引
saveRDS(
  data.frame(
    original_row = split_indices$train,
    fold = fold_id
  ),
  "data/processed/ordinal_cv_indices.rds"
)


# ============================================================
# 7. Run Cross-Validation
# ============================================================

cv_records <- list()
oof_records <- list()

record_id <- 1L

for (fold in seq_len(K)) {
  
  cat("\n========== Fold", fold, "==========\n")
  
  train_idx <- which(fold_id != fold)
  test_idx <- which(fold_id == fold)
  
  fold_train <- train_data[
    train_idx, , drop = FALSE
  ]
  
  fold_test <- train_data[
    test_idx, , drop = FALSE
  ]
  
  for (model_name in model_names) {
    
    cat("Fitting:", model_name, "\n")
    
    # 每一折独立拟合模型
    fit <- fit_ordinal(
      formula = model_formulas[[model_name]],
      data = fold_train
    )
    
    # 在当前折的留出数据上预测
    prediction <- predict_ordinal(
      fit = fit,
      newdata = fold_test
    )
    
    # 计算评价指标
    metrics <- evaluate_ordinal(
      actual = fold_test$y,
      predicted = prediction$predicted
    )
    
    # 保存当前折评价结果
    cv_records[[record_id]] <- data.frame(
      model = model_name,
      fold = fold,
      n = nrow(fold_test),
      accuracy = metrics$accuracy,
      mae = metrics$mae,
      qwk = metrics$qwk
    )
    
    # 保存折外预测
    oof_records[[record_id]] <- data.frame(
      model = model_name,
      fold = fold,
      row_id = split_indices$train[test_idx],
      actual = as.integer(
        as.character(fold_test$y)
      ),
      predicted = as.integer(
        prediction$predicted
      )
    )
    
    cat(
      sprintf(
        "Accuracy: %.4f | MAE: %.4f | QWK: %.4f\n",
        metrics$accuracy,
        metrics$mae,
        metrics$qwk
      )
    )
    
    record_id <- record_id + 1L
  }
}

cv_results <- do.call(rbind, cv_records)
oof_predictions <- do.call(rbind, oof_records)

stopifnot(
  nrow(cv_results) == K * length(model_names),
  all(is.finite(cv_results$qwk))
)


# ============================================================
# 8. Summarize Cross-Validation Results
# ============================================================

cv_summary <- do.call(
  rbind,
  
  lapply(model_names, function(model_name) {
    
    x <- cv_results[
      cv_results$model == model_name, ,
      drop = FALSE
    ]
    
    data.frame(
      model = model_name,
      
      accuracy_mean = mean(x$accuracy),
      accuracy_sd = sd(x$accuracy),
      
      mae_mean = mean(x$mae),
      mae_sd = sd(x$mae),
      
      qwk_mean = mean(x$qwk),
      qwk_sd = sd(x$qwk)
    )
  })
)

# QWK 优先，其次 MAE，最后 Accuracy
cv_summary <- cv_summary[
  order(
    -cv_summary$qwk_mean,
    cv_summary$mae_mean,
    -cv_summary$accuracy_mean
  ), ,
  drop = FALSE
]

rownames(cv_summary) <- NULL

cat("\n========== CV Fold Results ==========\n")
print(cv_results)

cat("\n========== CV Summary ==========\n")
print(cv_summary, digits = 5)


# ============================================================
# 9. Overall Out-of-Fold Evaluation
# ============================================================

oof_summary <- do.call(
  rbind,
  
  lapply(model_names, function(model_name) {
    
    x <- oof_predictions[
      oof_predictions$model == model_name, ,
      drop = FALSE
    ]
    
    stopifnot(
      nrow(x) == nrow(train_data),
      !anyDuplicated(x$row_id),
      setequal(x$row_id, split_indices$train)
    )
    
    metrics <- evaluate_ordinal(
      actual = x$actual,
      predicted = x$predicted
    )
    
    data.frame(
      model = model_name,
      accuracy = metrics$accuracy,
      mae = metrics$mae,
      qwk = metrics$qwk
    )
  })
)

oof_summary <- oof_summary[
  order(-oof_summary$qwk), ,
  drop = FALSE
]

rownames(oof_summary) <- NULL

cat("\n========== Overall OOF Results ==========\n")
print(oof_summary, digits = 5)


# ============================================================
# 10. Save Cross-Validation Results
# ============================================================

write.csv(
  cv_results,
  "results/tables/ordinal_cv_folds.csv",
  row.names = FALSE
)

write.csv(
  cv_summary,
  "results/tables/ordinal_cv_summary.csv",
  row.names = FALSE
)

write.csv(
  oof_predictions,
  "results/tables/ordinal_oof_predictions.csv",
  row.names = FALSE
)

write.csv(
  oof_summary,
  "results/tables/ordinal_oof_summary.csv",
  row.names = FALSE
)


# ============================================================
# 11. Visualize Model Comparison
# ============================================================

cv_plot_data <- cv_summary

cv_plot_data$model <- factor(
  cv_plot_data$model,
  levels = rev(cv_summary$model)
)

p_cv <- ggplot(
  cv_plot_data,
  aes(x = model, y = qwk_mean)
) +
  geom_col(
    fill = "#3B82F6",
    width = 0.6
  ) +
  geom_errorbar(
    aes(
      ymin = qwk_mean - qwk_sd,
      ymax = qwk_mean + qwk_sd
    ),
    width = 0.15
  ) +
  geom_text(
    aes(label = sprintf("%.4f", qwk_mean)),
    hjust = -0.25
  ) +
  coord_flip() +
  scale_y_continuous(
    expand = expansion(mult = c(0.05, 0.15))
  ) +
  labs(
    title = "Ordinal Model Comparison",
    subtitle = "Stratified 5-fold cross-validation",
    x = "Model",
    y = "Mean Quadratic Weighted Kappa",
    caption = "Error bars represent one standard deviation."
  ) +
  theme_minimal(base_size = 13)

print(p_cv)

ggsave(
  filename = "results/figures/ordinal_cv_comparison.png",
  plot = p_cv,
  width = 8,
  height = 5,
  dpi = 300
)


# ============================================================
# 12. Select the Final Model
# ============================================================

best_model_name <- cv_summary$model[1]

cat("\n========== Model Selection ==========\n")

cat("Selected model:", best_model_name, "\n")

cat(
  "Mean CV QWK:",
  cv_summary$qwk_mean[1],
  "\n"
)

# 使用完整训练集重新拟合最优模型
final_model <- fit_ordinal(
  formula = model_formulas[[best_model_name]],
  data = train_data
)

cat("\n========== Final Model Summary ==========\n")
print(summary(final_model))

saveRDS(
  final_model,
  "results/models/ordinal_final_model.rds"
)

saveRDS(
  list(
    selected_model = best_model_name,
    formula = model_formulas[[best_model_name]],
    selection_metric = "Mean CV QWK",
    prediction_rule = "Maximum class probability",
    cv_summary = cv_summary,
    seed = 2026
  ),
  "results/models/ordinal_model_selection.rds"
)


# ============================================================
# 13. Independent Validation
# ============================================================

# 仅在模型选择完成后评估最终验证集
# 首次运行时保持 FALSE
RUN_FINAL_VALIDATION <- TRUE

if (RUN_FINAL_VALIDATION) {
  
  validation_data <- model_data[
    split_indices$validation, ,
    drop = FALSE
  ]
  
  stopifnot(
    nrow(validation_data) == 405,
    !anyNA(validation_data)
  )
  
  final_prediction <- predict_ordinal(
    fit = final_model,
    newdata = validation_data
  )
  
  final_metrics <- evaluate_ordinal(
    actual = validation_data$y,
    predicted = final_prediction$predicted
  )
  
  validation_summary <- data.frame(
    model = best_model_name,
    n = nrow(validation_data),
    accuracy = final_metrics$accuracy,
    mae = final_metrics$mae,
    qwk = final_metrics$qwk
  )
  
  cat("\n========== Validation Results ==========\n")
  print(validation_summary, digits = 5)
  
  cat("\n========== Confusion Matrix ==========\n")
  print(final_metrics$confusion_matrix)
  
  
  # ==========================================================
  # 14. Prediction Error Analysis
  # ==========================================================
  
  actual <- as.integer(
    as.character(validation_data$y)
  )
  
  predicted <- as.integer(
    final_prediction$predicted
  )
  
  error <- predicted - actual
  absolute_error <- abs(error)
  
  error_summary <- data.frame(
    exact_match = mean(absolute_error == 0),
    within_one_level = mean(absolute_error <= 1),
    within_two_levels = mean(absolute_error <= 2),
    severe_error = mean(absolute_error >= 3),
    underprediction = mean(error < 0),
    overprediction = mean(error > 0),
    mean_signed_error = mean(error)
  )
  
  cat("\n========== Error Analysis ==========\n")
  print(error_summary, digits = 5)
  
  cat("\nAbsolute error distribution:\n")
  print(table(factor(absolute_error, levels = 0:8)))
  
  # 保存验证集预测
  validation_predictions <- data.frame(
    row_id = split_indices$validation,
    actual = actual,
    predicted = predicted,
    error = error,
    absolute_error = absolute_error
  )
  
  probability_df <- as.data.frame(
    final_prediction$probability
  )
  
  names(probability_df) <- paste0(
    "prob_", classes
  )
  
  validation_predictions <- cbind(
    validation_predictions,
    probability_df
  )
  
  
  # ==========================================================
  # 15. Confusion Matrix Visualization
  # ==========================================================
  
  cm_df <- as.data.frame(
    final_metrics$confusion_matrix
  )
  
  p_cm <- ggplot(
    cm_df,
    aes(
      x = Predicted,
      y = Actual,
      fill = Freq
    )
  ) +
    geom_tile(color = "white") +
    geom_text(
      aes(
        label = Freq,
        color = Freq > max(Freq) / 2
      ),
      size = 4
    ) +
    scale_color_manual(
      values = c("FALSE" = "black", "TRUE" = "white"),
      guide = "none"
    ) +
    scale_fill_gradient(
      low = "#EFF6FF",
      high = "#1D4ED8"
    ) +
    scale_y_discrete(
      limits = rev(classes)
    ) +
    coord_equal() +
    labs(
      title = "Validation Confusion Matrix",
      subtitle = paste(
        "Selected model:", best_model_name
      ),
      x = "Predicted Cost Level",
      y = "Actual Cost Level",
      fill = "Count"
    ) +
    theme_minimal(base_size = 13) +
    theme(panel.grid = element_blank())
  
  print(p_cm)
  
  ggsave(
    filename = "results/figures/ordinal_confusion_matrix.png",
    plot = p_cm,
    width = 8,
    height = 7,
    dpi = 300
  )
  
  
  # ==========================================================
  # 16. Prediction Error Visualization
  # ==========================================================
  
  error_df <- data.frame(
    error = factor(error, levels = -8:8)
  )
  
  p_error <- ggplot(
    error_df,
    aes(x = error)
  ) +
    geom_bar(
      fill = "#3B82F6",
      width = 0.75
    ) +
    scale_x_discrete(drop = FALSE) +
    labs(
      title = "Distribution of Prediction Errors",
      subtitle = "Predicted level minus actual level",
      x = "Prediction Error",
      y = "Number of Policyholders"
    ) +
    theme_minimal(base_size = 13)
  
  print(p_error)
  
  ggsave(
    filename = "results/figures/ordinal_prediction_errors.png",
    plot = p_error,
    width = 9,
    height = 5,
    dpi = 300
  )
  
  
  # ==========================================================
  # 17. Save Final Validation Results
  # ==========================================================
  
  write.csv(
    validation_summary,
    "results/tables/ordinal_validation_metrics.csv",
    row.names = FALSE
  )
  
  write.csv(
    as.data.frame.matrix(
      final_metrics$confusion_matrix
    ),
    "results/tables/ordinal_confusion_matrix.csv"
  )
  
  write.csv(
    error_summary,
    "results/tables/ordinal_error_summary.csv",
    row.names = FALSE
  )
  
  write.csv(
    validation_predictions,
    "results/tables/ordinal_validation_predictions.csv",
    row.names = FALSE
  )
  
  cat("\nPhase 4 final validation completed.\n")
  
} else {
  
  cat(
    "\nFinal validation is disabled.",
    "\nThe held-out validation set has not been evaluated.\n"
  )
}

cat("\n========== Script Completed ==========\n")
