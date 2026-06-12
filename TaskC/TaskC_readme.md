# TASK C：EV负荷建模与充电策略分析

>帮助梳理TASK C文件夹下的各个文件是在干什么，以及对当前TaskC进展有一个概览，详细内容可以看 TaskC详细策略.md
---

## 一、任务目标

基于微电网5分钟分辨率基础负荷数据，建立家庭电动汽车（EV）全年出行与充电模型，在统一出行行为条件下设计并比较三种典型充电策略

* EV-S1 到家即充
* EV-S2 谷时延迟充电
* EV-S3 光伏富余优先充电

分析EV接入后对家庭负荷特性的影响，并评估不同充电策略在削峰填谷和提高光伏利用率方面的效果

---

## 二、项目文件结构说明

### 1. 初始数据（来自成员B）

* microgrid_5min_integrated_data.csv
  全年5分钟分辨率微电网数据，包含基础负荷、光伏出力等

### 2. 数据处理文件

* 对原始5分钟数据进行连续性检查、缺失值处理、负值修正
* 生成辅助列：日索引、小时小数、是否周末、光伏富余等
* 输出文件：C_input_base_5min.csv

### 3. SOC更新模块

* SOC_update.m
* 功能：根据EV事件表和基础负荷/PV数据计算全年5分钟SOC、EV充电功率、总负荷
* 三种策略（S1/S2/S3）共用函数，输入不同策略参数即可生成对应充电曲线

### 4. EV事件生成模块

* ev_events_generation.m
* 功能：生成EV_event_table.csv
* 内容：365天出行事件、每日行驶里程、长途日标记、SOC目标、是否周日补电

### 5. EV策略模型

* EV_S1.m：到家即充，输出EV_S1_home_charge_result.csv和fig_EV_S1
* EV_S2.m：谷时延迟，输出EV_S2_valley_delay_result.csv和fig_EV_S2
* EV_S3.m：光伏优先，输出EV_S3_pv_surplus_result.csv和fig_EV_S3

### 6. 策略统一对比

* EV_compare.m
* 输入三策略结果CSV，输出EV_strategy_compare.csv
* 输出图表到fig_EV_compare，包含月平均SOC、SOC箱线图、月度充电量、典型日总负荷、峰值负荷等

---

## 三、EV事件生成

* 生成全年365天EV出行事件
* 工作日/周末规律+随机长途日
* 计算行驶耗电、标记长途预充、周日补电
* 输出EV_event_table.csv

---

## 四、EV充电策略

### EV-S1 到家即充

* 19:00开始充电，直至达到日常或长途目标SOC
* 输出EV_S1_home_charge_result.csv和fig_EV_S1

### EV-S2 谷时延迟

* 22:00后开始充电
* 输出EV_S2_valley_delay_result.csv和fig_EV_S2

### EV-S3 光伏优先

* 白天优先利用光伏富余充电，晚间谷时补充不足SOC
* 输出EV_S3_pv_surplus_result.csv和fig_EV_S3

---

## 五、统一策略对比（EV_compare）

* 输入：三策略结果CSV
* 输出：EV_strategy_compare.csv
* 图表输出到fig_EV_compare，包括月平均SOC、SOC箱线图、月度EV充电量、典型日总负荷、峰值负荷等

---

## 六、结果分析

### 年度充电量

* 三策略年EV充电量差异小于2%
* 总能耗相近，差异主要体现在充电时段

### 峰值负荷

* EV-S2、EV-S3全年峰值低于EV-S1
* EV-S2晚高峰峰值最明显降低

### SOC情况

* EV-S1：SOC高且平稳
* EV-S2：SOC最低
* EV-S3：SOC中等，同时提高光伏利用率

### 综合评价

| 策略  | 特点                                       |
| ----- | ------------------------------------------ |
| EV-S1 | 用户体验最好，晚高峰压力大                 |
| EV-S2 | 削峰效果最佳，晚高峰最低                   |
| EV-S3 | 兼顾削峰和光伏利用，晚高峰中等，PV自用率高 |
