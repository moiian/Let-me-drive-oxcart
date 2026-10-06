# 实现参考与本地对照记录

## 来源说明

- **Better Oxcarts Redux**：早期牛车研究的参考之一，主要用于认识牛车缓存对象、ActionManager 移动请求与伤害入口；Oxcarts Journey Redux 的早期实现也与其有承接关系。当前 Let me drive oxcart 使用自己的驾驶会话、转向、角色锚定和对象范围保护，不依赖 `_NickCore`。
- **Immersive Interactables Enhanced**（[MOD 页面](https://www.nexusmods.com/dragonsdogma2/mods/1518)）：原生司机位试验的思路参考，尤其是 `CharacterType` 的 Player 标志和 `InteractManager.requestInteractFromAI`。当前实现限定到本车 `IsDriver` 返回的入口，验证实际司机位绑定，并独立处理司机退出、一次性传送、驾驶状态、暂停与清理。
- **xyzkljl1/MyDD2Mod/CameraDistance**：相机距离字段的识别参考。

这些参考不应因后续重构而从历史或说明中删除。相同的游戏类型、字段、方法签名及动作名称属于接口使用证据，不足以单独证明复制了独特实现。重构同样不能改变历史来源。

## 2026-10-06 对照范围与结论

检查当前 `reframework/autorun` 下的 Lua 源码，对照本地 `Better Oxcats Redux/reframework/autorun/BetterOxcartsRedux.lua` 和 `Immersive Interactables Enhanced/autorun` 下的 Lua 文件，共 88 个参考文件。

去掉空行、整行注释，统一空白和引号后，没有检出同时包含至少三个非结构语句、累计至少 140 字符的连续相同行块。这只是文字复用筛查，不是完整算法比较或原创性的证明。另人工查看了下列相关实现：

| 位置 | 相似点 | 当前实现的区别 |
| --- | --- | --- |
| `discover()` / Better 的 `get_ox()` | 从 NPCManager 的牛车缓存获取牛 | 当前还解析连接部件、查找最近车体、选择 MoveFloor 锚点及附近司机；没有移植其城市坐标表、付费乘客条件或 HUD 文本改写 |
| `action()` / Better 的 `handle_move()` | 请求 Wait、Walk、Run、Dash | 当前用原生司机位会话、可重绑输入和牛的方向控制；没有移植其 NickCore 回调或独特的受击关键词列表 |
| 伤害 hook / Better 的伤害 hook | 使用相同 HitController API 和 DamageInfo 字段 | 当前按本车和已锚定随从的对象地址限定范围；没有司机／守卫 ID 倍率表、伤害输出倍率、1999 阈值或通用异常状态列表 |
| 司机位会话 / IIE 的 `_patch_search_point()`、王座请求 | 临时开放 Player 标志、请求并保留原生结果 | 当前只操作确定的司机入口，不做通用物件扫描、图标替换、交互距离扩展或 IrisPrompt 仲裁；实际绑定确认与清理属于本项目会话 |

## 本次实质重构

- 将司机位的权限授予、请求提交、资源释放拆成明确的会话操作；清理只撤销本会话添加的 Player 位，保留期间发生的其他权限变化。预先已有 Player 权限时不撤销。
- 结果引用只在 `add_ref()` 成功后归本会话所有，释放一次；保留失败不会错误 `release()`。
- 将伤害接收对象分类集中为“锚定随从”和“正在驾驶的牛车”两项规则。两种原生伤害入口使用同一分类器，保持司机、守卫、玩家及其他牛车不受保护。
- 不用改名、改排版作为原创性证据，不修改已验证的上车／退出／传送流程、预设或等待时间。

对应新增测试覆盖权限变化保留、既有权限保留、引用保留失败与重复清理；原生交互、保护范围、照片模式和预设测试继续运行。
