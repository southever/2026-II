%% 成员D：储能容量/功率选型
clear; clc; close all;

%% 1. 基本参数（5分钟分辨率）
dt = 5/60;
N_step_day = 288;
N_expected = 365 * N_step_day;

fprintf('=== 储能选型开始 ===\n');
fprintf('时间分辨率：%.4f 小时\n', dt);
fprintf('理论点数：%d\n', N_expected);

%% 2. 读取B同学数据
fprintf('\n=== 读取B同学数据 ===\n');

base_table = readtable('annual_household_load_5min_enhanced.csv');
P_load_base_raw = base_table.load_kW;
N_raw = length(P_load_base_raw);
fprintf('基础负荷点数：%d（缺失%d点）\n', N_raw, N_expected - N_raw);

if N_raw < N_expected
    missing = N_expected - N_raw;
    P_load_base = [P_load_base_raw; repmat(P_load_base_raw(end), missing, 1)];
    fprintf('已补齐 %d 点\n', missing);
else
    P_load_base = P_load_base_raw;
end
N = length(P_load_base);

pv_mat = readmatrix('pv_matrix_365x288.csv');
P_pv_full = pv_mat';
P_pv = P_pv_full(:);
if length(P_pv) > N
    P_pv = P_pv(1:N);
elseif length(P_pv) < N
    P_pv = [P_pv; repmat(P_pv(end), N - length(P_pv), 1)];
end
fprintf('光伏数据长度：%d\n', length(P_pv));

%% 3. 参数设置
param.eta_ch = 0.90;
param.eta_dis = 0.90;
param.SOC_min = 0.40;
param.SOC_max = 0.90;
param.SOC_init = 0.65;
param.price_sell = 0.4155;
param.C_bat_unit = 1500;
param.C_pcs_unit = 800;
param.r_om = 0.01;

t_hour = (0:N-1)' * dt;
hour_of_day = mod(t_hour, 24);
is_peak = (hour_of_day >= 6 & hour_of_day < 22);

%% 4. 阶梯电价函数
function [peak_price, valley_price] = get_tiered_price(E_buy_cumulative)
    if E_buy_cumulative <= 3120
        peak_price = 0.617;
        valley_price = 0.307;
    elseif E_buy_cumulative <= 4800
        peak_price = 0.677;
        valley_price = 0.337;
    else
        peak_price = 0.977;
        valley_price = 0.487;
    end
end

%% 5. 储能扫描函数
function results_table = storage_scan(P_load_total, P_pv, param, E_list, P_list, dt, is_peak, no_storage_cost)
    N = length(P_load_total);
    results = [];
    
    for cap = E_list
        for pwr = P_list
            if pwr > cap
                continue;
            end
            
            SOC = zeros(N+1,1);
            SOC(1) = param.SOC_init;
            cumulative_discharge = 0;
            E_buy_cumulative = 0;
            buy_cost = 0;
            sell_income = 0;
            P_grid_buy_max = 0;
            total_sell_energy = 0;
            
            for t = 1:N
                P_net = P_pv(t) - P_load_total(t);
                
                P_ch_max = min(pwr, (param.SOC_max - SOC(t)) * cap / dt / param.eta_ch);
                P_dis_max = min(pwr, (SOC(t) - param.SOC_min) * cap * param.eta_dis / dt);
                
                if P_net > 0
                    P_bat = min(P_net, P_ch_max);
                    SOC(t+1) = SOC(t) + P_bat * dt * param.eta_ch / cap;
                    P_sell = max(0, P_net - P_bat);
                    P_buy = 0;
                else
                    P_bat = max(P_net, -P_dis_max);
                    SOC(t+1) = SOC(t) + P_bat * dt / param.eta_dis / cap;
                    P_buy = max(0, -P_net - P_bat);
                    P_sell = 0;
                end
                
                if P_bat < 0
                    cumulative_discharge = cumulative_discharge + abs(P_bat) * dt;
                end
                P_grid_buy_max = max(P_grid_buy_max, P_buy);
                
                [peak_price, valley_price] = get_tiered_price(E_buy_cumulative);
                if is_peak(t)
                    buy_cost = buy_cost + P_buy * peak_price * dt;
                else
                    buy_cost = buy_cost + P_buy * valley_price * dt;
                end
                sell_income = sell_income + P_sell * param.price_sell * dt;
                total_sell_energy = total_sell_energy + P_sell * dt;
                
                E_buy_cumulative = E_buy_cumulative + P_buy * dt;
            end
            
            annual_cost = buy_cost - sell_income;
            total_pv = sum(P_pv) * dt;
            self_use_rate = (total_pv - total_sell_energy) / total_pv;
            equivalent_cycles = cumulative_discharge / cap;
            inv_cost = cap * param.C_bat_unit + pwr * param.C_pcs_unit;
            annual_om = inv_cost * param.r_om;
            annual_saving = no_storage_cost - annual_cost - annual_om;
            
            if annual_saving > 0
                payback = inv_cost / annual_saving;
            else
                payback = inf;
            end
            
            results = [results; cap, pwr, annual_cost, self_use_rate, ...
                       P_grid_buy_max, equivalent_cycles, inv_cost, payback, annual_saving];
        end
    end
    
    results_table = array2table(results, 'VariableNames', ...
        {'Capacity_kWh', 'Power_kW', 'AnnualCost_Yuan', 'SelfUseRate', ...
         'PeakImport_kW', 'EquivCycles', 'Investment_Yuan', 'Payback_Years', 'AnnualSaving_Yuan'});
