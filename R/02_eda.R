# ============================================================
# 02 - Exploratory Data Analysis
# Medical Insurance GLM
# ============================================================

# 加载 ggplot2
if (!requireNamespace("ggplot2", quietly = TRUE)) {
  install.packages("ggplot2")
}

library(ggplot2)

# 读取预处理数据
df <- readRDS("data/processed/insurance_model_data.rds")

# 检查数据
stopifnot(nrow(df) == 1338, is.ordered(df$y))

# 医疗费用等级频数
p1 <- ggplot(df, aes(x = y)) +
  geom_bar(fill = "#3B82F6", width = 0.75) +
  labs(
    title = "Distribution of Medical Insurance Cost Levels",
    x = "Medical Cost Level",
    y = "Number of Policyholders"
  ) +
  theme_minimal(base_size = 13)

print(p1)

ggsave(
  "results/figures/01_cost_level_distribution.png",
  plot = p1,
  width = 8,
  height = 5,
  dpi = 300
)

p2 <- ggplot(df, aes(x = age)) +
  geom_histogram(
    binwidth = 5,
    fill = "#10B981",
    color = "white"
  ) +
  labs(
    title = "Age Distribution",
    x = "Age",
    y = "Number of Policyholders"
  ) +
  theme_minimal(base_size = 13)

print(p2)

ggsave(
  "results/figures/02_age_distribution.png",
  plot = p2,
  width = 8,
  height = 5,
  dpi = 300
)

p3 <- ggplot(df, aes(x = bmi)) +
  geom_histogram(
    binwidth = 2,
    fill = "#8B5CF6",
    color = "white"
  ) +
  labs(
    title = "BMI Distribution",
    x = "Body Mass Index (BMI)",
    y = "Number of Policyholders"
  ) +
  theme_minimal(base_size = 13)

print(p3)

ggsave(
  "results/figures/03_bmi_distribution.png",
  plot = p3,
  width = 8,
  height = 5,
  dpi = 300
)

# ============================================================
# 4. Smoking Status vs Medical Cost Level
# ============================================================

p4 <- ggplot(df, aes(x = smoker, fill = y)) +
  geom_bar(
    position = "fill",
    width = 0.65
  ) +
  scale_y_continuous(
    labels = scales::label_percent()
  ) +
  scale_fill_viridis_d(
    option = "plasma",
    direction = -1
  ) +
  labs(
    title = "Medical Cost Levels by Smoking Status",
    x = "Smoking Status (Original Coding)",
    y = "Proportion of Policyholders",
    fill = "Cost Level"
  ) +
  theme_minimal(base_size = 13)

print(p4)

ggsave(
  "results/figures/04_smoking_cost_levels.png",
  plot = p4,
  width = 8,
  height = 5,
  dpi = 300
)

# 各组医疗费用等级的频数
smoking_table <- table(df$smoker, df$y)

print(smoking_table)

# 各组内部的费用等级百分比
round(prop.table(smoking_table, margin = 1) * 100, 2)

# ============================================================
# 5. Age and BMI vs Medical Cost Level
# ============================================================

# 年龄与医疗费用等级
p5 <- ggplot(df, aes(x = y, y = age)) +
  geom_boxplot(
    fill = "#60A5FA",
    alpha = 0.8,
    outlier.alpha = 0.5
  ) +
  labs(
    title = "Age by Medical Cost Level",
    x = "Medical Cost Level",
    y = "Age"
  ) +
  theme_minimal(base_size = 13)

print(p5)

ggsave(
  "results/figures/05_age_by_cost_level.png",
  plot = p5,
  width = 8,
  height = 5,
  dpi = 300
)

# BMI 与医疗费用等级
p6 <- ggplot(df, aes(x = y, y = bmi)) +
  geom_boxplot(
    fill = "#A78BFA",
    alpha = 0.8,
    outlier.alpha = 0.5
  ) +
  labs(
    title = "BMI by Medical Cost Level",
    x = "Medical Cost Level",
    y = "Body Mass Index (BMI)"
  ) +
  theme_minimal(base_size = 13)

print(p6)

ggsave(
  "results/figures/06_bmi_by_cost_level.png",
  plot = p6,
  width = 8,
  height = 5,
  dpi = 300
)

# ============================================================
# 6. BMI by Cost Level and Smoking Status
# ============================================================

p7 <- ggplot(
  df,
  aes(x = y, y = bmi, fill = smoker)
) +
  geom_boxplot(
    position = position_dodge(width = 0.8),
    width = 0.65,
    alpha = 0.8,
    outlier.alpha = 0.4
  ) +
  facet_wrap(~ smoker, nrow = 1) +
  scale_fill_manual(
    values = c("0" = "#60A5FA", "1" = "#F97316")
  ) +
  labs(
    title = "BMI by Medical Cost Level and Smoking Status",
    x = "Medical Cost Level",
    y = "Body Mass Index (BMI)",
    fill = "Smoking Status"
  ) +
  theme_minimal(base_size = 13) +
  theme(legend.position = "none")

print(p7)

ggsave(
  "results/figures/07_bmi_smoking_cost_levels.png",
  plot = p7,
  width = 11,
  height = 5,
  dpi = 300
)

# ============================================================
# 7. Other Categorical Features vs Cost Level
# ============================================================

# 构造用于绘图的数据
plot_data <- rbind(
  data.frame(
    feature = "Sex",
    group = as.character(df$sex),
    y = df$y
  ),
  data.frame(
    feature = "Region",
    group = as.character(df$region),
    y = df$y
  ),
  data.frame(
    feature = "Children",
    group = as.character(df$children),
    y = df$y
  )
)

# 分面展示不同特征的费用等级构成
p8 <- ggplot(
  plot_data,
  aes(x = group, fill = y)
) +
  geom_bar(position = "fill") +
  facet_wrap(
    ~ feature,
    scales = "free_x",
    ncol = 1
  ) +
  scale_y_continuous(
    labels = scales::label_percent()
  ) +
  scale_fill_viridis_d(
    option = "plasma",
    direction = -1
  ) +
  labs(
    title = "Medical Cost Levels Across Categorical Features",
    x = "Category",
    y = "Proportion of Policyholders",
    fill = "Cost Level"
  ) +
  theme_minimal(base_size = 12)

print(p8)

ggsave(
  "results/figures/08_categorical_features.png",
  plot = p8,
  width = 9,
  height = 9,
  dpi = 300
)

# ============================================================
# 8. Final EDA Checks
# ============================================================

# 1. 子女数量频数
cat("\nChildren Frequency:\n")
print(table(df$children))

# 2. 连续变量之间的相关系数
numeric_vars <- df[, c("age", "bmi", "children")]

cat("\nPearson Correlation Matrix:\n")
print(round(cor(numeric_vars), 3))

# 3. 吸烟状态与性别的交叉分布
cat("\nSex vs Smoking Status:\n")
print(table(df$sex, df$smoker))

# 4. 地区与吸烟状态的交叉分布
cat("\nRegion vs Smoking Status:\n")
print(table(df$region, df$smoker))