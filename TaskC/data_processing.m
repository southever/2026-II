%% C任务：基础数据整理脚本
% 功能：
% 1. 读取 B 提供的 microgrid_5min_integrated_data.csv
% 2. 检查 load_kW / pv_kW 缺失值和负值
% 3. 生成 EV 建模所需的时间辅助列
% 4. 生成光伏富余列 pv_surplus_kW
% 5. 输出整理后的 C_input_base_5min.csv

clear; clc;

%% 1. 读取数据
input_file = "microgrid_5min_integrated_data.csv";
T = readtable(input_file);

% 将时间戳转为 datetime 格式
T.timestamp = datetime(T.timestamp);

fprintf("原始数据行数：%d\n", height(T));
fprintf("起始时间：%s\n", string(T.timestamp(1)));
fprintf("结束时间：%s\n", string(T.timestamp(end)));

%% 2. 缺失值检查
missing_load = sum(ismissing(T.load_kW));
missing_pv   = sum(ismissing(T.pv_kW));

fprintf("\n缺失值检查：\n");
fprintf("load_kW 缺失值数量：%d\n", missing_load);
fprintf("pv_kW 缺失值数量：%d\n", missing_pv);

%% 3. 负值检查
negative_load = sum(T.load_kW < 0);
negative_pv   = sum(T.pv_kW < 0);

fprintf("\n负值检查：\n");
fprintf("load_kW 负值数量：%d\n", negative_load);
fprintf("pv_kW 负值数量：%d\n", negative_pv);

% 如果光伏存在极小负值，统一修正为0
T.pv_kW(T.pv_kW < 0) = 0;

% 基础负荷理论上不应为负，如果出现负值，先置为0
T.load_kW(T.load_kW < 0) = 0;

%% 4. 生成时间辅助列

% 第几天，范围应为 1~365
T.day_index = day(T.timestamp, "dayofyear");

% 小时小数，例如 19:30 -> 19.5
T.time_hour = hour(T.timestamp) + minute(T.timestamp) / 60;

% 星期编号：MATLAB中 Sunday=1, Monday=2, ..., Saturday=7
weekday_num = weekday(T.timestamp);

% 是否周末：周六或周日
T.is_weekend = (weekday_num == 1) | (weekday_num == 7);

% 是否周日
T.is_sunday = (weekday_num == 1);

%% 5. 生成光伏富余列

% 光伏富余功率 = max(光伏出力 - 基础负荷, 0)
% 后续 EV-S3 光伏富余优先充电策略直接使用这一列
T.pv_surplus_kW = max(T.pv_kW - T.load_kW, 0);

%% 6. 计算基础统计量

dt_hour = 5 / 60;

E_load_base_year = sum(T.load_kW) * dt_hour;
E_pv_year = sum(T.pv_kW) * dt_hour;
E_pv_surplus_year = sum(T.pv_surplus_kW) * dt_hour;

P_load_peak = max(T.load_kW);
P_pv_peak = max(T.pv_kW);
P_surplus_peak = max(T.pv_surplus_kW);

fprintf("\n基础统计结果：\n");
fprintf("年基础负荷电量：%.2f kWh\n", E_load_base_year);
fprintf("年光伏发电量：%.2f kWh\n", E_pv_year);
fprintf("年光伏富余电量：%.2f kWh\n", E_pv_surplus_year);
fprintf("基础负荷峰值：%.2f kW\n", P_load_peak);
fprintf("光伏最大出力：%.2f kW\n", P_pv_peak);
fprintf("最大光伏富余功率：%.2f kW\n", P_surplus_peak);

%% 7. 简单一致性检查

fprintf("\n一致性检查：\n");
fprintf("day_index 最小值：%d\n", min(T.day_index));
fprintf("day_index 最大值：%d\n", max(T.day_index));
fprintf("周末数据点数量：%d\n", sum(T.is_weekend));
fprintf("周日数据点数量：%d\n", sum(T.is_sunday));

%% 8. 输出整理后的数据

output_file = "C_input_base_5min.csv";
writetable(T, output_file);

fprintf("\n数据整理完成，已输出：%s\n", output_file);