end

%% 6. 曲线图绘制函数
function plot_curves(results_table, E_list, P_list, y_col, y_label, title_str, filename)
    figure('Name', title_str, 'NumberTitle', 'off');
    colors = {'r', 'g', 'b', 'm', 'c', 'k'};
    hold on;
    
    for i = 1:length(E_list)
        cap = E_list(i);
        idx = results_table.Capacity_kWh == cap;
        if sum(idx) > 0
            sub_table = results_table(idx, :);
            x_vals = sub_table.Power_kW;
            y_vals = sub_table.(y_col);
            valid = isfinite(y_vals);
            if sum(valid) > 0
                [x_sorted, sidx] = sort(x_vals(valid));
                y_sorted = y_vals(valid);
                y_sorted = y_sorted(sidx);
                plot(x_sorted, y_sorted, 'o-', 'Color', colors{mod(i-1,6)+1}, ...
                    'LineWidth', 1.5, 'MarkerSize', 6, 'DisplayName', sprintf('%d kWh', cap));
            end
        end
    end
    
    xlabel('功率 (kW)');
    ylabel(y_label);
    legend('Location', 'best');
    title(title_str);
    grid on;
    saveas(gcf, filename);
    close(gcf);
end

%% 7. 柱状图绘制函数（自发自用率专用，固定功率10kW）
function plot_selfuse_bar(results_table, E_list, P_list, title_str, filename)
    figure('Name', title_str, 'NumberTitle', 'off');
    
    pwr_fixed = 10;
    idx = results_table.Power_kW == pwr_fixed;
    
    if sum(idx) > 0
        sub_table = results_table(idx, :);
        [cap_sorted, sort_idx] = sort(sub_table.Capacity_kWh);
        self_rates = sub_table.SelfUseRate(sort_idx);
        
        bar(cap_sorted, self_rates * 100);
        xlabel('容量 (kWh)');
        ylabel('自发自用率 (%)');
        title([title_str, ' (功率=', num2str(pwr_fixed), 'kW)']);
        ylim([0, 100]);
        grid on;
        
        for k = 1:length(cap_sorted)
            text(cap_sorted(k), self_rates(k)*100 + 1, ...
                sprintf('%.1f%%', self_rates(k)*100), ...
                'HorizontalAlignment', 'center', 'FontSize', 9);
        end
    else
        text(0.5, 0.5, '无有效数据', 'HorizontalAlignment', 'center', 'FontSize', 12);
        axis off;
        title(title_str);
    end
    
    saveas(gcf, filename);
    close(gcf);
end

%% 8. 三种策略的文件和列名
ev_files = {'EV_S1_home_charge_result.csv', ...
            'EV_S2_valley_delay_result.csv', ...
            'EV_S3_pv_surplus_result.csv'};
strategy_names = {'S1到家即充', 'S2谷时延迟', 'S3光伏富余'};
total_cols = {'P_total_S1_kW', 'P_total_S2_kW', 'P_total_S3_kW'};

E_bat_list = [5, 10, 15, 20, 30, 40];
P_bat_list = [2, 3, 5, 7, 10];

all_results = struct();

