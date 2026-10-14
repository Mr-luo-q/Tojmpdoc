# Gym 接口要求与 SimuHome 现状差异分析

## 1. Gym 接口是什么

Gym 是强化学习领域的一套环境接口标准，最早由 OpenAI Gym 提出，现在由开源项目 Gymnasium 延续维护。它规定的是“环境和训练循环之间怎么说话”，不规定强化学习算法本身怎么实现。

用一句话概括：在 RL 系统里，智能体负责决策，环境负责响应；Gym 规定这两者之间的调用契约。

```
        RL 训练循环
  policy / value / replay buffer
              |  action
              v
      +------------------+
      |   Gym 接口契约    |  reset / step / space / seed
      +------------------+
              |  observation / reward / terminated / truncated / info
              v
      +------------------+
      | 环境（世界/沙盒）  |  SimuHome、HomeEnv、真机适配器……
      +------------------+
```

只要一个模拟器按这套契约暴露自己，它就能被标准 RL 训练器、评测脚本、vector env 包装等工具接管。HomeFlow 附录 A.3 的做法就是给 HomeEnv 注册一个 `gym.make("HomeEnv-v0")`，数据合成与训练直接按 Gym 环境接入。

### 1.1 最小心智模型

```
env             训练循环持有的环境对象
reset()         开始或重开一局（episode），返回初始观测
step(a)         执行动作 a，推进世界，返回下一步观测与结果
observation     智能体能看到的状态信息
action          智能体发出的动作
reward          这一步的环境反馈信号
terminated      回合因任务本身结束（目标达成或失败）
truncated       回合因外部限制被截断（超时或步数上限）
info            辅助信息（指标、诊断、额外上下文）
spaces          声明动作与观测的结构与取值范围
seed            决定环境随机性，保证同 seed 可复现
episode/rollout 从 reset 到 terminated/truncated 的一段交互
```

`terminated` 与 `truncated` 的区分在 RL 里有实际意义：`terminated` 表示环境本身结束，后续价值视为零；`truncated` 表示只是被时间或步数截断，价值估计通常还要继续 bootstrap。Gymnasium 用五元组返回，正是为了把这两件事分开。

### 1.2 Gymnasium 与 OpenAI Gym

```
OpenAI Gym：最初的接口库，2021 年前后停止主要维护
Gymnasium：社区延续版本，目前是主流替代

旧 API：obs, reward, done, info = env.step(action)
新 API：obs, reward, terminated, truncated, info = env.step(action)

旧 API：obs = env.reset()
新 API：obs, info = env.reset(seed=seed)
```

本文后面的“Gym 接口要求”采用 Gymnasium 的五元组语义：它兼容当前生态，也与 HomeFlow 附录 A.3 的写法一致。

### 1.3 它与“世界模型”的关系

这两个概念经常被混在一起。分开看是三样东西：

```
沙盒/仿真器（SimuHome、HomeEnv）：提供世界本身及其动力学
Gym 接口：规定训练循环怎么调用这个世界
世界模型（learned world model）：智能体从数据中学出来的环境动力学
```

Gym 接口本身不做环境学习，也不预测未来，它只是协议层。世界模型是 model-based RL 里的一类算法组件：智能体从经验中学习环境如何演化，再在学到的模型里训练策略。即便如此，世界模型收集数据、做最终验证时，仍然需要对上 Gym 这类环境接口。

我们的方案属于“沙盒提供可控动力学 + Gym 暴露给 RL 训练”。它不要求先训练一个世界模型；将来若引入 model-based RL，学到的模型也可以按 Gym 风格 rollout 和评测。更准确的表述是：做 RL 沙盒通常要对上 Gym 接口，世界模型是可选算法组件，Gym 接口本身不是世界模型。

### 1.4 为什么智能家居论文要用它

```
训练侧：一次 reset 产生一个家庭 episode；
        一次 step 是一个高层家居决策；
        reward 从环境状态计算；
        terminated 对应任务目标达成；
        大量 episode 与并行 worker 支撑 RL 采样。

评测侧：同一接口可以被 benchmark 脚本调用，
        训练与评测共享同一套环境口径。

迁移侧：Gym 负责沙盒内的训练与离线评测；
        真实 Home Assistant 侧挂同语义的 MCP 工具，
        两边共享动作与观测定义。
```

## 2. 定位

本文只做对照：Gym 风格环境接口要求什么，SimuHome 当前代码提供什么，差距落在哪一层。改造方案见同目录下另外两份文档，这里不展开怎么改。

