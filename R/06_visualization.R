
# ============================================================
# 06_visualization.R
# Phase 6: Final Model Visualization
# ============================================================


# ============================================================
# 1. Environment Setup
# ============================================================

required_packages <- c(
  "ggplot2",
  "ordinal",
  "logistf",
  "pROC"
)

for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg)
  }
}

library(ggplot2)
library(ordinal)
library(logistf)
library(pROC)

dir.create(
  "results/figures",
  recursive = TRUE,
  showWarnings = FALSE
)

figure_dir <- "results/figures"

cat("\n========== Visualization Setup ==========\n")


# ============================================================
# 2. Load Saved Data and Models
# ============================================================

model_data <- readRDS(
  "data/processed/insurance_model_data.rds"
)

ordinal_split <- readRDS(
  "data/processed/ordinal_split_indices.rds"
)

binary_split <- readRDS(
  "data/processed/binary_split_indices.rds"
)

ordinal_model <- readRDS(
  "results/models/ordinal_final_model.rds"
)

binary_object <- readRDS(
  "results/models/binary_final_model.rds"
)

binary_model <- binary_object$model

binary_threshold <- binary_object$threshold

ordinal_train <- model_data[
  ordinal_split$train, , drop = FALSE
]

binary_train <- model_data[
  binary_split$train, , drop = FALSE
]

binary_validation <- model_data[
  binary_split$validation, , drop = FALSE
]

stopifnot(
  inherits(ordinal_model, "clm"),
  inherits(binary_model, "logistf"),
  nrow(ordinal_train) == 933,
  nrow(binary_train) == 937,
  nrow(binary_validation) == 200,
  is.finite(binary_threshold),
  binary_threshold > 0,
  binary_threshold < 1
)

cat("Saved models loaded successfully.\n")

cat(
  "Binary final model:",
  binary_object$name, "\n"
)

cat(
  "Binary classification threshold:",
  binary_threshold, "\n"
)


# ============================================================
# 3. Visualization Style
# ============================================================

color_blue <- "#376795"
color_orange <- "#D97732"
color_green <- "#428C7B"
color_gray <- "#9CA3AF"
color_dark <- "#263746"

smoking_colors <- c(
  "Non-smoker" = color_blue,
  "Smoker" = color_orange
)

theme_project <- function() {
  
  theme_minimal(base_size = 13) +
    
    theme(
      plot.title = element_text(
        face = "bold",
        size = 16,
        color = color_dark
      ),
      
      plot.subtitle = element_text(
        size = 11,
        color = "#64748B"
      ),
      
      axis.title = element_text(
        face = "bold"
      ),
      
      axis.text = element_text(
        color = color_dark
      ),
      
      panel.grid.minor = element_blank(),
      
      panel.grid.major = element_line(
        color = "#E5E7EB",
        linewidth = 0.35
      ),
      
      legend.position = "bottom",
      
      legend.title = element_blank(),
      
      plot.background = element_rect(
        fill = "white",
        color = NA
      ),
      
      plot.margin = margin(15, 20, 15, 15)
    )
}

save_figure <- function(
    plot,
    filename,
    width = 8,
    height = 5.5
) {
  
  ggsave(
    filename = file.path(
      figure_dir,
      filename
    ),
    plot = plot,
    width = width,
    height = height,
    dpi = 300,
    bg = "white"
  )
  
  cat("Saved:", filename, "\n")
}


# ============================================================
# 4. Prediction Helper Functions
# ============================================================

get_mode <- function(x) {
  
  names(which.max(table(x)))
}


# Apply saved training-set centering parameters

prepare_binary_data <- function(data) {
  
  data$age_c <-
    data$age - binary_object$age_center
  
  data$bmi_c <-
    data$bmi - binary_object$bmi_center
  
  data
}


# Predict probabilities from the saved Firth model

predict_binary <- function(data) {
  
  data <- prepare_binary_data(data)
  
  prob <- as.numeric(
    predict(
      binary_model,
      newdata = data,
      type = "response"
    )
  )
  
  stopifnot(
    length(prob) == nrow(data),
    all(is.finite(prob)),
    all(prob >= 0 & prob <= 1)
  )
  
  prob
}


# Predict all nine ordinal class probabilities

