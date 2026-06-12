%% ==========================================================
% 任务4：生成全年EV出行事件表
%
% 输出文件：
% EV_event_table.csv
%
% 说明：
% 1. 本脚本只生成EV出行事件，不计算充电功率
% 2. EV-S1 / EV-S2 / EV-S3 三种策略共用该事件表
% 3. 固定随机种子，保证结果可复现
% ==========================================================

clear;
clc;

%% 1. 基础参数设置

year_sim = 2025;

% EV参数
E_ev_bat = 62.5;          % EV电池容量，kWh
e_ev = 0.15;              % 单位里程耗电，kWh/km

% SOC参数
SOC_ev_init = 0.90;       % 初始SOC
SOC_ev_trigger = 0.40;    % 日常充电触发SOC
SOC_ev_min = 0.20;        % 安全SOC下限
SOC_ev_target = 0.90;     % 日常目标SOC
SOC_ev_long = 1.00;       % 长途预充目标SOC

% 工作日出行参数
weekday_mean = 35;        % 工作日基准里程，km
weekday_std = 3.5;        % 工作日随机扰动标准差，约10%
weekday_min = 20;         % 工作日最小里程，km
weekday_max = 50;         % 工作日最大里程，km

% 周末出行参数
weekend_mean = 20;        % 周末基准里程，km
weekend_std = 3;          % 周末随机扰动标准差，约15%
weekend_min = 10;         % 周末最小里程，km
weekend_max = 40;         % 周末最大里程，km

% 长途出行参数
long_trip_per_month = 2;  % 每月随机2个长途日
long_extra_min = 80;      % 长途额外里程下限，km
long_extra_max = 200;     % 长途额外里程上限，km

%% 2. 生成全年日期

date_list = (datetime(year_sim,1,1):days(1):datetime(year_sim,12,31))';
N_day = length(date_list);
day_index = (1:N_day)';

% MATLAB weekday规则：
% Sunday=1, Monday=2, ..., Saturday=7
weekday_num = weekday(date_list);

is_sunday = weekday_num == 1;
is_saturday = weekday_num == 7;
is_weekend = is_sunday | is_saturday;

month_id = month(date_list);

%% 3. 固定随机种子

% 保证每次运行生成相同的出行事件表
rng(2025);

%% 4. 初始化变量

distance_km = zeros(N_day,1);
is_long_trip = false(N_day,1);
long_extra_km = zeros(N_day,1);

%% 5. 生成工作日随机里程

weekday_idx = find(~is_weekend);

for k = 1:length(weekday_idx)
    idx = weekday_idx(k);
    
    % 正态扰动
    d = weekday_mean + weekday_std * randn;
    
    % 限制范围
    d = max(d, weekday_min);
    d = min(d, weekday_max);
    
    distance_km(idx) = d;
end

%% 6. 生成周末随机里程

weekend_idx = find(is_weekend);

for k = 1:length(weekend_idx)
    idx = weekend_idx(k);
    
    % 正态扰动
    d = weekend_mean + weekend_std * randn;
    
    % 限制范围
    d = max(d, weekend_min);
    d = min(d, weekend_max);
    
    distance_km(idx) = d;
end

%% 7. 每月随机选择2个周末日作为长途日

for m = 1:12
    
    % 当前月份的周末日
    candidate_idx = find(month_id == m & is_weekend);
    
    % 随机选择长途日
    selected_idx = candidate_idx( ...
        randperm(length(candidate_idx), long_trip_per_month));
    
    is_long_trip(selected_idx) = true;
end

%% 8. 对长途日增加随机额外里程

long_idx = find(is_long_trip);

for k = 1:length(long_idx)
    idx = long_idx(k);
    
    extra_distance = randi([long_extra_min, long_extra_max]);
    
    long_extra_km(idx) = extra_distance;
    distance_km(idx) = distance_km(idx) + extra_distance;
end

%% 9. 计算每日行驶耗电

drive_energy_kWh = distance_km * e_ev;

% 当日行驶消耗对应的SOC下降量
drive_SOC_drop = drive_energy_kWh / E_ev_bat;

%% 10. 生成长途预充标记

% 如果明天是长途日，则今天晚上需要预充至100%
need_precharge = false(N_day,1);

for d = 1:N_day-1
    if is_long_trip(d+1)
        need_precharge(d) = true;
    end
end

%% 11. 生成周日补电标记

% 每周日晚上补电至90%
need_sunday_charge = is_sunday;

%% 12. 生成SOC参数列

% 这些列便于后续SOC状态机和报告说明
SOC_init_col = SOC_ev_init * ones(N_day,1);
SOC_trigger_col = SOC_ev_trigger * ones(N_day,1);
SOC_min_col = SOC_ev_min * ones(N_day,1);
SOC_target_col = SOC_ev_target * ones(N_day,1);
SOC_long_col = SOC_ev_long * ones(N_day,1);

%% 13. 星期名称

weekday_name = strings(N_day,1);
name_map = ["Sun"; "Mon"; "Tue"; "Wed"; "Thu"; "Fri"; "Sat"];

for i = 1:N_day
    weekday_name(i) = name_map(weekday_num(i));
end

%% 14. 构建事件表

EV_event = table( ...
    day_index, ...
    date_list, ...
    month_id, ...
    weekday_name, ...
    is_weekend, ...
    is_sunday, ...
    is_long_trip, ...
    need_precharge, ...
    need_sunday_charge, ...
    distance_km, ...
    long_extra_km, ...
    drive_energy_kWh, ...
    drive_SOC_drop, ...
    SOC_init_col, ...
    SOC_trigger_col, ...
    SOC_min_col, ...
    SOC_target_col, ...
    SOC_long_col);

%% 15. 输出统计结果

fprintf('\n========== EV出行事件表统计 ==========\n');
fprintf('全年天数：%d 天\n', N_day);
fprintf('工作日数量：%d 天\n', sum(~is_weekend));
fprintf('周末数量：%d 天\n', sum(is_weekend));
fprintf('长途日数量：%d 天\n', sum(is_long_trip));
fprintf('长途前预充天数：%d 天\n', sum(need_precharge));
fprintf('周日补电次数：%d 次\n', sum(need_sunday_charge));
fprintf('全年总行驶里程：%.1f km\n', sum(distance_km));
fprintf('全年行驶耗电量：%.1f kWh\n', sum(drive_energy_kWh));
fprintf('平均日行驶里程：%.2f km/day\n', mean(distance_km));
fprintf('最大单日行驶里程：%.1f km\n', max(distance_km));
fprintf('最大单日SOC下降：%.2f%%\n', max(drive_SOC_drop)*100);
fprintf('=====================================\n');

%% 16. 输出CSV文件

output_file = 'EV_event_table.csv';
writetable(EV_event, output_file);

fprintf('\n已生成文件：%s\n', output_file);