结论先行：SimuHome 当前对外契约是“客户端到服务”（LLM 通过 HTTP 工具调一个正在自运行的模拟器）；Gym 风格接口要求的是“训练循环到环境实例”（reset/step 控制一个可反复开始的独立世界）。两者在“设备、环境量、时间演化”上的内核机制可以复用，但外层运行契约需要整体平移。

先用两个运行场景把这句话落到具体，后面所有差异都从这里展开。

## 3. 两个场景：同一内核，两种用法

场景 A 是 SimuHome 现在的用法（LLM demo 或评测），场景 B 是 RL 训练的用法。

```
场景 A：LLM 通过 HTTP 操作一个自己会走的家
  agent 想开客厅空调
    → 调 execute_command("ac_1", ...)        # 一次 HTTP 请求
    → 服务端把动作放入队列
    → 后台循环在某个 tick 消费，设备属性改变
    → 返回 success=True
  agent 若想知道温度，必须再调 get_room_states("living_room")
  两次调用之间，世界可能已经自己走了很多 tick

场景 B：RL 训练循环操作一个随自己走的家
  trainer 想开客厅空调
    → obs, reward, terminated, truncated, info = env.step(open_ac)
    → 这一次调用内部完成：动作执行 + 时间推进到可判定点
    → trainer 拿到的 obs 就是“动作已经产生后果”之后的世界状态
  trainer 不需要第二次查询，也不需要等后台
```

两个场景共用一个内核：房间、设备、温度聚合、tick 演化都在其中。差异在“谁驱动、怎么调用、调用后拿到什么”。

## 4. Gym 接口要求的机制内涵

Gym 环境的最小生命周期约定是：

```python
env = SomeEnv(...)
# 创建一个环境实例；每个实例对应一个独立的世界

obs, info = env.reset(seed=seed, options=options)
# reset：开始一个新 episode（一局）
#   seed    固定环境随机性，保证同一 seed 得到同一初始世界
#   options 传入本局的场景、难度、目标条件等可选配置
#   返回本局第一帧观测 obs，以及额外信息 info

while True:                                    # 一局内的决策循环
    action = policy(obs)
    # 策略只依据当前观测 obs 选择动作；
    # policy 不直接读取环境内部状态，这是部分可观测的接口约束

    obs, reward, terminated, truncated, info = env.step(action)
    # step：执行动作并推进世界，一次性返回下一步的全部结果
    #   obs        动作生效后的新观测
    #   reward     这一步的环境反馈，由状态或目标条件计算
    #   terminated 回合因任务本身结束（目标达成或失败）
    #   truncated  回合因超时、步数上限等外部限制被截断
    #   info       辅助信息：诊断、日志、额外指标

    if terminated or truncated:
        break                                  # 本局结束后跳出，等待下一次 reset
```

这段循环的机制可以概括成四步：reset 创建或重开世界，policy 依据观测决策，step 执行动作并推进世界，terminated/truncated 判断本局是否结束。RL 训练器反复运行这个循环，采集 `(obs, action, reward, next_obs, terminated/truncated)` 用于学习；一个模拟器能稳定接入这段循环，就能被标准训练与评测流程使用。SimuHome 当前缺的正是能放进这段循环的位置。

这组接口背后还隐含六项机制要求：

```
同步：env.step 返回时，世界已到达该动作的下一个可判定时刻
单点控制：环境推进只由调用方驱动，环境自己不能私跑时间
实例化：每个 env 对象是一个独立世界，reset 反复产生新 episode
可复现：seed 决定初始状态，同一 seed 得到相同 rollout
完整信号：每次 step 都给出 reward、terminated、truncated、info
空间声明：action_space / observation_space 描述允许动作与观测结构
```

其中同步与单点控制最根本：RL 依赖形如 `(state, action, next_state, reward)` 的 transition 做训练，如果下一次状态不在 step 返回时确定下来，transition 就拼不出来。

## 5. Gym 约定之后，强化学习怎么进行

上一节那张图只画了环境这一侧：reset 开局、step 交互、结束关闭。RL 算法要做的，是反复运行这条交互链，再从产生的经验中改进策略。整个过程可以拆成两个嵌套的循环。

```
环境循环（产生经验）：
  reset → step → step → ... → terminated / truncated

学习循环（消费经验）：
  从整段经验中估计回报 → 更新策略或价值函数 → 回环境采样新经验
```

