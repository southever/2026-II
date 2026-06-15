%% TaskE: Storage Dispatch Strategy Optimization
% Fixed battery configuration: 5 kWh / 2 kW.
% Strategies:
% 1) PV_FIRST: PV self-consumption first.
% 2) TOU_PRICE: peak-valley price dispatch.
% 3) DAYAHEAD_FORECAST: rule-based day-ahead forecast.
% 4) ML_FORECAST: lightweight linear-regression day-ahead forecast.

clear; clc; close all;

%% 1. Parameters
dt = 5/60;
N_step_day = 288;
N_expected = 365 * N_step_day;

param.cap = 5;
param.pwr = 2;
param.eta_ch = 0.90;
param.eta_dis = 0.90;
param.SOC_min = 0.40;
param.SOC_max = 0.90;
param.SOC_init = 0.65;
param.SOC_forecast_target = 0.70;
param.price_sell = 0.4155;

ev_files = {'../TaskC/EV_S1_home_charge_result.csv', ...
            '../TaskC/EV_S2_valley_delay_result.csv', ...
            '../TaskC/EV_S3_pv_surplus_result.csv'};
ev_cols = {'P_total_S1_kW', 'P_total_S2_kW', 'P_total_S3_kW'};
ev_names = {'EV-S1 home charge', 'EV-S2 valley delay', 'EV-S3 PV surplus'};

strategy_ids = {'PV_FIRST', 'TOU_PRICE', 'DAYAHEAD_FORECAST', 'ML_FORECAST'};
strategy_names = {'PV first', 'TOU price', 'Rule forecast', 'ML forecast'};

%% 2. Load PV data
pv_mat = readmatrix('../TaskB/pv_matrix_365x288.csv');
P_pv = pv_mat';
P_pv = P_pv(:);
P_pv = align_length(P_pv, N_expected);

