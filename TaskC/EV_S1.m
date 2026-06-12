%% ==========================================================
% 任务4：EV-S1 到家即充策略
% ==========================================================

clear;
clc;

%% 1. 读取输入数据

T_base = readtable('C_input_base_5min.csv');
EV_event_table = readtable('EV_event_table.csv');

T_base.timestamp = datetime(T_base.timestamp);

%% 2. 调用 SOC_update 函数

[SOC_S1, P_EV_S1, P_total_S1] = SOC_update( ...
    EV_event_table, ...
    T_base, ...
    'S1');

%% 3. 整理输出表

T_out = T_base;

T_out.SOC_EV_S1 = SOC_S1;
T_out.P_EV_S1_kW = P_EV_S1;
T_out.P_total_S1_kW = P_total_S1;

%% 4. 计算统计指标

dt_hour = 5 / 60;

E_base_year = sum(T_base.load_kW) * dt_hour;
E_EV_S1_year = sum(P_EV_S1) * dt_hour;
E_total_S1_year = sum(P_total_S1) * dt_hour;

P_base_peak = max(T_base.load_kW);
P_total_S1_peak = max(P_total_S1);

idx_evening = T_base.time_hour >= 18 & T_base.time_hour < 22;

P_base_evening_peak = max(T_base.load_kW(idx_evening));
P_total_S1_evening_peak = max(P_total_S1(idx_evening));

SOC_min_S1 = min(SOC_S1);
SOC_max_S1 = max(SOC_S1);

%% 5. 输出统计结果

fprintf('\n========== EV-S1 到家即充策略结果 ==========\n');
fprintf('基础负荷年用电量：%.2f kWh\n', E_base_year);
fprintf('EV-S1 年充电电量：%.2f kWh\n', E_EV_S1_year);
fprintf('加入EV后年总用电量：%.2f kWh\n', E_total_S1_year);
fprintf('基础负荷全年峰值：%.2f kW\n', P_base_peak);
fprintf('加入EV后全年峰值：%.2f kW\n', P_total_S1_peak);
fprintf('基础负荷晚高峰峰值：%.2f kW\n', P_base_evening_peak);
fprintf('加入EV后晚高峰峰值：%.2f kW\n', P_total_S1_evening_peak);
fprintf('SOC最低值：%.2f%%\n', SOC_min_S1 * 100);
fprintf('SOC最高值：%.2f%%\n', SOC_max_S1 * 100);
fprintf('===========================================\n');

%% 6. 保存结果

writetable(T_out, 'EV_S1_home_charge_result.csv');

fprintf('\n已生成文件：EV_S1_home_charge_result.csv\n');

%% 7. 绘图检查与保存图片

set(0,'DefaultFigureVisible','on');

fig_dir = 'fig_EV_S1';
if ~exist(fig_dir, 'dir')
    mkdir(fig_dir);
end

idx_sample = 1:12:height(T_out);

%% 7.1 全年SOC曲线

figure('Name','EV-S1 全年SOC曲线','Position',[100,100,1200,500]);
plot(T_out.timestamp(idx_sample), T_out.SOC_EV_S1(idx_sample) * 100, 'LineWidth', 1.2);
xlabel('时间');
ylabel('SOC / %');
title('EV-S1 到家即充策略全年SOC曲线');
grid on;
drawnow;

saveas(gcf, fullfile(fig_dir, 'EV_S1_SOC_year.png'));

%% 7.2 全年EV充电功率曲线
% 这里不抽样，避免7kW短时脉冲被抽样漏掉

figure('Name','EV-S1 全年EV充电负荷','Position',[120,120,1200,500]);
plot(T_out.timestamp, T_out.P_EV_S1_kW, 'LineWidth', 0.8);
xlabel('时间');
ylabel('EV充电功率 / kW');
title('EV-S1 到家即充策略全年EV充电负荷');
grid on;
ylim([0 8]);
drawnow;

saveas(gcf, fullfile(fig_dir, 'EV_S1_charge_power_year.png'));

%% 7.3 自动选择EV充电量最大的典型日

daily_EV_energy = zeros(365,1);

for d = 1:365
    idx_d = T_out.day_index == d;
    daily_EV_energy(d) = sum(T_out.P_EV_S1_kW(idx_d)) * dt_hour;
end

[~, typical_day] = max(daily_EV_energy);

idx_day = T_out.day_index == typical_day;

fprintf('\nEV-S1 典型日自动选择为第 %d 天，当日EV充电量 %.2f kWh\n', ...
    typical_day, daily_EV_energy(typical_day));

%% 7.4 典型日负荷对比图
% 左轴：基础负荷、加入EV后总负荷
% 右轴：EV充电负荷，避免EV充电曲线压缩其他曲线

figure('Name','EV-S1 典型日负荷对比','Position',[140,140,1200,550]);

yyaxis left;
plot(T_out.time_hour(idx_day), T_out.load_kW(idx_day), 'LineWidth', 1.6);
hold on;
plot(T_out.time_hour(idx_day), T_out.P_total_S1_kW(idx_day), 'LineWidth', 1.6);
ylabel('家庭负荷 / kW');

yyaxis right;
stairs(T_out.time_hour(idx_day), T_out.P_EV_S1_kW(idx_day), 'LineWidth', 1.4);
ylabel('EV充电功率 / kW');
ylim([0 8]);

xlabel('时间 / h');
title(['EV-S1 典型日负荷对比，第', num2str(typical_day), '天']);
legend('基础负荷', '加入EV后总负荷', 'EV充电负荷', 'Location','best');

grid on;
xlim([0 24]);
drawnow;

saveas(gcf, fullfile(fig_dir, 'EV_S1_typical_day_load.png'));

%% 7.5 单独画总负荷对比，不使用双轴，适合放报告

figure('Name','EV-S1 典型日基础负荷与总负荷','Position',[160,160,1200,500]);

plot(T_out.time_hour(idx_day), T_out.load_kW(idx_day), 'LineWidth', 1.6);
hold on;
plot(T_out.time_hour(idx_day), T_out.P_total_S1_kW(idx_day), 'LineWidth', 1.6);

xlabel('时间 / h');
ylabel('功率 / kW');
title(['EV-S1 典型日基础负荷与加入EV后总负荷，第', num2str(typical_day), '天']);
legend('基础负荷', '加入EV后总负荷', 'Location','best');
grid on;
xlim([0 24]);

drawnow;

saveas(gcf, fullfile(fig_dir, 'EV_S1_typical_day_total_vs_base.png'));

fprintf('\nEV-S1 图片已保存至文件夹：%s\n', fig_dir);