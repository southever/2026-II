%% ==========================================================
% 任务4：EV三种充电策略统一对比（改进版，增加月平均SOC和箱线图）
% 输入文件：
% 1. EV_S1_home_charge_result.csv
% 2. EV_S2_valley_delay_result.csv
% 3. EV_S3_pv_surplus_result.csv
%
% 输出文件：
% 1. EV_strategy_compare.csv
% 2. fig_EV_compare 文件夹中的优化对比图
% ==========================================================

clear;
clc;

%% 1. 读取三种策略结果
S1 = readtable('EV_S1_home_charge_result.csv');
S2 = readtable('EV_S2_valley_delay_result.csv');
S3 = readtable('EV_S3_pv_surplus_result.csv');

S1.timestamp = datetime(S1.timestamp);
S2.timestamp = datetime(S2.timestamp);
S3.timestamp = datetime(S3.timestamp);

dt_hour = 5 / 60;

%% 2. 创建图片输出文件夹
fig_dir = 'fig_EV_compare';
if ~exist(fig_dir, 'dir')
    mkdir(fig_dir);
end

%% 3. 计算年度统计指标
strategy_name = ["EV-S1 到家即充"; "EV-S2 谷时延迟"; "EV-S3 光伏富余优先"];

E_EV_year = [sum(S1.P_EV_S1_kW) * dt_hour;
             sum(S2.P_EV_S2_kW) * dt_hour;
             sum(S3.P_EV_S3_kW) * dt_hour];

E_total_year = [sum(S1.P_total_S1_kW) * dt_hour;
                sum(S2.P_total_S2_kW) * dt_hour;
                sum(S3.P_total_S3_kW) * dt_hour];

P_peak = [max(S1.P_total_S1_kW);
          max(S2.P_total_S2_kW);
          max(S3.P_total_S3_kW)];

idx_evening = S1.time_hour >= 18 & S1.time_hour < 22;
P_evening_peak = [max(S1.P_total_S1_kW(idx_evening));
                  max(S2.P_total_S2_kW(idx_evening));
                  max(S3.P_total_S3_kW(idx_evening))];

SOC_min = [min(S1.SOC_EV_S1)*100;
           min(S2.SOC_EV_S2)*100;
           min(S3.SOC_EV_S3)*100];

SOC_max = [max(S1.SOC_EV_S1)*100;
           max(S2.SOC_EV_S2)*100;
           max(S3.SOC_EV_S3)*100];

%% 4. 输出策略对比表
EV_strategy_compare = table(strategy_name, E_EV_year, E_total_year, ...
    P_peak, P_evening_peak, SOC_min, SOC_max, ...
    'VariableNames', {'Strategy', 'EV_Energy_kWh', 'Total_Energy_kWh', ...
    'Peak_Load_kW', 'Evening_Peak_Load_kW', 'SOC_Min_percent', 'SOC_Max_percent'});

writetable(EV_strategy_compare,'EV_strategy_compare.csv');
disp(EV_strategy_compare);
fprintf('\n已生成策略对比表：EV_strategy_compare.csv\n');

%% 5. 图1：全年SOC对比（蓝黄绿）
idx_sample = 1:12:height(S1);

figure('Name','三种EV策略全年SOC对比',...
       'Position',[100,100,1200,500]);
hold on

plot(S1.timestamp(idx_sample), S1.SOC_EV_S1(idx_sample)*100,'Color',[0 0.4470 0.7410],'LineWidth',0.8);
plot(S2.timestamp(idx_sample), S2.SOC_EV_S2(idx_sample)*100,'Color',[0.9290 0.8940 0.1250],'LineWidth',0.8); % 黄色
plot(S3.timestamp(idx_sample), S3.SOC_EV_S3(idx_sample)*100,'Color',[0.4660 0.6740 0.1880],'LineWidth',0.8);

xlabel('时间'); ylabel('SOC / %');
title('三种EV充电策略全年SOC对比');
legend('EV-S1 到家即充','EV-S2 谷时延迟','EV-S3 光伏富余优先','Location','south');
ylim([20 100]);
grid on;

saveas(gcf, fullfile(fig_dir,'EV_strategy_SOC_compare.png'));

%% 5b. 月平均SOC对比
month_id = month(S1.timestamp);
SOC_monthly_S1 = zeros(12,1);
SOC_monthly_S2 = zeros(12,1);
SOC_monthly_S3 = zeros(12,1);

for m = 1:12
    idx_m = month_id == m;
    SOC_monthly_S1(m) = mean(S1.SOC_EV_S1(idx_m)) * 100;
    SOC_monthly_S2(m) = mean(S2.SOC_EV_S2(idx_m)) * 100;
    SOC_monthly_S3(m) = mean(S3.SOC_EV_S3(idx_m)) * 100;