### 5.1 伪代码：与环境交互，采集训练样本

```python
buffer = []                          # 存放训练样本的集合

for episode in range(num_episodes):  # 反复进行一局又一局
    obs, info = env.reset(seed=...)
    # 开始新一局：环境给出初始观测

    done = False
    while not done:                  # 本局内一步步决策
        action = policy.sample(obs)
        # 依据当前策略采样动作；训练时会保留探索性

        next_obs, reward, terminated, truncated, info = env.step(action)
        # 环境执行动作、推进世界，返回这一步的完整结果

        buffer.append({
            "obs": obs, "action": action, "reward": reward,
            "next_obs": next_obs,
            "terminated": terminated, "truncated": truncated,
        })
        # 一条 (状态, 动作, 奖励, 下一状态, 结束标志) 就是 RL 的学习样本

        obs = next_obs               # 推进到下一步观测
        done = terminated or truncated
```

这段循环对应上一节图的完整生命周期：`reset` 开局，`step` 反复产生 transition，`terminated/truncated` 结束本局。环境负责把每一步的状态变化和奖励如实给出，策略在这里只负责选择动作、收集经验。

### 5.2 追问：next_obs 是怎么在这一步得到的

Gym 只规定 `env.step(action)` 必须返回 `next_obs`，并不替环境计算它。`next_obs` 是具体环境实现者在 step 返回之前生成的。一个 step 内部通常发生四件事：

```
① 执行动作     s_t  ──action──>  s_t+1
② 推进世界     让动作的后果发生（时间前进若干 tick）
③ 生成观测     next_obs = observe(s_t+1)
④ 计算反馈     reward, terminated, truncated = evaluate(...)

然后环境一次性返回：
  (next_obs, reward, terminated, truncated, info)
```

用温度任务把一个 step 展开：

```
动作：打开客厅空调，目标设为 24°C

① 设备状态变化：ac_1 从 off 变为 on，setpoint 变为 24
② 世界推进：温度聚合器逐 tick 把客厅从 30.0 向 24.0 拉
③ 生成观测：读取此刻的房间环境量与关心的设备状态
     next_obs = {"living_room": {"temperature": 29.4},
                 "ac_1": {"on": true, "setpoint": 24}}
④ 计算反馈：目标条件尚未满足
     reward = 0/2, terminated = False, truncated = False
```

时间关系可以画成：

```
时刻 t                         step 内部                         时刻 t+1

obs_t ──policy──> action ──> 执行动作 ──> 世界推进 ──> next_obs
                                                     ├──> reward
                                                     └──> terminated / truncated
```

这里有三个容易误解的点。

Gym 不替环境算 `next_obs`，它只规定返回格式。环境可以按自己的方式生成观测：直接读模拟器内部状态、经过噪声模型模拟传感器、只返回本次工具调用的执行结果，都算合法实现。HomeFlow 的执行沙箱属于最后一种：动作是执行一段操作，observation 只包含该次执行的直接结果，完整状态要靠下一次查询动作获取。

`next_obs` 不要求等于世界的完整状态。内部 `state` 是环境掌握的全部信息，`observation` 是 agent 能看到的部分。智能家居里，内部状态可能包含所有房间的温度、所有门的状态；`next_obs` 可能只给本次动作影响到的那间房，拓扑信息留着等 agent 查询。

“这一步”覆盖多长时间由环境定义。step 内推进 1 个 tick、60 个 tick 还是直到任务到点，决定了 `next_obs` 是动作后 0.1 秒、1 分钟还是 20 分钟的世界。粒度定下来以后，同一动作的 `next_obs` 才可比较，`buffer` 里的 transition 才稳定。

回到 SimuHome：当前动作返回 `success=True` 只说明命令被接受，房间环境量要等后续 tick 才更新，`next_obs` 需要第二次查询才能拿到，而且查询时刻由客户端决定。接入 Gym 后，step 内部统一完成“执行动作 → 推进世界 → 生成 next_obs”，`next_obs` 与 `action` 一一对应，这才形成可训练的学习样本。

换个角度看 `obs` 与 `next_obs` 的关系，更容易建立直觉：

```
reset → obs_0 ──a_0──> step ──> next_obs_1 ──a_1──> step ──> next_obs_2 → ...
                              ↑                       ↑
                        这一步的输出             下一步的 obs

循环中的 `obs = next_obs` 做的就是这个交接：
上一次 step 返回的 next_obs，在下一轮成为决策用的 obs。
```