predict_ordinal <- function(data) {
  
  data$y <- NULL
  
  prob <- predict(
    ordinal_model,
    newdata = data,
    type = "prob"
  )$fit
  
  prob <- as.matrix(prob)
  
  stopifnot(
    nrow(prob) == nrow(data),
    ncol(prob) == 9,
    all(is.finite(prob)),
    all(prob >= -1e-10),
    all(prob <= 1 + 1e-10),
    max(abs(rowSums(prob) - 1)) < 1e-8
  )
  
  prob
}


# Construct a representative covariate profile

make_profile <- function(data, n) {
  
  data.frame(
    
    age = rep(
      median(data$age), n
    ),
    
    sex = factor(
      rep(get_mode(data$sex), n),
      levels = levels(data$sex)
    ),
    
    bmi = rep(
      median(data$bmi), n
    ),
    
    children = rep(
      median(data$children), n
    ),
    
    smoker = factor(
      rep("0", n),
      levels = levels(data$smoker)
    ),
    
    region = factor(
      rep(get_mode(data$region), n),
      levels = levels(data$region)
    )
  )
}


# Add readable smoking labels

add_smoking_label <- function(data) {
  
  data$smoking_status <- factor(
    ifelse(
      as.character(data$smoker) == "1",
      "Smoker",
      "Non-smoker"
    ),
    levels = c("Non-smoker", "Smoker")
  )
  
  data
}


# ============================================================
# 5. Ordinal Model: BMI x Smoking Effect
# ============================================================

cat("\n========== Ordinal Effect Plot ==========\n")

# Restrict the plot to the central observed BMI range

bmi_range <- quantile(
  ordinal_train$bmi,
  probs = c(0.025, 0.975)
)

bmi_grid <- seq(
  bmi_range[1],
  bmi_range[2],
  length.out = 200
)

ordinal_grid <- make_profile(
  ordinal_train,
  2 * length(bmi_grid)
)

ordinal_grid$bmi <- rep(
  bmi_grid, times = 2
)

ordinal_grid$smoker <- factor(
  rep(
    c("0", "1"),
    each = length(bmi_grid)
  ),
  levels = levels(ordinal_train$smoker)
)

ordinal_grid <- add_smoking_label(
  ordinal_grid
)

ordinal_prob <- predict_ordinal(
  ordinal_grid
)

# Expected ordinal cost level: E(Y | X)

class_values <- as.numeric(
  ordinal_model$y.levels
)

ordinal_grid$expected_level <- as.numeric(
  ordinal_prob %*% class_values
)

p_ordinal_effect <- ggplot(
  ordinal_grid,
  aes(
    x = bmi,
    y = expected_level,
    color = smoking_status
  )
) +
  
  geom_line(linewidth = 1.3) +
  
  scale_color_manual(
    values = smoking_colors
  ) +
  
  scale_y_continuous(
    limits = c(0, 8),
    breaks = 0:8
  ) +
  
  labs(
    title = "BMI and Smoking Interaction",
    subtitle = paste(
      "Expected medical cost level",
      "from the ordinal spline model"
    ),
    x = "Body Mass Index (BMI)",
    y = "Expected cost level"
  ) +
  
  theme_project()

save_figure(
  p_ordinal_effect,
  "ordinal_bmi_smoking_effect.png"
)


# ============================================================
# 6. Binary Candidate Model Comparison
# ============================================================

cat("\n========== Binary Model Comparison ==========\n")

comparison <- read.csv(
  "results/tables/binary_model_comparison.csv"
)

stopifnot(
  all(
    c(
      "model",
      "roc_auc",
      "pr_auc",
      "log_loss",
      "brier_score"
    ) %in% names(comparison)
  )
)

model_labels <- c(
  baseline = "Baseline",
  interaction = "Interaction",
  spline = "Spline",
  quadratic = "Quadratic"
)

comparison$model_label <- factor(
  unname(
    model_labels[
      as.character(comparison$model)
    ]
  ),
  levels = c(
    "Baseline",
    "Interaction",
    "Spline",
    "Quadratic"
  )
)

stopifnot(!anyNA(comparison$model_label))

comparison$selected <- ifelse(
  comparison$model == binary_object$name,
  "Selected model",
  "Candidate model"
)

metric_names <- c(
  "roc_auc",
  "pr_auc",
  "log_loss",
  "brier_score"
)

metric_labels <- c(
  "ROC-AUC (higher is better)",
  "PR-AUC (higher is better)",
  "Log loss (lower is better)",
  "Brier score (lower is better)"
)

comparison_long <- do.call(
  rbind,
  
  lapply(seq_along(metric_names), function(i) {
    
    data.frame(
      model = comparison$model_label,
      selected = comparison$selected,
      metric = metric_labels[i],
      value = comparison[[metric_names[i]]]
    )
  })
)

