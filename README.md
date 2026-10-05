# Let me drive oxcart

Dragon's Dogma 2 / REFramework 原生司机位驾驶脚本。当前分支：`experimental/native-interaction`。
历史非原生方向保存在 `direction/non-native`；旧根位置约束不再用于主驾驶入口。

## 操作

通用设置中的 **Let me drive** 请求玩家原生进入司机位。
**E / X（Square）** 执行同一入口，但要求玩家与车体前侧检测点的距离严格小于 **2**，且玩家不在原生乘客位或 OJR 座位中。
上车中及已驾驶时不会重复进入；驾驶时 E / X 使用独立的预设轮询映射。

**A/D / 左摇杆** 转向，**W/S / RB/LB** 加减速：Wait → Walk → Run → Dash。
**手柄 A** 仍由游戏原生处理下车动画；映射的键盘 Stand（默认 Space）请求原生退出。
不再使用 Shift + 1–4、G/RT 或鼠标驾驶。

请求上车时立即让牛 Wait，并覆盖 Walk/Run/Dash 请求。
实际提交玩家上车请求后保留 5 秒静止时间，期间不接受加速；暂停时间不计入这 5 秒。
检测车体附近 12 距离内的司机；未上车时也将真实位置一次性传送到车后 50 距离。
司机已占座或正在上车时先请求原生退出，确认解绑后再传送，再请求玩家进入。司机不会在解除控制时被传回来。

## 随从

玩家原生绑定司机位后，自动将缺失随从真实传送到车前铰链附近，并请求原生乘客位。
通用设置 **Let pawns sit** 可以重复补位；已坐稳的随从不移动，失败的请求先退出，再重新补位。
主 Pawn 使用 Point 2，另外两个随从依次选择其他空乘客位，通常为 Point 3 / Point 4。

确认原生坐稳后才开启随从伤害保护和座位锁定：阻止外部主动作及结束/取消交互请求，FSM 保持运行。
玩家不受这项保护或锁定影响。上车寻路和动画阶段也不锁定。
**Let pawns stand** 请求原生起身；玩家离开车前检测点超过 10 距离时自动请求起身。
退出、车体损坏/失效或随从离开当前座位时取消保护和锁定。退出不传送随从。

## 座位与镜头预设

只使用当前车种对应的预设。x/y/z/yaw 作用于骨架位置和朝向，不改角色根位置、碰撞位置或原生座位绑定。
定位原点优先使用车体的 MoveFloor 子节点；没有该节点时使用车体 Transform。它是模型节点原点，不是实时计算的包围盒底部中心。
预设保留现有 X/Z 定位，正 Y 沿车体朝上的法线；原生节点 Y 朝下时进行纠正。
骨架朝向完整跟随车体的俯仰和侧倾：模型 +Y 对齐车体上方向，模型 -Z 对齐预设 yaw，再换算成角色局部旋转。不写角色根位置或根骨世界旋转，不镜像预设位置。
照片模式同样应用骨架预设，但不请求动画，也不应用驾驶镜头参数。
随从默认启用随机坐姿请求，玩家默认关闭随机坐姿。原生座位的动画接管会使这些请求无法生效；目前尚未解决，不拦截维持座位绑定的原生交互。
Camera offset 已移除；旧配置中的偏移参数不再读取或保存。
预设内的 FOV 和 Camera distance 在原生上车请求后 5 秒才生效。
之后切换预设不重新计时；下车和脚本重置恢复镜头原值。技能栏仅暂停绘制，退出后自然恢复。

## 检测点与兼容

车前方向使用牛与车体的水平连线，静止时也有效；退化时使用车体轴向。
默认检测点在车体原点前方 1.5 距离，可在 aelinore debug tool 的距离功能中校准。
两个脚本共享 OxcartFrontProbe.json。OJR 为可选依赖，驾驶期间通过共享控制 lease 避免同时驱动车辆。

## 测试与 LOG

`tests/run-tests.ps1` 验证当前原生入口、等待/镜头计时、随从分配/补位/保护/骨架、退出与清理、热键及配置迁移。
`tests/run-npc-monitor-tests.ps1` 验证独立 debug 工具。
旧非原生断言文件仅为开发历史，不参与当前原生测试入口。

原生交互 LOG：`reframework/data/AelinoreNativeSeat_*.log`、`AelinoreNativePawns_*.log`。
主 Pawn 只读跟踪和道路记录仍在 debug 工具中；各次记录使用独立文件名。

### 原生坐姿动画测试

重载脚本后，在 debug 工具的 **Native seated animation test** 点击 **Start seat animation trace (60s)**，再用 **Let me drive** 上车，让主 Pawn 原生坐稳。
点击 **Test seat execJack once (3s)**，观察主 Pawn 是否换姿势、是否立刻恢复或出现无动画姿态。输入值是座位 MotionJack 的 FSM 状态名，不保证普通 Action name 或动画文件名在该状态机中存在；默认 `LivSitChairCrosslegs` 仅为候选。
测试调用当前主 Pawn 座位自己的 `execJack(string)` 一次，3 秒后请求原生循环恢复。不结束交互、不移动根位置、不冻结 FSM，也不修改共享的静态动画名。
记录期间暂不向主 Pawn发送 MOD 的普通/随机坐姿请求，避免干扰比较；另两个 Pawn 不记录、不参与此动画测试。
点击 **Stop seat animation trace / restore** 提前结束；否则 60 秒自动保存。LOG 为 `reframework/data/AelinoreSeatAnimation_*.log`，各次独立命名，记录 native/test 请求来源、MotionJack 状态、动作 Bank/Motion、根位置和 continueInteract 次数。
暂停不消耗 3 秒恢复计时；主 Pawn 已离开座位时不再请求恢复动画。恢复是原生循环请求，不表示已经通过游戏内验证。
模拟测试不能替代游戏内确认。新版本先短测上车 5 秒静止、随从坐姿/抗攻击、切换预设和自然下车，再进行长途测试。