`obs` 与 `next_obs` 是同一条观测流上相邻的两帧，命名是相对同一个动作的“执行前 / 执行后”。说“obs 来自上一步、next_obs 生自这一步”在时间归属上成立；更精确的说法是：`obs` 是本次决策已知的观测（第一轮来自 reset），`next_obs` 是本次动作执行并推进世界之后生成的观测，同时会成为下一步的 `obs`。同一条 buffer 记录里的 `obs` 与 `action` 属于动作前，`reward` 与 `next_obs` 属于动作后。

### 5.3 伪代码：从经验中更新策略

```python
for batch in sample_batches(buffer):     # 从经验中取一批样本
    returns = compute_returns(batch)
    # 用奖励序列计算每个动作的后续回报；
    # terminated 处分价值归零，truncated 处通常还要继续估计后续价值

    log_probs = policy.log_prob(batch.obs, batch.action)
    # 计算当前策略当时选择这些动作的概率

    loss = -(log_probs * advantages).mean()
    # 回报高于预期的动作提高概率，低于预期的动作降低概率

    optimizer.zero_grad()
    loss.backward()
    optimizer.step()
    # 更新策略参数，下一次采样时策略会有所不同
```

上面两段拼起来，就是 RL 最基本的“采样—学习—再采样”闭环。不同算法改动的是第二段：环境接口本身不随算法变化。

### 5.4 为什么 truncated 还要“估计后续价值”

“一条样本完全跑完了，后续回报自然知道”这个前提只在 `terminated` 时成立。`truncated` 的含义是采样被外部限制停了下来，任务本身没有结束：

```
truncated：
  ... → s_T ──?──> r_{T+1} ──?──> r_{T+2} → ...
        采样在这里停止
        后面的奖励真实存在，只是这次没有采到

terminated：
  ... → s_T（terminal）
        任务到此结束，后面不再有奖励
```

所以计算回报时两者处理不同：

```
terminated：G_T = 0
            终止之后没有奖励，价值归零，不需要再估计

truncated ：G_T ≈ r_T + γ·r_{T+1} + ... + γ^n·V(s_{T+n})
            已经采到的奖励照常求和，
            截断之后的部分用价值函数 V 估计还会拿到多少回报
```

举一个具体例子：

```
任务：10 分钟内让厨房降到 24°C
到第 10 分钟时厨房是 25°C，环境把本局 truncated

如果直接把 25°C 之后的回报当成 0，策略会学到
“停在 25°C 和彻底失败一样”，训练信号是错的；
用 V(next_obs) 估计“继续等一分钟可能就达标”，
这个样本的回报估计才接近真实情况。
```

常见实现会分开使用两个标志：

```
continue_flag   = not (terminated or truncated)  # 要不要继续采样
bootstrap_flag  = not terminated                 # 要不要用 V(next_obs) 估计后续
```

TD 误差里也能看到这个差别：

```
δ_t = r_t + γ · V(next_obs) · (1 - terminated) - V(obs)
# truncated 不切断 V(next_obs)，terminated 才把后续价值切断
```

### 5.5 不同 RL 算法改的是哪一段

```
value-based（DQN 一类）：
  额外学习 Q(s,a)，用下一状态的 Q 值构造更新目标；
  采样循环与 Gym 接口完全不变。

policy-based（REINFORCE / PPO / GRPO 一类）：
  直接更新动作概率；PPO 限制新旧策略差异，
  GRPO 用一组样本的相对好坏代替价值函数。

actor-critic（A2C / SAC 一类）：
  策略网络负责选动作，价值网络负责估计回报，两者联合更新。

model-based（Dreamer / MuZero 一类）：
  先用 buffer 训练一个世界模型，再让策略在模型里做想象 rollout；
  最终仍要回到真实环境按 Gym 接口做评测。
```

### 5.6 回到智能家居沙盒

这段训练循环对环境的全部要求，就是上一节图里的那几项：能 reset、能 step、能给出观测与奖励、能标明回合何时结束。训练算法不需要知道世界内部有多少房间、多少设备、温度怎么聚合。只要 SimuHome 对接上 Gym 接口，这类算法就能直接在上面采样和训练；沙盒提供动力学与奖励，算法提供策略更新。HomeFlow 的 SFT + stepwise RLVE 也是在同一套循环上叠加数据合成与逐步奖励，没有改变这个基本结构。