comparison_long$metric <- factor(
  comparison_long$metric,
  levels = metric_labels
)

p_comparison <- ggplot(
  comparison_long,
  aes(
    x = model,
    y = value,
    fill = selected
  )
) +
  
  geom_col(width = 0.65) +
  
  geom_text(
    aes(label = sprintf("%.4f", value)),
    vjust = -0.5,
    size = 3.4
  ) +
  
  facet_wrap(
    ~ metric,
    scales = "free_y",
    ncol = 2
  ) +
  
  scale_fill_manual(
    values = c(
      "Selected model" = color_blue,
      "Candidate model" = color_gray
    )
  ) +
  
  scale_y_continuous(
    expand = expansion(
      mult = c(0, 0.18)
    )
  ) +
  
  labs(
    title = "Binary Logistic Model Comparison",
    subtitle = "Performance on the testing set",
    x = NULL,
    y = NULL
  ) +
  
  theme_project() +
  
  theme(
    axis.text.x = element_text(
      angle = 20,
      hjust = 1
    )
  )

save_figure(
  p_comparison,
  "binary_model_comparison.png",
  width = 10,
  height = 7
)


# ============================================================
# 7. Final Validation Predictions
# ============================================================

cat("\n========== Binary Validation Predictions ==========\n")

actual <- as.integer(
  as.character(binary_validation$y) == "8"
)

probability <- predict_binary(
  binary_validation
)

predicted <- as.integer(
  probability >= binary_threshold
)

validation_results <- data.frame(
  actual = actual,
  probability = probability,
  predicted = predicted
)

cm <- table(
  Actual = factor(actual, levels = 0:1),
  Predicted = factor(predicted, levels = 0:1)
)

print(cm)

# Verify consistency with the completed Phase 5 experiment

stopifnot(
  sum(cm) == 200,
  sum(actual == 1) == 17,
  cm["0", "0"] == 182,
  cm["0", "1"] == 1,
  cm["1", "0"] == 1,
  cm["1", "1"] == 16
)

cat("Validation prediction verification passed.\n")


# ============================================================
# 8. ROC Curve
# ============================================================

roc_object <- pROC::roc(
  response = actual,
  predictor = probability,
  levels = c(0, 1),
  direction = "<",
  quiet = TRUE
)

roc_auc <- as.numeric(
  pROC::auc(roc_object)
)

roc_data <- data.frame(
  fpr = 1 - roc_object$specificities,
  tpr = roc_object$sensitivities
)

roc_data <- roc_data[
  order(roc_data$fpr, roc_data$tpr),
]

p_roc <- ggplot(
  roc_data,
  aes(x = fpr, y = tpr)
) +
  
  geom_abline(
    intercept = 0,
    slope = 1,
    linetype = "dashed",
    color = color_gray
  ) +
  
  geom_path(
    color = color_blue,
    linewidth = 1.2
  ) +
  
  annotate(
    "text",
    x = 0.65,
    y = 0.20,
    label = sprintf(
      "AUC = %.4f", roc_auc
    ),
    size = 5,
    color = color_dark
  ) +
  
  coord_equal(
    xlim = c(0, 1),
    ylim = c(0, 1)
  ) +
  
  labs(
    title = "Receiver Operating Characteristic",
    subtitle = "Final validation set (n = 200)",
    x = "False positive rate",
    y = "True positive rate"
  ) +
  
  theme_project()

save_figure(
  p_roc,
  "binary_roc_curve.png",
  width = 6.5,
  height = 6
)


# ============================================================
# 9. Precision-Recall Curve
# ============================================================

# Evaluate all distinct probability thresholds.
# Tied probabilities are handled together.

threshold_grid <- c(
  Inf,
  sort(
    unique(probability),
    decreasing = TRUE
  )
)

pr_data <- do.call(
  rbind,
  
  lapply(threshold_grid, function(t) {
    
    pred <- as.integer(
      probability >= t
    )
    
    tp <- sum(pred == 1 & actual == 1)
    fp <- sum(pred == 1 & actual == 0)
    
    recall <- tp / sum(actual == 1)
    
    precision <- if (
      tp + fp == 0
    ) {
      1
    } else {
      tp / (tp + fp)
    }
    
    data.frame(
      recall = recall,
      precision = precision
    )
  })
)

# Average Precision: step-wise PR summary