t_hour = (0:N_expected-1)' * dt;
hour_of_day = mod(t_hour, 24);
is_peak = (hour_of_day >= 6 & hour_of_day < 22);
day_index = floor((0:N_expected-1)' / N_step_day) + 1;

%% 3. Run 3 EV scenarios x 4 storage strategies
all_rows = {};
all_ts_s2 = table();
ml_forecast_result = table();

for e = 1:numel(ev_files)
    ev_table = readtable(ev_files{e});
    P_load = align_length(ev_table.(ev_cols{e}), N_expected);
    [ml_pred_deficit, ml_table] = build_ml_forecast(P_load, P_pv, dt, day_index);

    for s = 1:numel(strategy_ids)
        [metric, ts] = simulate_strategy(P_load, P_pv, param, strategy_ids{s}, ...
            dt, is_peak, hour_of_day, day_index, ml_pred_deficit);

        all_rows(end+1, :) = {ev_names{e}, strategy_ids{s}, strategy_names{s}, ...
            metric.E_buy_year, metric.E_sell_year, metric.Cost_year, ...
            metric.R_self_use, metric.P_grid_peak, metric.N_cycle, ...
            metric.E_bat_charge_year, metric.E_bat_discharge_year};

        if e == 2
            ts.EVScenario = repmat(string(ev_names{e}), height(ts), 1);
            ts.StrategyID = repmat(string(strategy_ids{s}), height(ts), 1);
            ts.StrategyName = repmat(string(strategy_names{s}), height(ts), 1);
            all_ts_s2 = [all_ts_s2; ts]; %#ok<AGROW>

            if strcmp(strategy_ids{s}, 'ML_FORECAST')
                ml_table.EVScenario = repmat(string(ev_names{e}), height(ml_table), 1);
                ml_forecast_result = ml_table;
            end
        end
    end
end

result_table = cell2table(all_rows, 'VariableNames', ...
    {'EVScenario', 'StrategyID', 'StrategyName', 'E_buy_year_kWh', ...
     'E_sell_year_kWh', 'Cost_year_Yuan', 'R_self_use', 'P_grid_peak_kW', ...
     'N_cycle_per_year', 'E_bat_charge_year_kWh', 'E_bat_discharge_year_kWh'});

writetable(result_table, 'strategy_compare.csv');
writetable(all_ts_s2, 'strategy_timeseries_S2.csv');
writetable(ml_forecast_result, 'ml_forecast_result.csv');

%% 4. Figures
main_idx = strcmp(result_table.EVScenario, 'EV-S2 valley delay');
main_table = result_table(main_idx, :);

plot_bar(main_table.StrategyName, main_table.Cost_year_Yuan, ...
    'Annual net cost (Yuan/year)', 'EV-S2: Annual Net Cost', 'fig_strategy_cost_compare.png');
plot_bar(main_table.StrategyName, main_table.R_self_use * 100, ...
    'PV self-use rate (%)', 'EV-S2: PV Self-use Rate', 'fig_strategy_selfuse_compare.png');
plot_bar(main_table.StrategyName, main_table.P_grid_peak_kW, ...
    'Peak grid import (kW)', 'EV-S2: Peak Grid Import', 'fig_strategy_peak_compare.png');
plot_bar(main_table.StrategyName, main_table.N_cycle_per_year, ...
    'Equivalent cycles (cycles/year)', 'EV-S2: Battery Cycles', 'fig_strategy_cycle_compare.png');

plot_typical_day(all_ts_s2, 172, 'fig_strategy_typical_day.png');
plot_ml_forecast(ml_forecast_result, 'fig_ml_forecast_compare.png');

disp(result_table);

%% Local functions
function x = align_length(x, N)
    x = x(:);
    if length(x) < N
        x = [x; repmat(x(end), N - length(x), 1)];
    elseif length(x) > N
        x = x(1:N);
    end
end

function price = get_price(E_buy_cumulative, is_peak_step)
    if E_buy_cumulative <= 3120
        peak_price = 0.617; valley_price = 0.307;
    elseif E_buy_cumulative <= 4800
        peak_price = 0.677; valley_price = 0.337;
    else
        peak_price = 0.977; valley_price = 0.487;
    end
    if is_peak_step
        price = peak_price;
    else
        price = valley_price;
    end
end

function [pred_deficit, ml_table] = build_ml_forecast(P_load, P_pv, dt, day_index)
    n_day = max(day_index);
    daily_load = zeros(n_day, 1);
    daily_pv = zeros(n_day, 1);
    daily_deficit = zeros(n_day, 1);
    month_id = repelem((1:12)', ceil(n_day/12));
    month_id = month_id(1:n_day);

    for d = 1:n_day
        idx = day_index == d;
        daily_load(d) = sum(P_load(idx)) * dt;
        daily_pv(d) = sum(P_pv(idx)) * dt;
        daily_deficit(d) = max(0, daily_load(d) - daily_pv(d));
    end

    X = [];
    y = [];
    row_day = [];
    for d = 4:n_day
        prev3 = d-3:d-1;
        X(end+1, :) = [1, month_id(d), double(mod(d,7) == 0 || mod(d,7) == 6), ...
            daily_pv(d-1), daily_load(d-1), daily_deficit(d-1), ...
            mean(daily_pv(prev3)), mean(daily_load(prev3))]; %#ok<AGROW>
        y(end+1, 1) = daily_deficit(d); %#ok<AGROW>
        row_day(end+1, 1) = d; %#ok<AGROW>
    end

    n_train = floor(0.70 * size(X, 1));
    beta = X(1:n_train, :) \ y(1:n_train);
    pred_y = max(0, X * beta);

    pred_deficit = daily_deficit;
    pred_deficit(row_day) = pred_y;

    is_test = false(size(row_day));
    is_test(n_train+1:end) = true;
    charge_flag = pred_y > 5;
    ml_table = table(row_day, daily_deficit(row_day), pred_y, charge_flag, is_test, ...
        'VariableNames', {'Day', 'ActualDeficit_kWh', 'PredictedDeficit_kWh', ...
        'NightChargeFlag', 'IsTestSet'});
end

function [metric, ts] = simulate_strategy(P_load, P_pv, param, strategy_id, dt, is_peak, hour_of_day, day_index, ml_pred_deficit)
    N = length(P_load);
    SOC = zeros(N+1, 1);
    SOC(1) = param.SOC_init;

    P_bat = zeros(N, 1);
    P_grid_buy = zeros(N, 1);
    P_grid_sell = zeros(N, 1);
    price_buy = zeros(N, 1);

    E_buy_cumulative = 0;
    buy_cost = 0;
    sell_income = 0;
    E_ch = 0;
    E_dis = 0;

    daily_deficit = zeros(max(day_index), 1);
    for d = 1:max(day_index)
        idx = day_index == d;
        daily_deficit(d) = max(0, sum((P_load(idx) - P_pv(idx)) * dt));
    end

    for t = 1:N
        net = P_pv(t) - P_load(t);
        P_ch_max = min(param.pwr, (param.SOC_max - SOC(t)) * param.cap / dt / param.eta_ch);
        P_dis_max = min(param.pwr, (SOC(t) - param.SOC_min) * param.cap * param.eta_dis / dt);
        P_ch = 0;
        P_dis = 0;

        switch strategy_id
            case 'PV_FIRST'
                if net > 0
                    P_ch = min(net, P_ch_max);
                else
                    P_dis = min(-net, P_dis_max);
                end

            case 'TOU_PRICE'
                if net > 0
                    P_ch = min(net, P_ch_max);
                elseif is_peak(t)
                    P_dis = min(-net, P_dis_max);
                elseif SOC(t) < 0.55
                    target_power = (0.55 - SOC(t)) * param.cap / dt / param.eta_ch;
                    P_ch = min([param.pwr, P_ch_max, target_power]);
                end

            case 'DAYAHEAD_FORECAST'
                d = min(day_index(t) + 1, max(day_index));
                tomorrow_deficit = daily_deficit(d);
                if net > 0
                    P_ch = min(net, P_ch_max);
                elseif is_peak(t)
                    P_dis = min(-net, P_dis_max);
                elseif ~is_peak(t) && tomorrow_deficit > param.cap && SOC(t) < param.SOC_forecast_target
                    target_power = (param.SOC_forecast_target - SOC(t)) * param.cap / dt / param.eta_ch;
                    P_ch = min([param.pwr, P_ch_max, target_power]);
                end

            case 'ML_FORECAST'
                d = min(day_index(t) + 1, max(day_index));
                tomorrow_deficit = ml_pred_deficit(d);
                if net > 0
                    P_ch = min(net, P_ch_max);
                elseif is_peak(t)
                    P_dis = min(-net, P_dis_max);
                elseif ~is_peak(t) && tomorrow_deficit > param.cap && SOC(t) < param.SOC_forecast_target
                    target_power = (param.SOC_forecast_target - SOC(t)) * param.cap / dt / param.eta_ch;
                    P_ch = min([param.pwr, P_ch_max, target_power]);
                end
        end

        if P_ch > 0
            SOC(t+1) = SOC(t) + P_ch * dt * param.eta_ch / param.cap;
            grid_net = net - P_ch;
            P_grid_sell(t) = max(0, grid_net);
            P_grid_buy(t) = max(0, -grid_net);
            P_bat(t) = P_ch;
            E_ch = E_ch + P_ch * dt;
        elseif P_dis > 0
            SOC(t+1) = SOC(t) - P_dis * dt / param.eta_dis / param.cap;
            grid_net = net + P_dis;
            P_grid_sell(t) = max(0, grid_net);
            P_grid_buy(t) = max(0, -grid_net);
            P_bat(t) = -P_dis;
            E_dis = E_dis + P_dis * dt;
        else
            SOC(t+1) = SOC(t);
            P_grid_sell(t) = max(0, net);
            P_grid_buy(t) = max(0, -net);
        end

        price_buy(t) = get_price(E_buy_cumulative, is_peak(t));
        buy_cost = buy_cost + P_grid_buy(t) * price_buy(t) * dt;
        sell_income = sell_income + P_grid_sell(t) * param.price_sell * dt;
        E_buy_cumulative = E_buy_cumulative + P_grid_buy(t) * dt;
    end

    E_buy_year = sum(P_grid_buy) * dt;
    E_sell_year = sum(P_grid_sell) * dt;
    total_pv = sum(P_pv) * dt;

    metric.E_buy_year = E_buy_year;
    metric.E_sell_year = E_sell_year;
    metric.Cost_year = buy_cost - sell_income;
    metric.R_self_use = (total_pv - E_sell_year) / total_pv;
    metric.P_grid_peak = max(P_grid_buy);
    metric.N_cycle = E_dis / param.cap;
    metric.E_bat_charge_year = E_ch;
    metric.E_bat_discharge_year = E_dis;

    ts = table((1:N)', day_index, hour_of_day, P_load, P_pv, SOC(1:N), P_bat, ...
        P_grid_buy, P_grid_sell, price_buy, ...
        'VariableNames', {'Step', 'Day', 'Hour', 'P_load_kW', 'P_pv_kW', ...
        'SOC_bat', 'P_bat_kW', 'P_grid_buy_kW', 'P_grid_sell_kW', 'Price_buy_Yuan_per_kWh'});
end

function plot_bar(labels, values, y_label, title_str, filename)
    figure('Visible', 'off');
    bar(values);
    set(gca, 'XTickLabel', labels, 'XTickLabelRotation', 20);
    ylabel(y_label);
    title(title_str);
    grid on;
    saveas(gcf, filename);
    close(gcf);
end

function plot_typical_day(ts, day_no, filename)
    figure('Visible', 'off');
    strategies = unique(ts.StrategyID, 'stable');
    tiledlayout(numel(strategies), 1);
    for i = 1:numel(strategies)
        idx = strcmp(ts.StrategyID, strategies(i)) & ts.Day == day_no;
        sub = ts(idx, :);
        nexttile;
        yyaxis left;
        plot(sub.Hour, sub.SOC_bat * 100, 'LineWidth', 1.2);
        ylabel('SOC (%)');
        yyaxis right;
        plot(sub.Hour, sub.P_bat_kW, 'LineWidth', 1.2);
        ylabel('Battery kW');
        title(string(sub.StrategyName(1)));
        grid on;
        xlim([0, 24]);
    end
    xlabel('Hour');
    saveas(gcf, filename);
    close(gcf);
end

function plot_ml_forecast(ml_table, filename)
    if isempty(ml_table)
        return;
    end
    figure('Visible', 'off');
    plot(ml_table.Day, ml_table.ActualDeficit_kWh, 'LineWidth', 1.2); hold on;
    plot(ml_table.Day, ml_table.PredictedDeficit_kWh, '--', 'LineWidth', 1.2);
    xlabel('Day');
    ylabel('Next-day deficit (kWh)');
    title('ML forecast: actual vs predicted deficit');
    legend('Actual', 'Predicted', 'Location', 'best');
    grid on;
    saveas(gcf, filename);
    close(gcf);
end