## 6. SimuHome 当前的运行时契约

SimuHome 现在按“服务型智能体工具链”组织，运行链路是：

```
LLM / 评测脚本
  → SmartHomeClient（HTTP 客户端）
  → FastAPI route
  → Home.queue_api() 排队
  → 后台 simulation loop 在某个 tick 消费
  → Result 经 threading.Event 返回
```

它的时间机制值得细看：Home 一旦启动，后台循环就按 tick_interval 自行推进，即使 agent 什么都不做，房间温度也会向基线回归、到点 workflow 也会触发。对外看来，agent 是在“操作一个自己会走的家”，而不是在“驱动一个等自己下指令的家”。

一次命令往返的时序可以画成：

```
agent 发命令                → 服务端收到并排队
后台循环消费（时机不确定）   → 设备属性改变
响应返回 agent              → 得到 success=True
agent 再查询               → 世界已经又走了若干 tick
```

注意中间两段时间都不由 agent 控制：动作何时被消费取决于队列处理节奏，动作生效后世界又演化多久取决于 agent 下一次查询的时机。这是与 Gym 最根本的运行差异。

## 7. 逐条差异

### 7.1 reset：服务重启 vs 环境实例重开

```
Gym 要求：
  env = MyHomeEnv()
  obs, info = env.reset(seed=7)      # 新 episode
  obs, info = env.reset(seed=8)      # 立刻换初始世界，不重启服务
  reset 属于环境实例；多个 env 可各自处于不同 episode

SimuHome 现状：
  reset_simulation 是 HTTP 端点，作用于全局单例 home
  机制 = 停后台循环 → 新建 Home → 填充房间/设备 → 再启动循环
  另一个客户端在同一时刻 reset，会影响这个共享实例
```

一个直观类比：Gym 的 reset 像“同一台跑步机调一次坡度重新跑”，SimuHome 的 reset 像“拆掉整台跑步机重新组装”。后者也能完成，但它是服务级重建，成本高且不能并发。RL 的 episode 数以万计，若每次 reset 都要走一次服务级重建，训练基础设施会变成瓶颈。

### 7.2 step：不存在 vs 步进同步返回

```
Gym 要求：
  obs, reward, terminated, truncated, info = env.step(action)
  一次调用同时完成“执行动作”和“得到下一步状态”

SimuHome 现状：
  没有 step 语义
  动作通过 queue_api 异步投递，threading.Event 等待结果
  时间由后台循环自驱，不随调用方步进
```

把场景 A 里的“开空调”补完就能看到差距：Gym 一次 step 后，obs 已经告诉你温度在往哪个方向走；SimuHome 中，成功响应只说明“命令被接受”，温度是否变化、变化多少，是下一次查询才知道的事。即使命令立刻生效，agent 也拿不到一个被明确定义为“该动作后的世界状态”。

对 RL 的影响是直接的：transition 里的 next_state 没有稳定来源，policy 也就无法获得可靠的训练样本。

### 7.3 action：HTTP 工具 vs 动作空间

```
Gym 要求：
  action_space 声明动作结构与取值约束
  每个 step 恰好消费一个 action
  policy 网络知道输出什么范围的动作，环境对非法动作给反馈

SimuHome 现状：
  已有 execute_command / write_attribute / schedule_workflow /
  查询等高层工具
  参数约束分散在各 HTTP request model 中，由服务端逐请求校验
```

SimuHome 工具本身的语义离 Gym 动作不远：控制类动作改变设备，查询类动作读状态，调度类动作登记未来任务。差距主要在两点：动作没有与 step 绑定，policy 不能保证“每发一次动作，世界就前进一个可学习的节拍”；动作格式由服务契约决定，而不是由训练算法需要的 action_space 决定。把现成工具收敛成一组稳定 schema 并不困难，但当前代码里还没有这层声明。

### 7.4 observation：自由快照 vs 受控观测

```
Gym 要求：
  observation_space 声明观测结构
  agent 只能拿到 env 给出的 obs，不能自己决定“现在看全量还是看局部”

SimuHome 现状：
  get_home_state 可一次返回全屋完整快照
  get_room_states / get_device_attributes 可按需局部查询
  观测内容由客户端自己决定调哪个接口、拼什么格式
```

SimuHome 的问题是权限与口径：agent 可以自由选择“全看”或“看一部分”，这更适合交互式评测，但对 RL 不友好。策略网络的输入格式必须固定，如果同一时刻两种 agent 看到不同结构的 obs，模型就没法训练。