average_precision <- sum(
  diff(pr_data$recall) *
    pr_data$precision[-1]
)

positive_rate <- mean(actual)

p_pr <- ggplot(
  pr_data,
  aes(x = recall, y = precision)
) +
  
  geom_hline(
    yintercept = positive_rate,
    linetype = "dashed",
    color = color_gray
  ) +
  
  geom_step(
    direction = "vh",
    color = color_green,
    linewidth = 1.2
  ) +
  
  annotate(
    "text",
    x = 0.38,
    y = 0.25,
    label = sprintf(
      "Average Precision = %.4f",
      average_precision
    ),
    size = 4.2,
    color = color_dark
  ) +
  
  coord_equal(
    xlim = c(0, 1),
    ylim = c(0, 1)
  ) +
  
  labs(
    title = "Precision-Recall Curve",
    subtitle = sprintf(
      "Validation positive rate: %.1f%%",
      100 * positive_rate
    ),
    x = "Recall",
    y = "Precision"
  ) +
  
  theme_project()

save_figure(
  p_pr,
  "binary_pr_curve.png",
  width = 6.5,
  height = 6
)


# ============================================================
# 10. Binary Confusion Matrix
# ============================================================

cm_data <- as.data.frame(cm)

cm_data$Actual <- factor(
  cm_data$Actual,
  levels = c("1", "0"),
  labels = c(
    "High cost",
    "Other levels"
  )
)

cm_data$Predicted <- factor(
  cm_data$Predicted,
  levels = c("0", "1"),
  labels = c(
    "Other levels",
    "High cost"
  )
)

cm_data$text_color <- ifelse(
  cm_data$Freq > max(cm_data$Freq) / 2,
  "white",
  color_dark
)

p_cm <- ggplot(
  cm_data,
  aes(
    x = Predicted,
    y = Actual,
    fill = Freq
  )
) +
  
  geom_tile(
    color = "white",
    linewidth = 2
  ) +
  
  geom_text(
    aes(
      label = Freq,
      color = text_color
    ),
    size = 9,
    fontface = "bold"
  ) +
  
  scale_color_identity() +
  
  scale_fill_gradient(
    low = "#E8EFF6",
    high = color_blue
  ) +
  
  coord_equal() +
  
  labs(
    title = "Binary Classification Confusion Matrix",
    subtitle = sprintf(
      "Validation set | Threshold = %.4f",
      binary_threshold
    ),
    x = "Predicted class",
    y = "Actual class",
    fill = "Count"
  ) +
  
  theme_project() +
  
  theme(
    panel.grid = element_blank(),
    legend.position = "none"
  )

save_figure(
  p_cm,
  "binary_confusion_matrix.png",
  width = 7,
  height = 5.8
)


# ============================================================
# 11. Calibration Curve
# ============================================================

# Fixed probability intervals.
# Empty intervals are omitted.

validation_results$probability_bin <- cut(
  validation_results$probability,
  breaks = seq(0, 1, by = 0.2),
  include.lowest = TRUE
)

calibration_groups <- split(
  validation_results,
  validation_results$probability_bin,
  drop = TRUE
)

calibration_data <- do.call(
  rbind,
  
  lapply(calibration_groups, function(d) {
    
    n <- nrow(d)
    
    observed <- sum(d$actual)
    
    ci <- binom.test(
      observed, n
    )$conf.int
    
    data.frame(
      n = n,
      mean_predicted = mean(d$probability),
      observed_rate = mean(d$actual),
      lower = ci[1],
      upper = ci[2]
    )
  })
)

calibration_data <- calibration_data[
  order(calibration_data$mean_predicted),
]

brier_score <- mean(
  (probability - actual)^2
)

p_calibration <- ggplot(
  calibration_data,
  aes(
    x = mean_predicted,
    y = observed_rate
  )
) +
  
  geom_abline(
    intercept = 0,
    slope = 1,
    color = color_gray,
    linetype = "dashed"
  ) +
  
  geom_line(
    color = color_blue,
    linewidth = 0.8
  ) +
  
  geom_errorbar(
    aes(
      ymin = lower,
      ymax = upper
    ),
    width = 0.025,
    color = color_blue,
    alpha = 0.7
  ) +
  
  geom_point(
    aes(size = n),
    color = color_blue
  ) +
  
  scale_size_continuous(
    range = c(2.5, 6)
  ) +
  
  coord_equal(
    xlim = c(0, 1),
    ylim = c(0, 1)
  ) +
  
  labs(
    title = "Probability Calibration",
    subtitle = sprintf(
      "Validation set | Brier score = %.4f",
      brier_score
    ),
    x = "Mean predicted probability",
    y = "Observed event proportion",
    size = "Group size"
  ) +
  
  theme_project()