%% 9. 主循环：对每种策略分别处理
for i = 1:3
    fprintf('\n========================================\n');
    fprintf('处理策略：%s\n', strategy_names{i});
    fprintf('========================================\n');
    
    ev_table = readtable(ev_files{i});
    P_total_raw = ev_table.(total_cols{i});
    
    if length(P_total_raw) < N_expected
        missing = N_expected - length(P_total_raw);
        P_total = [P_total_raw; repmat(P_total_raw(end), missing, 1)];
        fprintf('已补齐 %d 点\n', missing);
    else
        P_total = P_total_raw;
    end
    
    % 计算无储能成本
    E_buy_cumulative = 0;
    buy_cost = 0;
    sell_income = 0;
    for t = 1:N
        P_net = P_pv(t) - P_total(t);
        if P_net > 0
            P_sell = P_net;
            P_buy = 0;
        else
            P_buy = -P_net;
            P_sell = 0;
        end
        [peak_price, valley_price] = get_tiered_price(E_buy_cumulative);
        if is_peak(t)
            buy_cost = buy_cost + P_buy * peak_price * dt;
        else
            buy_cost = buy_cost + P_buy * valley_price * dt;
        end
        sell_income = sell_income + P_sell * param.price_sell * dt;
        E_buy_cumulative = E_buy_cumulative + P_buy * dt;
    end
    no_storage_cost = buy_cost - sell_income;
    fprintf('无储能年净电费：%.2f 元\n', no_storage_cost);
    
    % 储能扫描
    results_table = storage_scan(P_total, P_pv, param, E_bat_list, P_bat_list, dt, is_peak, no_storage_cost);
    
    % 保存储能扫描结果
    writetable(results_table, sprintf('storage_scan_%s.csv', ev_files{i}(4:5)));
    fprintf('已保存：storage_scan_%s.csv\n', ev_files{i}(4:5));
    
    % 保存成本与回收期分析表
    cost_payback = results_table(:, {'Capacity_kWh', 'Power_kW', 'Investment_Yuan', 'Payback_Years', 'AnnualSaving_Yuan'});
    writetable(cost_payback, sprintf('cost_payback_%s.csv', ev_files{i}(4:5)));
    
    % 保存电池等效循环次数分析
    cycle_analysis = results_table(:, {'Capacity_kWh', 'Power_kW', 'EquivCycles'});
    writetable(cycle_analysis, sprintf('cycle_analysis_%s.csv', ev_files{i}(4:5)));
    
    % ========== 绘图部分 ==========
    
    % 曲线图1：年电费
    plot_curves(results_table, E_bat_list, P_bat_list, 'AnnualCost_Yuan', '年电费 (元)', ...
        sprintf('年电费 - %s', strategy_names{i}), sprintf('fig_cost_curves_%s.png', ev_files{i}(4:5)));
    
    % 柱状图：自发自用率（固定功率10kW）
    plot_selfuse_bar(results_table, E_bat_list, P_bat_list, ...
        sprintf('自发自用率 - %s', strategy_names{i}), sprintf('fig_selfuse_bar_%s.png', ev_files{i}(4:5)));
    
    % 曲线图3：购电峰值
    plot_curves(results_table, E_bat_list, P_bat_list, 'PeakImport_kW', '购电峰值 (kW)', ...
        sprintf('购电峰值 - %s', strategy_names{i}), sprintf('fig_peak_curves_%s.png', ev_files{i}(4:5)));
    
    % 曲线图4：等效循环次数
    plot_curves(results_table, E_bat_list, P_bat_list, 'EquivCycles', '等效循环次数', ...
        sprintf('循环次数 - %s', strategy_names{i}), sprintf('fig_cycle_curves_%s.png', ev_files{i}(4:5)));
    
    % ========== 候选方案 ==========
    
    [~, idx_econ] = min(results_table.Payback_Years);
    econ = results_table(idx_econ, :);
    
    cost_norm = results_table.AnnualCost_Yuan / max(results_table.AnnualCost_Yuan);
    self_norm = 1 - results_table.SelfUseRate / max(results_table.SelfUseRate);
    pay_norm = results_table.Payback_Years / max(results_table.Payback_Years);
    cycle_norm = results_table.EquivCycles / max(results_table.EquivCycles);
    score = 0.3*cost_norm + 0.3*self_norm + 0.3*pay_norm + 0.1*cycle_norm;
    [~, idx_bal] = min(score);
    balanced = results_table(idx_bal, :);
    
    [~, idx_rob] = min(results_table.PeakImport_kW);
    robust = results_table(idx_rob, :);
    
    candidates = [econ; balanced; robust];
    cand_names = {'Economic'; 'Balanced'; 'Robust'};
    cand_table = table(cand_names, candidates.Capacity_kWh, candidates.Power_kW, ...
        candidates.AnnualCost_Yuan, candidates.SelfUseRate, candidates.PeakImport_kW, ...
        candidates.EquivCycles, candidates.Investment_Yuan, candidates.Payback_Years, ...
        'VariableNames', {'Plan', 'Cap_kWh', 'Pow_kW', 'Cost_Yuan', 'SelfUseRate', ...
        'Peak_kW', 'Cycles', 'Inv_Yuan', 'Payback_Yrs'});
    
    writetable(cand_table, sprintf('candidates_%s.csv', ev_files{i}(4:5)));
    
    all_results.(sprintf('S%d', i)).table = results_table;
    all_results.(sprintf('S%d', i)).no_storage_cost = no_storage_cost;
    
    fprintf('\n--- %s 候选方案 ---\n', strategy_names{i});
    disp(cand_table);
end