另一个机制层面的问题更隐蔽：如果 reset 后第一帧 obs 就包含完整拓扑和每台设备属性，空间任务就失去意义。模型不需要查询，直接按全图做规划即可；它永远学不会“先勘察再行动”。Gym 的 obs 边界恰好能约束这一点：初始只给概览，详情由查询动作提供。

### 7.5 reward / terminated / truncated：结果状态 vs 回合信号

```
Gym 要求：
  step 返回 reward、terminated、truncated
  terminated 表示目标达成或世界终结
  truncated 表示超时、步数耗尽等外部截断
  reward 由环境根据状态计算

SimuHome 现状：
  Result 携带 success/error，说明动作/请求是否成功
  workflow 有 pending/running/completed/failed，说明流程是否走完
  房间聚合器维护 current_value，时钟由 current_tick 维护
  但没有“目标状态是否满足”的通用判定
```

用温度任务说明层级差别：agent 把空调设到 24°C，服务端返回 success=True，这只证明“设置动作合法”；十分钟后房间是不是真的到 24°C，属于状态层问题，现有机制不负责回答。RL 真正需要的是后者，并且需要在每个 step 都能拿到中间状态：是 26°C、25°C，还是已经到 24°C。

目标可以这样表达，以帮助理解 reward 的来源：

```
goal = [
    kitchen.temperature ∈ [23, 25],
    bedroom.temperature ≤ 28,
    deadline_tick = 12000
]

每个 step 后：
  reward     = 满足条件数 / 条件总数
  terminated = 全部条件满足
  truncated  = 超过 deadline 或步数耗尽
```

SimuHome 当前没有这层“状态条件到回合信号”的映射，这是五个差异里最需要新增的一环。

### 7.6 并行与可复现：全局单例 vs 独立实例

```
Gym 要求：
  reset 带 seed；同一 seed 得到同一初始世界
  多个 env 实例可并行，vector env 由独立环境对象组成

SimuHome 现状：
  HTTP 服务层使用全局单例 home
  重置是服务级操作，多个训练进程无法各持一个世界
  场景由手工 SimulationConfig 提供，没有随机种子语义
```

RL 训练对“多样初始状态”的需求量很大。HomeFlow 的规模化训练以 10,000 个独立基础配置起步，正是为了从不同房屋布局与设备组合中采样。SimuHome 若靠手工 JSON 配置一个接一个地跑，无法支撑这种规模；每个 worker 都应能从 seed 独立构造自己的世界。当前代码里场景描述与运行实例已经分开存放（配置与 Home 对象），但运行实例仍与全局服务绑在一起，所以机制上还差“按 seed 构造独立实例”这一步。

## 8. 差异汇总

```
对比项        Gym 接口要求               SimuHome 现状           差异落点
reset         env.reset → obs/info       HTTP 停旧建新并启线程    生命周期
step          同步五元组返回             无 step；queue 异步       时间控制权
action        action_space + step 绑定   高层 HTTP 工具           表示与推进耦合
observation   受控 obs / observation_space 全量或按房间自由读取   暴露口径
reward/终止   reward/terminated/truncated Result 与 workflow 状态   回合级信号缺失
并行复现      独立 env 实例 + seed        全局单例 + 手工 config    实例隔离
```

## 9. 差异归因

这些差异同根：SimuHome 为“LLM 通过 HTTP 工具在真实时间里操作一台模拟器”设计，Gym 为“训练循环直接驱动一个可反复开始的模拟世界”设计。前一种契约要求世界自己转、命令排队进；后一种契约要求世界随训练循环走、命令在 step 内生效。

可复用的部分：设备-聚合器-房间环境的三层演化、tick 推进、workflow 调度与 fast_forward，都是内核机制，Gym 化不需要重做。

需要平移的部分：环境的实例生命周期（reset 归属环境对象）、同步步进入口（step）、动作与步进的绑定、观测口径的固定、回合级状态判定的产出，以及 seed 化的场景构造。

因此差异的性质可以概括为：SimuHome 有 Gym 需要的世界内核，缺的是 Gym 需要的外部契约层；差距集中在“服务型运行方式”与“环境实例型运行方式”之间，改动面是外层而不是物理模型。这正好对应同目录《沙盒轻量化设计分析》中的“一个同步内核、两个门”思路，以及《沙盒支持强化学习的五个条件分析》里五个机制的改造顺序。