save_figure(
  p_calibration,
  "binary_calibration_curve.png",
  width = 7,
  height = 6.5
)

print(calibration_data)


# ============================================================
# 12. Binary Model: Age Effect
# ============================================================

# Plot the conditional age effect among smokers.
# Other covariates are held at representative values.

smoker_train <- binary_train[
  binary_train$smoker == "1",
  , drop = FALSE
]

age_range <- range(smoker_train$age)

age_grid <- seq(
  age_range[1],
  age_range[2],
  length.out = 200
)

age_effect <- make_profile(
  smoker_train,
  length(age_grid)
)

age_effect$age <- age_grid

age_effect$smoker <- factor(
  rep("1", length(age_grid)),
  levels = levels(binary_train$smoker)
)

age_effect$probability <- predict_binary(
  age_effect
)

p_age <- ggplot(
  age_effect,
  aes(
    x = age,
    y = probability
  )
) +
  
  geom_line(
    color = color_blue,
    linewidth = 1.3
  ) +
  
  scale_y_continuous(
    limits = c(0, 1),
    labels = function(x) {
      paste0(round(x * 100), "%")
    }
  ) +
  
  labs(
    title = "Nonlinear Effect of Age",
    subtitle = paste(
      "Conditional predictions among smokers",
      "| Quadratic Firth logistic model"
    ),
    x = "Age (years)",
    y = "Probability of highest cost level"
  ) +
  
  theme_project()

save_figure(
  p_age,
  "binary_age_effect.png"
)


# ============================================================
# 13. Binary Model: BMI Effect
# ============================================================

bmi_range_binary <- quantile(
  smoker_train$bmi,
  probs = c(0.025, 0.975)
)

bmi_grid_binary <- seq(
  bmi_range_binary[1],
  bmi_range_binary[2],
  length.out = 200
)

bmi_effect <- make_profile(
  smoker_train,
  length(bmi_grid_binary)
)

bmi_effect$bmi <- bmi_grid_binary

bmi_effect$smoker <- factor(
  rep("1", length(bmi_grid_binary)),
  levels = levels(binary_train$smoker)
)

bmi_effect$probability <- predict_binary(
  bmi_effect
)

p_bmi <- ggplot(
  bmi_effect,
  aes(
    x = bmi,
    y = probability
  )
) +
  
  geom_line(
    color = color_orange,
    linewidth = 1.3
  ) +
  
  scale_y_continuous(
    limits = c(0, 1),
    labels = function(x) {
      paste0(round(x * 100), "%")
    }
  ) +
  
  labs(
    title = "Nonlinear Effect of BMI",
    subtitle = paste(
      "Conditional predictions among smokers",
      "| Quadratic Firth logistic model"
    ),
    x = "Body Mass Index (BMI)",
    y = "Probability of highest cost level"
  ) +
  
  theme_project()

save_figure(
  p_bmi,
  "binary_bmi_effect.png"
)


# ============================================================
# 14. Final Verification
# ============================================================

expected_figures <- c(
  "ordinal_bmi_smoking_effect.png",
  "binary_model_comparison.png",
  "binary_roc_curve.png",
  "binary_pr_curve.png",
  "binary_confusion_matrix.png",
  "binary_calibration_curve.png",
  "binary_age_effect.png",
  "binary_bmi_effect.png"
)

figure_check <- data.frame(
  figure = expected_figures,
  exists = file.exists(
    file.path(
      figure_dir,
      expected_figures
    )
  )
)

cat("\n========== Visualization Verification ==========\n")

print(
  figure_check,
  row.names = FALSE
)

stopifnot(all(figure_check$exists))

cat("\n========== Validation Metric Check ==========\n")

cat("ROC-AUC:", roc_auc, "\n")
cat("Average Precision:", average_precision, "\n")
cat("Brier score:", brier_score, "\n")
cat("Classification threshold:", binary_threshold, "\n")

cat("\nNew figures:", length(expected_figures), "\n")

cat(
  "Total figures:",
  length(
    list.files(
      figure_dir,
      pattern = "\\.png$"
    )
  ),
  "\n"
)

cat("\n========== Phase 6 Visualization Completed ==========\n")