end

figure('Name','月平均SOC对比','Position',[120,120,1000,500]);
plot(1:12, SOC_monthly_S1,'-o','LineWidth',1.5,'Color',[0 0.4470 0.7410]); hold on
plot(1:12, SOC_monthly_S2,'-s','LineWidth',1.5,'Color',[0.9290 0.8940 0.1250]);
plot(1:12, SOC_monthly_S3,'-^','LineWidth',1.5,'Color',[0.4660 0.6740 0.1880]);
xlabel('月份'); ylabel('平均SOC / %'); title('三种EV策略月平均SOC对比');
legend('EV-S1','EV-S2','EV-S3','Location','best'); grid on;
xlim([1 12]);
saveas(gcf, fullfile(fig_dir,'EV_strategy_monthly_SOC_compare.png'));

%% 5c. 全年SOC箱线图
figure('Name','SOC箱线图','Position',[140,140,1000,500]);
boxplot([S1.SOC_EV_S1*100, S2.SOC_EV_S2*100, S3.SOC_EV_S3*100],...
    'Labels',{'EV-S1','EV-S2','EV-S3'});
ylabel('SOC / %'); title('三种EV策略全年SOC箱线图');
grid on;
saveas(gcf, fullfile(fig_dir,'EV_strategy_SOC_boxplot.png'));

%% 6. 图2：月度EV充电电量对比
monthly_EV_S1 = zeros(12,1);
monthly_EV_S2 = zeros(12,1);
monthly_EV_S3 = zeros(12,1);

for m = 1:12
    idx_m = month_id == m;
    monthly_EV_S1(m) = sum(S1.P_EV_S1_kW(idx_m)) * dt_hour;
    monthly_EV_S2(m) = sum(S2.P_EV_S2_kW(idx_m)) * dt_hour;
    monthly_EV_S3(m) = sum(S3.P_EV_S3_kW(idx_m)) * dt_hour;
end

figure('Name','三策略月度EV充电量对比','Position',[120,120,1000,500]);
bar([monthly_EV_S1, monthly_EV_S2, monthly_EV_S3]);
set(gca, 'XTickLabel', {'1月','2月','3月','4月','5月','6月','7月','8月','9月','10月','11月','12月'});
xlabel('月份'); ylabel('EV充电电量 / kWh'); title('三种EV充电策略月度充电电量对比');
legend('EV-S1','EV-S2','EV-S3','Location','best'); grid on
saveas(gcf, fullfile(fig_dir,'EV_strategy_monthly_energy_compare.png'));

%% 7. 图3：典型日三策略总负荷对比
daily_EV_S1 = zeros(365,1);
for d = 1:365
    idx_d = S1.day_index == d;
    daily_EV_S1(d) = sum(S1.P_EV_S1_kW(idx_d)) * dt_hour;
end
[~, typical_day] = max(daily_EV_S1);
idx_day = S1.day_index == typical_day;

figure('Name','典型日三策略总负荷对比','Position',[160,160,1200,500]);
plot(S1.time_hour(idx_day), S1.load_kW(idx_day),'LineWidth',1.6); hold on
plot(S1.time_hour(idx_day), S1.P_total_S1_kW(idx_day),'LineWidth',1.4);
plot(S2.time_hour(idx_day), S2.P_total_S2_kW(idx_day),'--','LineWidth',1.4);
plot(S3.time_hour(idx_day), S3.P_total_S3_kW(idx_day),'-.','LineWidth',1.4);
xlabel('时间 / h'); ylabel('功率 / kW'); title(['典型日三策略总负荷对比，第', num2str(typical_day),'天']);
legend('基础负荷','EV-S1 总负荷','EV-S2 总负荷','EV-S3 总负荷','Location','best'); grid on; xlim([0 24]);
saveas(gcf, fullfile(fig_dir,'EV_strategy_typical_day_total_compare.png'));

%% 8. 图4：策略年度峰值对比
figure('Name','三策略年度峰值对比','Position',[180,180,1000,500]);
bar([P_peak, P_evening_peak]);
set(gca, 'XTickLabel', {'EV-S1','EV-S2','EV-S3'});
ylabel('功率 / kW'); title('三种EV充电策略年度峰值对比');
legend('全年峰值','晚高峰峰值','Location','best'); grid on;
ylim([0, max(P_peak)*1.2]);
saveas(gcf, fullfile(fig_dir,'EV_strategy_peak_compare.png'));

fprintf('\n统一典型日选择为第 %d 天\n', typical_day);
fprintf('EV策略对比图片已保存至文件夹：%s\n', fig_dir);