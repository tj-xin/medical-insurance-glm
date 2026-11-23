# ============================================================
# Medical Insurance GLM
# 01 - Data Preparation and Quality Assessment
# ============================================================

# 1. 读取原始数据
df <- read.csv("data/raw/project data.csv")

# 2. 数据基本结构
cat("样本量与变量数：\n")
print(dim(df))

cat("\n变量名称：\n")
print(names(df))

cat("\n变量类型：\n")
str(df)

# 3. 数据质量检查
cat("\n各变量缺失值数量：\n")
print(colSums(is.na(df)))

cat("\n重复记录数量：\n")
print(sum(duplicated(df)))

# 4. 因变量分布
cat("\n医疗费用等级分布：\n")
print(table(df$y))

cat("\n医疗费用等级比例：\n")
print(round(prop.table(table(df$y)), 4))

# 5. 数值变量描述性统计
cat("\n描述性统计：\n")
print(summary(df))

# 6. 检查地区哑变量编码
region_cols <- grep("^region__", names(df), value = TRUE)

cat("\n地区变量取值：\n")
print(lapply(df[region_cols], unique))

cat("\n每条记录的地区编码之和：\n")
print(table(rowSums(df[region_cols])))

# 7. 检查因变量类别
cat("\n因变量实际类别：\n")
print(sort(unique(df$y)))

# ============================================================
# 8. 构造建模所需的变量
# ============================================================

# 地区哑变量转换为分类变量
region_cols <- c(
  "region__northeast",
  "region__northwest",
  "region__southeast",
  "region__southwest"
)

region_names <- c(
  "northeast",
  "northwest",
  "southeast",
  "southwest"
)

# 确认地区编码有效
stopifnot(
  all(as.matrix(df[region_cols]) %in% c(0, 1)),
  all(rowSums(df[region_cols]) == 1)
)

# 创建新的建模数据框
df_model <- df

df_model$region <- factor(
  region_names[max.col(df[region_cols])],
  levels = region_names
)

# 将二元解释变量转换为因子
# 暂时使用原始编码，不预设 0/1 的实际含义
df_model$sex <- factor(df_model$sex)
df_model$smoker <- factor(df_model$smoker)

# 将医疗费用等级转换为有序因子
df_model$y <- ordered(df_model$y, levels = 0:8)

# 删除原有的四个地区哑变量
df_model <- df_model[
  , !names(df_model) %in% region_cols
]

# ============================================================
# 9. 检查处理后的数据
# ============================================================

cat("\n处理后的变量结构：\n")
str(df_model)

cat("\n地区分布：\n")
print(table(df_model$region))

cat("\n因变量是否为有序因子：\n")
print(is.ordered(df_model$y))

cat("\n处理后数据维度：\n")
print(dim(df_model))

# ============================================================
# 10. 保存处理后的数据
# ============================================================

saveRDS(
  df_model,
  file = "data/processed/insurance_model_data.rds"
)

cat("\n处理后的数据已保存。\n")