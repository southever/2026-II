function [SOC,P_EV,P_total] = SOC_update(EV_event_table,T_base,strategy)
%% ==========================================================
% 功能：
% 根据EV_event_table生成全年SOC曲线、EV充电功率和总负荷
% 可切换三种充电策略：'S1' 到家即充, 'S2' 谷时延迟, 'S3' 光伏富余优先
%
% 输入：
% EV_event_table : 365天EV出行事件表
% T_base         : 基础负荷/PV数据 5分钟分辨率表
% strategy       : 'S1','S2','S3'
%
% 输出：
% SOC    : 全年5分钟SOC曲线
% P_EV   : 全年5分钟EV充电功率(kW)
% P_total: 全年总负荷(kW)
% ==========================================================
%% 1. 参数设置
E_ev_bat = 62.5;   % kWh
P_ev_ch  = 7;      % kW
eta_ev   = 0.90;   % 充电效率

SOC_init    = 0.90;
SOC_trigger = 0.40;
SOC_min     = 0.20;
SOC_target  = 0.90;
SOC_long    = 1.00;

dt_hour = 5/60; % 5分钟时间步

N = height(T_base);

SOC = zeros(N,1);
P_EV = zeros(N,1);
P_total = zeros(N,1);

soc_now = SOC_init;

%% 2. 循环每日更新SOC
for d = 1:365
    idx_day = find(T_base.day_index == d);
    if isempty(idx_day)
        continue;
    end
    
    %% 当天行驶耗电
    drive_energy = EV_event_table.drive_energy_kWh(d);
    soc_after_drive = max(soc_now - drive_energy/E_ev_bat, SOC_min);
    soc_now = soc_after_drive;
    
    %% 判断是否需要充电
    need_charge = false;
    target_soc = SOC_target;
    
    if soc_after_drive < SOC_trigger
        need_charge = true;
        target_soc = SOC_target;
    end
    
    if EV_event_table.need_sunday_charge(d)
        need_charge = true;
        target_soc = max(target_soc, SOC_target);
    end
    
    if EV_event_table.need_precharge(d)
        need_charge = true;
        target_soc = SOC_long;
    end
    
    %% 策略决定充电时间
    if need_charge
        switch strategy
            case 'S1' % 到家即充
                idx_charge = idx_day(T_base.time_hour(idx_day) >= 19);
            case 'S2' % 谷时延迟
                idx_charge = idx_day(T_base.time_hour(idx_day) >= 22);
            case 'S3' % 光伏富余优先
                % 白天光伏富余充电
                idx_charge = idx_day(T_base.pv_kW(idx_day) > T_base.load_kW(idx_day));
                % 晚间兜底补至目标SOC
                idx_charge = [idx_charge; idx_day(T_base.time_hour(idx_day) >= 22)];
            otherwise
                error('策略选择错误，必须为S1,S2或S3');
        end
        
        for k = 1:length(idx_charge)
            i = idx_charge(k);
            if soc_now >= target_soc
                break;
            end
            
            energy_need = (target_soc - soc_now)*E_ev_bat;
            energy_max = P_ev_ch*dt_hour*eta_ev;
            energy_to_bat = min(energy_need, energy_max);
            energy_from_grid = energy_to_bat / eta_ev;
            
            P_EV(i) = energy_from_grid/dt_hour;
            soc_now = soc_now + energy_to_bat/E_ev_bat;
            soc_now = min(soc_now,target_soc);
            
            SOC(i) = soc_now;
        end
    end
    
    %% 填充未赋值SOC
    for k = 1:length(idx_day)
        i = idx_day(k);
        if SOC(i) == 0
            SOC(i) = soc_now;
        end
    end
    
    soc_now = SOC(idx_day(end)); % 更新下一天初始SOC
end

%% 3. 生成总负荷
P_total = T_base.load_kW + P_EV;

end